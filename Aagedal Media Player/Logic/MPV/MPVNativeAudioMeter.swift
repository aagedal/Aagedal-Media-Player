// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Libavfilter
import Libmpv

/// Development comparison probe, never a source-QC snapshot. MPVKit's
/// `amc-meter-history` transport timestamps every filter output frame, so a
/// reading covers exactly the frames the audio clock has reached since the
/// previous one; `MPVNativeAudioMeterHistory` detects lost frames.
nonisolated enum MPVNativeAudioMeter {
    static let label = "amp-native-audio-probe"
    static let filter = "@\(label):lavfi=graph=[ebur128=metadata=1:peak=true:framelog=verbose,"
        + "astats=metadata=1:reset=1:measure_perchannel=Peak_level+RMS_level:measure_overall=none]"
        + ":amc-meter-history=yes"
    static let historyKey = "amc-meter-history-v1"

    struct Reading: Equatable, Sendable {
        /// Maximum over this reading's frames.
        let samplePeaks: [Double]
        /// Over this reading's frames.
        let rms: [Double]
        /// Every frame measured since the filter started.
        let maximumSamplePeaks: [Double]
        /// ebur128's maxima since the filter started. Nil means below the
        /// metadata's linear-amplitude rounding precision.
        let truePeaks: [Double?]
        let momentary: Double?
        let shortTerm: Double?
        /// Samples per channel measured since the filter started.
        let filterFrames: Int64
        /// Media time at which the newest included frame ends.
        let measuredUntil: Double
        /// Filter output frames aggregated into this reading.
        let frameCount: Int
        /// Filter restarts after lost or discontinuous history.
        let historyRestarts: Int
    }

    /// One filter output frame's own metadata (astats resets every frame).
    struct FrameMeasurement: Equatable, Sendable {
        let samplePeaks: [Double]
        let rms: [Double]
        let truePeaks: [Double?]
        let momentary: Double
        let shortTerm: Double
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

    static func decodeFrame(_ values: [String: String], channels: Int) -> FrameMeasurement? {
        guard (1...8).contains(channels) else { return nil }
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
        return FrameMeasurement(samplePeaks: peaks, rms: rms, truePeaks: truePeaks,
                                momentary: momentary, shortTerm: shortTerm)
    }

    /// Used only on the owning MPVPlayer queue (or an isolated test context).
    /// Reinstalls the filter when `history` reports lost frames. The clock is
    /// mpv's audio playback position, falling back to `time-pos` without one.
    static func read(_ context: OpaquePointer, history: inout MPVNativeAudioMeterHistory) -> Reading? {
        if history.needsFilterRestart {
            _ = command(context, ["af", "remove", "@\(label)"])
            guard command(context, ["af", "pre", filter]) else { return nil }
            history.restart()
            return nil
        }
        var node = mpv_node()
        defer { mpv_free_node_contents(&node) }
        guard mpv_get_property(context, "af-metadata/\(label)", MPV_FORMAT_NODE, &node) >= 0,
              let values = metadata(node), let json = values[historyKey] else { return nil }
        history.ingest(json: json)
        var clock: Double = 0
        guard mpv_get_property(context, "audio-pts", MPV_FORMAT_DOUBLE, &clock) >= 0
                || mpv_get_property(context, "time-pos", MPV_FORMAT_DOUBLE, &clock) >= 0 else { return nil }
        return history.reading(at: clock)
    }
}
