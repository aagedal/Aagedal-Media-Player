// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Libmpv
import XCTest
@testable import Aagedal_Media_Player

/// Real libmpv/FFmpeg metadata versus the existing source-meter DSP. These
/// generated signals qualify the comparison probe, not compressed-source QC,
/// physical output latency, or a replacement for source timestamp provenance.
final class MPVNativeAudioMeterIntegrationTests: XCTestCase {
    func testNativeFiltersAgainstExistingDSPAndSparsePolling() async throws {
        guard ProcessInfo.processInfo.environment["AAGEDAL_MPV_AUDIO_PROBE_TESTS"] == "1" else {
            throw XCTSkip("Set AAGEDAL_MPV_AUDIO_PROBE_TESTS=1 with the verified audio-filter overlay")
        }
        XCTAssertTrue(MPVNativeAudioMeter.filtersAvailable)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [(String, Int, LiveAudioMeterFormat.Layout, UInt32)] = [
            ("mono-44", 44100, .mono, 0x4),
            ("stereo-48", 48000, .stereo, 0x3),
            ("stereo-96", 96000, .stereo, 0x3),
            ("surround", 48000, .surround5Point1, 0x60f),
            ("rear-71", 48000, .surround7Point1, 0x63f),
            ("lfe", 48000, .surround5Point1, 0x60f),
            ("silence", 48000, .stereo, 0x3),
            ("transient", 48000, .stereo, 0x3),
            ("intersample", 48000, .stereo, 0x3)
        ]
        var results: [[String: Any]] = []
        for (name, rate, layout, mask) in cases {
            let format = try LiveAudioMeterFormat(sampleRate: rate, layout: layout)
            let pcm = signal(name: name, rate: rate, channels: format.channelCount)
            let url = directory.appendingPathComponent(name + ".wav")
            try wave(pcm, rate: rate, channels: format.channelCount, mask: mask).write(to: url)
            let context = try makePlayer()
            defer { mpv_terminate_destroy(context) }
            let outputs = (0..<format.channelCount).map { "c\($0)=\($0 == 0 ? "0*" : "")c\($0)" }.joined(separator: "|")
            XCTAssertTrue(MPVNativeAudioMeter.command(context, ["af", "add", "@probe-route:lavfi=[pan=\(format.channelCount)c|\(outputs)]"]))
            XCTAssertTrue(MPVNativeAudioMeter.command(context, ["af", "pre", MPVNativeAudioMeter.filter]))
            XCTAssertTrue(MPVNativeAudioMeter.command(context, ["loadfile", url.path, "replace"]))
            // Ordinary polling. Each reading covers the timestamped frames the
            // audio clock reached since the previous one, so the brief early
            // transient must survive in the aggregated maxima.
            var history = MPVNativeAudioMeterHistory(channels: format.channelCount, sampleRate: rate)
            var readings: [MPVNativeAudioMeter.Reading] = []
            for _ in 0..<160 where (readings.last?.filterFrames ?? 0) < Int64(rate * 3) {
                if let reading = MPVNativeAudioMeter.read(context, history: &history) { readings.append(reading) }
                try await Task.sleep(for: .milliseconds(50))
            }
            let reading = try XCTUnwrap(readings.last, name)
            XCTAssertFalse(history.needsFilterRestart, "\(name): \(history.lastFailure ?? "")")
            XCTAssertEqual(reading.historyRestarts, 0, name)
            XCTAssertTrue(zip(readings, readings.dropFirst()).allSatisfy {
                $0.measuredUntil < $1.measuredUntil && $0.filterFrames < $1.filterFrames
            }, name)
            XCTAssertGreaterThan(readings.count, 20, "\(name): readings arrive as the clock advances")
            XCTAssertGreaterThanOrEqual(reading.filterFrames, Int64(rate * 3), name)
            XCTAssertLessThanOrEqual(reading.filterFrames, Int64(rate * 4), name)
            var dsp = try LiveAudioMeterDSP(format: format, startFrame: 0)
            var snapshots: [LiveAudioMeterSnapshot] = []
            let frames = min(Int(reading.filterFrames), pcm.count / format.channelCount)
            for frame in stride(from: 0, to: frames, by: rate / 20) {
                let end = min(frame + rate / 20, frames)
                let block = pcm[(frame * format.channelCount)..<(end * format.channelCount)]
                    .map { Float($0) / 32768 }
                snapshots += try dsp.process(block, startFrame: Int64(frame))
            }
            let reference = try XCTUnwrap(snapshots.last { $0.loudnessEndFrame == reading.filterFrames }, name)
            // The final reading's RMS covers only the frames after the previous reading.
            let windowStart = Int(readings.dropLast().last?.filterFrames ?? 0)
            for channel in 0..<format.channelCount {
                let expected = reference.maximumSamplePeakDBFS[channel]
                let energy = stride(from: windowStart * format.channelCount + channel,
                                    to: frames * format.channelCount, by: format.channelCount)
                    .reduce(0.0) { sum, offset in
                        let sample = Double(pcm[offset]) / 32768
                        return sum + sample * sample
                    }
                if energy == 0 {
                    XCTAssertEqual(reading.rms[channel], -.infinity, name)
                } else {
                    XCTAssertEqual(reading.rms[channel], 10 * log10(energy / Double(frames - windowStart)),
                                   accuracy: 0.01, name)
                }
                if expected == -.infinity {
                    XCTAssertEqual(reading.maximumSamplePeaks[channel], -.infinity, name)
                    XCTAssertNil(reading.truePeaks[channel], name)
                } else {
                    XCTAssertEqual(reading.maximumSamplePeaks[channel], expected, accuracy: 0.001, "\(name)/\(channel)")
                    XCTAssertEqual(try XCTUnwrap(reading.truePeaks[channel]), reference.maximumTruePeakDBTP[channel],
                                   accuracy: 0.4, "\(name)/\(channel)")
                }
            }
            if name == "silence" || name == "lfe" {
                XCTAssertEqual(reference.momentaryLUFS, -.infinity, name)
                XCTAssertLessThan(try XCTUnwrap(reading.momentary), -100, name)
            } else if name == "rear-71" {
                // This difference is an existing, documented source-QC
                // correction. Raw native loudness must not replace it silently.
                XCTAssertEqual(try XCTUnwrap(reading.momentary) - XCTUnwrap(reference.momentaryLUFS),
                               10 * log10(1.41), accuracy: 0.1)
            } else {
                XCTAssertEqual(try XCTUnwrap(reading.momentary), try XCTUnwrap(reference.momentaryLUFS), accuracy: 0.1, name)
                XCTAssertEqual(try XCTUnwrap(reading.shortTerm), try XCTUnwrap(reference.shortTermLUFS), accuracy: 0.1, name)
            }
            if name == "transient" {
                XCTAssertGreaterThan(reading.maximumSamplePeaks[0], -2)
                XCTAssertGreaterThan(readings.map { $0.samplePeaks[0] }.max() ?? -.infinity, -2,
                                     "One reading's own peak holds the transient")
            }
            if name == "intersample" {
                XCTAssertGreaterThan(try XCTUnwrap(reading.truePeaks[0]), reading.maximumSamplePeaks[0] + 1)
            }
            results.append(["signal": name, "rate": rate, "channels": format.channelCount,
                            "filterFrames": reading.filterFrames, "measuredUntil": reading.measuredUntil,
                            "readings": readings.count, "framesPerReading": Double(readings.map(\.frameCount).reduce(0, +)) / Double(readings.count),
                            "samplePeaks": reading.maximumSamplePeaks.map { String($0) },
                            "nativeTruePeaks": reading.truePeaks.map { $0.map { String($0) } ?? "below metadata precision" },
                            "referenceTruePeaks": reference.maximumTruePeakDBTP.map { String($0) },
                            "nativeM": String(reading.momentary ?? .nan),
                            "referenceM": String(reference.momentaryLUFS ?? .nan)])
            // Remove only our filter, keep an unrelated routing filter alive,
            // and verify that a subsequent exact seek really resumes decoding.
            while let event = mpv_wait_event(context, 0), event.pointee.event_id != MPV_EVENT_NONE {}
            XCTAssertTrue(MPVNativeAudioMeter.command(context, ["af", "remove", "@\(MPVNativeAudioMeter.label)"]))
            var filters = mpv_node()
            XCTAssertGreaterThanOrEqual(mpv_get_property(context, "af", MPV_FORMAT_NODE, &filters), 0)
            let filterString = try XCTUnwrap(mpv_get_property_string(context, "af"))
            let filterText = String(cString: filterString)
            mpv_free(filterString)
            mpv_free_node_contents(&filters)
            XCTAssertTrue(filterText.contains("probe-route"), name)
            XCTAssertFalse(filterText.contains(MPVNativeAudioMeter.label), name)
            XCTAssertTrue(MPVNativeAudioMeter.command(context, ["seek", "0.5", "absolute+exact"]))
            XCTAssertTrue(MPVNativeAudioMeter.command(context, ["set", "pause", "no"]))
            var resumed = false
            for _ in 0..<100 {
                let event = mpv_wait_event(context, 0)
                if event?.pointee.event_id == MPV_EVENT_PLAYBACK_RESTART { resumed = true; break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(resumed, name)
            var removed = MPVNativeAudioMeterHistory(channels: format.channelCount, sampleRate: rate)
            XCTAssertNil(MPVNativeAudioMeter.read(context, history: &removed))
            if name == "transient" {
                // A fresh filter after an exact seek past the transient cannot
                // republish the old maximum or completed S window.
                XCTAssertTrue(MPVNativeAudioMeter.command(context, ["seek", "2", "absolute+exact"]))
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertTrue(MPVNativeAudioMeter.command(context, ["af", "pre", MPVNativeAudioMeter.filter]))
                var restarted = MPVNativeAudioMeterHistory(channels: format.channelCount, sampleRate: rate)
                var fresh: MPVNativeAudioMeter.Reading?
                for _ in 0..<20 where fresh == nil {
                    try await Task.sleep(for: .milliseconds(50))
                    fresh = MPVNativeAudioMeter.read(context, history: &restarted)
                }
                let first = try XCTUnwrap(fresh)
                XCTAssertLessThan(first.filterFrames, Int64(rate))
                XCTAssertNil(first.shortTerm)
                XCTAssertLessThan(first.maximumSamplePeaks[0], -20)
                XCTAssertGreaterThanOrEqual(first.measuredUntil, 2)
            }
        }
        let report = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
        attachment.name = "Native audio probe versus source DSP"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MPV_NATIVE_AUDIO_PROBE_ACCEPTANCE: \(results.count) signals; timestamped history, units, source-DSP comparison, removal and seek")
    }

    private func makePlayer() throws -> OpaquePointer {
        let context = try XCTUnwrap(mpv_create())
        for (name, value) in [("vo", "null"), ("ao", "null"), ("audio-channels", "auto"),
                              ("keep-open", "yes"), ("load-scripts", "no"), ("config", "no"),
                              ("volume", "0"), ("mute", "yes")] {
            XCTAssertGreaterThanOrEqual(mpv_set_option_string(context, name, value), 0, name)
        }
        XCTAssertGreaterThanOrEqual(mpv_initialize(context), 0)
        return context
    }

    private func signal(name: String, rate: Int, channels: Int) -> [Int16] {
        (0..<(rate * 4)).flatMap { frame in
            (0..<channels).map { channel -> Int16 in
                let amplitude: Double
                switch name {
                case "silence": amplitude = 0
                case "lfe": amplitude = channel == 3 ? 0.5 : 0
                case "rear-71": amplitude = channel == 4 ? 0.5 : 0
                case "transient": amplitude = (frame >= rate / 5 && frame < rate / 5 + 480) ? 0.9 : 0.05
                case "intersample":
                    if frame >= rate / 5 && frame < rate / 5 + 480 {
                        return Int16((frame % 4 < 2 ? 0.8 : -0.8) * 32767)
                    }
                    amplitude = 0.05
                default: amplitude = Double(channel + 1) / Double(channels + 1) * 0.5
                }
                return Int16((amplitude * sin(2 * .pi * 1000 * Double(frame) / Double(rate)) * 32767).rounded())
            }
        }
    }

    private func wave(_ pcm: [Int16], rate: Int, channels: Int, mask: UInt32) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(60 + pcm.count * 2)); text("WAVEfmt "); u32(40)
        u16(0xfffe); u16(UInt16(channels)); u32(UInt32(rate)); u32(UInt32(rate * channels * 2))
        u16(UInt16(channels * 2)); u16(16); u16(22); u16(16); u32(mask)
        // KSDATAFORMAT_SUBTYPE_PCM, in WAVE GUID byte order.
        data.append(contentsOf: [1, 0, 0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113])
        text("data"); u32(UInt32(pcm.count * 2))
        for value in pcm { u16(UInt16(bitPattern: value)) }
        return data
    }
}
