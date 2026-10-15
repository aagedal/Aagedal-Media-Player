// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Libavfilter
import Libmpv

/// Development comparison probe, never a source-QC snapshot. af-metadata has
/// no frame timestamp and returns only the last frame. Cumulative filter peaks
/// survive missed polls; RMS is explicitly the average since filter reset.
nonisolated enum MPVNativeAudioMeter {
    static let label = "amp-native-audio-probe"
    static let filter = "@\(label):lavfi=[ebur128=metadata=1:peak=true:framelog=verbose,"
        + "astats=metadata=1:reset=0:measure_perchannel=Peak_level+RMS_level:measure_overall=Number_of_samples]"

    struct Reading: Equatable, Sendable {
        let samplePeaks: [Double]
        let rms: [Double]
        /// Nil means below the metadata's linear-amplitude rounding precision.
        let truePeaks: [Double?]
        let momentary: Double?
        let shortTerm: Double?
        let filterFrames: Int64
        /// Player clock at query time, NOT the PTS of these measurements.
        let queryPlaybackTime: Double
    }

    static var filtersAvailable: Bool {
        ["astats", "ebur128"].allSatisfy { name in
            name.withCString { avfilter_get_by_name($0) != nil }
        }
    }

    static func command(_ context: OpaquePointer, _ arguments: [String]) -> Bool {
        let strings = arguments.map { strdup($0)! }
        defer { strings.forEach { free($0) } }
        var pointers = strings.map { Optional(UnsafePointer($0)) } + [nil]
        return mpv_command(context, &pointers) >= 0
    }

    static func metadata(_ node: mpv_node) -> [String: String]? {
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list,
              list.pointee.num > 0, list.pointee.num <= 128,
              let keys = list.pointee.keys, let values = list.pointee.values else { return nil }
        var result: [String: String] = [:]
        for index in 0..<Int(list.pointee.num) {
            guard let key = keys[index], values[index].format == MPV_FORMAT_STRING,
                  let value = values[index].u.string else { return nil }
            let name = String(cString: key)
            guard result[name] == nil else { return nil }
            result[name] = String(cString: value)
        }
        return result
    }

    static func decode(_ values: [String: String], channels: Int, sampleRate: Int,
                       queryPlaybackTime: Double) -> Reading? {
        guard (1...8).contains(channels), [44_100, 48_000, 96_000].contains(sampleRate),
              queryPlaybackTime.isFinite, queryPlaybackTime >= 0,
              let countText = values["lavfi.astats.Overall.Number_of_samples"],
              let count = Double(countText), count.isFinite, count > 0,
              count.rounded() == count, count < Double(Int64.max) else { return nil }
        let peakKeys = values.keys.filter {
            $0.hasPrefix("lavfi.astats.") && $0.hasSuffix(".Peak_level") && !$0.contains(".Overall.")
        }
        guard peakKeys.count == channels else { return nil }
        func db(_ key: String) -> Double? {
            guard let text = values[key] else { return nil }
            if text == "-inf" || text == "-Infinity" { return -.infinity }
            guard let number = Double(text), number.isFinite else { return nil }
            return number
        }
        var peaks: [Double] = [], rms: [Double] = [], truePeaks: [Double?] = []
        for index in 0..<channels {
            guard let peak = db("lavfi.astats.\(index + 1).Peak_level"),
                  let average = db("lavfi.astats.\(index + 1).RMS_level"),
                  let text = values["lavfi.r128.true_peaks_ch\(index)"],
                  let amplitude = Double(text), amplitude.isFinite, amplitude >= 0 else { return nil }
            peaks.append(peak); rms.append(average)
            // FFmpeg serializes these linear amplitudes to only three decimal
            // places. Zero therefore cannot distinguish silence from a tiny peak.
            truePeaks.append(amplitude == 0 ? nil : 20 * log10(amplitude))
        }
        guard let momentary = db("lavfi.r128.M"), let shortTerm = db("lavfi.r128.S") else { return nil }
        return Reading(samplePeaks: peaks, rms: rms, truePeaks: truePeaks,
                       momentary: count >= Double(sampleRate) * 0.4 ? momentary : nil,
                       shortTerm: count >= Double(sampleRate) * 3 ? shortTerm : nil,
                       filterFrames: Int64(count), queryPlaybackTime: queryPlaybackTime)
    }

    /// Used only on the owning MPVPlayer queue (or an isolated test context).
    static func read(_ context: OpaquePointer, channels: Int, sampleRate: Int) -> Reading? {
        var node = mpv_node()
        defer { mpv_free_node_contents(&node) }
        var time: Double = 0
        guard mpv_get_property(context, "time-pos", MPV_FORMAT_DOUBLE, &time) >= 0,
              mpv_get_property(context, "af-metadata/\(label)", MPV_FORMAT_NODE, &node) >= 0,
              let values = metadata(node) else { return nil }
        return decode(values, channels: channels, sampleRate: sampleRate, queryPlaybackTime: time)
    }
}
