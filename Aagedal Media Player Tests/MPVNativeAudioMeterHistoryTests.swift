// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class MPVNativeAudioMeterHistoryTests: XCTestCase {
    func testFramesWaitForTheirEndAndReadingsAggregateEveryDueFrame() throws {
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: try snapshot(frames: [
            frame(1, peak: "-20", rms: "-30"), frame(2, peak: "-1", rms: "-30"), frame(3, peak: "-20", rms: "-20"),
        ]))
        XCTAssertNil(history.reading(at: 0.0999))
        let first = try XCTUnwrap(history.reading(at: 0.1))
        XCTAssertEqual(first.samplePeaks, [-20])
        XCTAssertEqual(first.measuredUntil, 0.1, accuracy: 0.000001)
        XCTAssertEqual(first.frameCount, 1)
        XCTAssertNil(history.reading(at: 0.15), "No new frame is due")
        // A gap in polling loses nothing: both frames arrive in one reading.
        let second = try XCTUnwrap(history.reading(at: 0.3))
        XCTAssertEqual(second.frameCount, 2)
        XCTAssertEqual(second.samplePeaks, [-1], "The transient between polls survives")
        XCTAssertEqual(second.rms[0], 10 * log10((pow(10, -3) + pow(10, -2)) / 2), accuracy: 0.0001)
        XCTAssertEqual(second.maximumSamplePeaks, [-1])
        XCTAssertEqual(second.filterFrames, 3 * 4800)
        XCTAssertEqual(second.measuredUntil, 0.3, accuracy: 0.000001)
        XCTAssertFalse(history.needsFilterRestart)
    }

    func testStaleFramesStillCountTowardMaximaButPublishNothing() throws {
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: try snapshot(frames: [frame(1, peak: "-2"), frame(2)]))
        XCTAssertNil(history.reading(at: 1), "Measurements 0.8 s old are not current")
        history.ingest(json: try snapshot(frames: [frame(1, peak: "-2")] + (2...11).map { frame($0) }))
        let reading = try XCTUnwrap(history.reading(at: 1.1))
        XCTAssertEqual(reading.samplePeaks, [-6])
        XCTAssertEqual(reading.maximumSamplePeaks, [-2])
        XCTAssertEqual(reading.filterFrames, 11 * 4800)
    }

    func testLoudnessWaitsForContinuousMeasuredHistory() throws {
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: try snapshot(frames: (1...30).map { frame($0) }))
        XCTAssertNil(try XCTUnwrap(history.reading(at: 0.3)).momentary)
        XCTAssertEqual(try XCTUnwrap(history.reading(at: 0.4)).momentary, -22)
        XCTAssertNil(try XCTUnwrap(history.reading(at: 2.9)).shortTerm)
        XCTAssertEqual(try XCTUnwrap(history.reading(at: 3)).shortTerm, -23)
    }

    func testRepeatedSnapshotsAndHarmlessEvictionAreNotLoss() throws {
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        let first = try snapshot(frames: [frame(1), frame(2)])
        history.ingest(json: first)
        history.ingest(json: first)
        XCTAssertEqual(history.bufferedFrameCount, 2)
        // Frame 1 was already received before the ring evicted it.
        history.ingest(json: try snapshot(frames: [frame(2), frame(3)], evicted: 1))
        XCTAssertFalse(history.needsFilterRestart)
        XCTAssertEqual(history.bufferedFrameCount, 3)
    }

    func testLossDiscontinuityAndChangedRecordsRequireAFilterRestart() throws {
        let cases: [(String, [String])] = [
            ("evicted before receipt", [try snapshot(frames: [frame(1)]),
                                        try snapshot(frames: [frame(3), frame(4)], evicted: 2)]),
            ("rejected record", [try snapshot(frames: [frame(1)]),
                                 try snapshot(frames: [frame(1), frame(3)], rejected: 1)]),
            ("missing trailing record", [try snapshot(frames: [frame(1)], last: 2)]),
            ("audio gap", [try snapshot(frames: [frame(1), frame(2, startOffset: 0.15)])]),
            ("changed repeat", [try snapshot(frames: [frame(1)]), try snapshot(frames: [frame(1, peak: "-3")])]),
            ("wrong channel count", [try snapshot(frames: [frame(1, channels: 2)])]),
            ("wrong sample rate", [try snapshot(frames: [frame(1, sampleRate: 44_100)])]),
            ("history began after a discontinuity", [try snapshot(frames: [frame(1)], epoch: 1)]),
        ]
        for (name, snapshots) in cases {
            var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
            snapshots.forEach { history.ingest(json: $0) }
            XCTAssertTrue(history.needsFilterRestart, name)
            XCTAssertNil(history.reading(at: 10), name)
            history.restart()
            XCTAssertFalse(history.needsFilterRestart, name)
            XCTAssertEqual(history.restarts, 1, name)
        }
    }

    func testClockRewindRequiresAFilterRestart() throws {
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: try snapshot(frames: [frame(1), frame(2)]))
        XCTAssertNotNil(history.reading(at: 0.2))
        XCTAssertNil(history.reading(at: 0.1))
        XCTAssertTrue(history.needsFilterRestart)
    }

    func testNewFilterInstanceRestartsMaximaWithoutCountingARestart() throws {
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: try snapshot(frames: [frame(1, peak: "-1")]))
        XCTAssertEqual(try XCTUnwrap(history.reading(at: 0.1)).maximumSamplePeaks, [-1])
        // mpv recreated the user filter chain, e.g. after another `af add`.
        history.ingest(json: try snapshot(frames: [frame(1, startOffset: 0.1, peak: "-12")], instance: 2))
        let reading = try XCTUnwrap(history.reading(at: 0.2))
        XCTAssertEqual(reading.maximumSamplePeaks, [-12])
        XCTAssertEqual(reading.filterFrames, 4800)
        XCTAssertEqual(reading.historyRestarts, 0)
        history.ingest(json: try snapshot(frames: [frame(1)], instance: 1))
        XCTAssertTrue(history.needsFilterRestart, "A retired instance cannot reappear")
    }

    func testRejectsMalformedTransport() throws {
        var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try snapshot(frames: [frame(1)]).utf8)) as? [String: Any])
        for (key, value) in [("schema-version", 2), ("capacity", 64), ("instance", 0)] as [(String, Any)] {
            var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
            var object = bad
            object[key] = value
            history.ingest(json: try encode(object))
            XCTAssertTrue(history.needsFilterRestart, key)
        }
        var history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: "not json")
        XCTAssertTrue(history.needsFilterRestart)
        bad["frames"] = [["sequence": 1, "frame": try rawFrame(sequence: 1, peak: "nan")]]
        history = MPVNativeAudioMeterHistory(channels: 1, sampleRate: 48_000)
        history.ingest(json: try encode(bad))
        XCTAssertTrue(history.needsFilterRestart)
    }

    // MARK: - Transport fixtures

    /// 0.1 s frames at 48 kHz, starting at media time (sequence − 1) / 10 + offset.
    private func frame(_ sequence: Int, startOffset: Double? = nil, peak: String = "-6", rms: String = "-9",
                       channels: Int = 1, sampleRate: Int = 48_000) -> [String: Any] {
        ["sequence": sequence, "frame": (try? rawFrame(sequence: sequence, startOffset: startOffset, peak: peak,
                                                       rms: rms, channels: channels, sampleRate: sampleRate)) ?? ""]
    }

    private func rawFrame(sequence: Int, startOffset: Double? = nil, peak: String = "-6", rms: String = "-9",
                          channels: Int = 1, sampleRate: Int = 48_000) throws -> String {
        let start = Double(sequence - 1) / 10 + (startOffset ?? 0)
        var metadata = ["lavfi.r128.M": "-22", "lavfi.r128.S": "-23"]
        for channel in 0..<channels {
            metadata["lavfi.astats.\(channel + 1).Peak_level"] = peak
            metadata["lavfi.astats.\(channel + 1).RMS_level"] = rms
            metadata["lavfi.r128.true_peaks_ch\(channel)"] = "0.500"
        }
        return try encode([
            "valid-time": true, "start": start, "end": start + 0.1,
            "effective-rate": Double(sampleRate), "speed": 1.0,
            "sample-rate": sampleRate, "samples": sampleRate / 10,
            "layout": channels == 1 ? "mono" : "stereo", "metadata": metadata,
        ])
    }

    private func snapshot(frames: [[String: Any]], instance: Int = 1, epoch: Int = 0, last: Int? = nil,
                          evicted: Int = 0, rejected: Int = 0, resetReason: String = "filter-created") throws -> String {
        let sequences = frames.compactMap { $0["sequence"] as? Int }
        return try encode([
            "schema-version": 1, "instance": instance, "epoch": epoch,
            "last-sequence": last ?? sequences.max() ?? 0, "evicted": evicted, "rejected": rejected,
            "capacity": 128, "reset-reason": resetReason, "frames": frames,
        ])
    }

    private func encode(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}
