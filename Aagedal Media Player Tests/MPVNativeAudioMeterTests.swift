// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Libmpv
import XCTest
@testable import Aagedal_Media_Player

final class MPVNativeAudioMeterTests: XCTestCase {
    private func metadata() -> [String: String] {
        ["lavfi.astats.1.Peak_level": "-6.0206", "lavfi.astats.1.RMS_level": "-9.0309",
         "lavfi.r128.true_peaks_ch0": "0.500", "lavfi.r128.M": "-9.031", "lavfi.r128.S": "-9.031"]
    }

    func testFrameUnitsAndSilenceRemainDistinct() throws {
        var values = metadata()
        let frame = try XCTUnwrap(MPVNativeAudioMeter.decodeFrame(values, channels: 1))
        XCTAssertEqual(try XCTUnwrap(frame.truePeaks[0]), -6.0206, accuracy: 0.0001)
        XCTAssertEqual(frame.samplePeaks, [-6.0206])
        XCTAssertEqual(frame.rms, [-9.0309])
        XCTAssertEqual(frame.momentary, -9.031)
        values["lavfi.astats.1.Peak_level"] = "-inf"
        values["lavfi.astats.1.RMS_level"] = "-inf"
        values["lavfi.r128.true_peaks_ch0"] = "0.000"
        let silent = try XCTUnwrap(MPVNativeAudioMeter.decodeFrame(values, channels: 1))
        XCTAssertEqual(silent.samplePeaks, [-.infinity])
        XCTAssertEqual(silent.truePeaks, [nil])
    }

    func testRejectsMalformedFrameMetadataAndChannelCounts() {
        let original = metadata()
        for key in original.keys {
            var values = original
            values.removeValue(forKey: key)
            XCTAssertNil(MPVNativeAudioMeter.decodeFrame(values, channels: 1), key)
            for bad in ["nan", "inf", "", "garbage"] {
                values[key] = bad
                XCTAssertNil(MPVNativeAudioMeter.decodeFrame(values, channels: 1), key)
            }
        }
        var values = original
        values["lavfi.r128.true_peaks_ch0"] = "-0.5"
        XCTAssertNil(MPVNativeAudioMeter.decodeFrame(values, channels: 1))
        for channels in [0, 2, 9, Int.max] {
            XCTAssertNil(MPVNativeAudioMeter.decodeFrame(original, channels: channels))
        }
        values = original; values["lavfi.astats.2.Peak_level"] = "-6"
        XCTAssertNil(MPVNativeAudioMeter.decodeFrame(values, channels: 1))
    }

    func testFilterRequestsTimestampedHistory() {
        XCTAssertTrue(MPVNativeAudioMeter.filter.hasPrefix("@\(MPVNativeAudioMeter.label):lavfi=graph=["))
        XCTAssertTrue(MPVNativeAudioMeter.filter.hasSuffix("]:amc-meter-history=yes"))
        XCTAssertTrue(MPVNativeAudioMeter.filter.contains("astats=metadata=1:reset=1:"),
                      "Per-frame astats; the history aggregates frames")
    }

    func testNodeMapCopiesStringsAndRejectsDuplicatesTypesAndBounds() {
        let key = strdup("lavfi.r128.M")!, value = strdup("-23.000")!
        defer { free(key); free(value) }
        var keys = [Optional(key), Optional(key)]
        var text = mpv_node(); text.format = MPV_FORMAT_STRING; text.u.string = value
        var values = [text, text]
        keys.withUnsafeMutableBufferPointer { keys in
            values.withUnsafeMutableBufferPointer { values in
                var list = mpv_node_list(num: 1, values: values.baseAddress, keys: keys.baseAddress)
                withUnsafeMutablePointer(to: &list) { list in
                    var node = mpv_node(); node.format = MPV_FORMAT_NODE_MAP; node.u.list = list
                    let copied = MPVNativeAudioMeter.metadata(node)
                    XCTAssertEqual(copied, ["lavfi.r128.M": "-23.000"])
                    list.pointee.num = 2
                    XCTAssertNil(MPVNativeAudioMeter.metadata(node))
                    list.pointee.num = 1; values[0].format = MPV_FORMAT_DOUBLE
                    XCTAssertNil(MPVNativeAudioMeter.metadata(node))
                    list.pointee.num = 129
                    XCTAssertNil(MPVNativeAudioMeter.metadata(node))
                    list.pointee.num = -1
                    XCTAssertNil(MPVNativeAudioMeter.metadata(node))
                    node.format = MPV_FORMAT_STRING
                    XCTAssertNil(MPVNativeAudioMeter.metadata(node))
                    XCTAssertEqual(copied, ["lavfi.r128.M": "-23.000"])
                }
            }
        }
    }
}

@MainActor
final class MPVNativeAudioMeterSessionTests: XCTestCase {
    func testDefaultOffDoesNotInstallOrQuery() async throws {
        let session = MPVNativeAudioMeterSession(enabled: false)
        let player = ProbeClient()
        session.update(player: player, format: try .init(sampleRate: 48000, layout: .stereo), eligible: true)
        XCTAssertNil(session.state)
        XCTAssertEqual(player.begins, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testSingleOutstandingQueryAndResetRejectsLateReply() async throws {
        let session = MPVNativeAudioMeterSession(enabled: true)
        let player = ProbeClient()
        let format = try LiveAudioMeterFormat(sampleRate: 48000, layout: .stereo)
        session.update(player: player, format: format, eligible: true)
        try await Task.sleep(for: .milliseconds(110))
        for _ in 0..<20 { session.update(player: player, format: format, eligible: true) }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(player.begins, 1)
        XCTAssertEqual(player.reads, 1)
        session.reset("reset marker")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(player.ends, 1)
        XCTAssertEqual(session.state?.status, "reset marker")
        XCTAssertNil(session.state?.reading)
        session.update(player: player, format: format, eligible: true)
        XCTAssertEqual(player.begins, 2)
        session.update(player: player, format: format, eligible: false)
        XCTAssertEqual(player.ends, 2)
    }

    func testMissingFiltersFallBackWithoutRepeatedInstallation() throws {
        let player = ProbeClient(available: false)
        let session = MPVNativeAudioMeterSession(enabled: true)
        let format = try LiveAudioMeterFormat(sampleRate: 48000, layout: .stereo)
        for _ in 0..<20 { session.update(player: player, format: format, eligible: true) }
        XCTAssertEqual(player.begins, 1)
        XCTAssertTrue(session.state?.status.contains("existing source meter") == true)
        session.reset()
        session.update(player: player, format: format, eligible: true)
        XCTAssertEqual(player.begins, 2)
    }

    func testReplacementAndDeinitializationRemoveOnlyOwnedFilter() throws {
        let first = ProbeClient(), second = ProbeClient()
        var session: MPVNativeAudioMeterSession? = .init(enabled: true)
        let format = try LiveAudioMeterFormat(sampleRate: 48000, layout: .stereo)
        session?.update(player: first, format: format, eligible: true)
        session?.update(player: second, format: format, eligible: true)
        XCTAssertEqual(first.ends, 1)
        XCTAssertEqual(second.begins, 1)
        session = nil
        XCTAssertEqual(second.ends, 1)
    }

    private nonisolated final class ProbeClient: MPVNativeAudioProbeClient, @unchecked Sendable {
        private let lock = NSLock()
        private var counts = [0, 0, 0]
        private let available: Bool
        var begins: Int { lock.withLock { counts[0] } }
        var reads: Int { lock.withLock { counts[1] } }
        var ends: Int { lock.withLock { counts[2] } }
        init(available: Bool = true) { self.available = available }
        func beginNativeAudioProbe(owner: UUID) -> Bool {
            lock.withLock { counts[0] += 1 }; return available
        }
        func readNativeAudioProbe(owner: UUID, channels: Int, sampleRate: Int) async -> MPVNativeAudioMeter.Reading? {
            lock.withLock { counts[1] += 1 }
            // Deliberately return even after cancellation to test token rejection.
            try? await Task.sleep(for: .milliseconds(80))
            return .init(samplePeaks: [-6, -6], rms: [-9, -9], maximumSamplePeaks: [-6, -6],
                         truePeaks: [-6, -6], momentary: -6, shortTerm: -6, filterFrames: 144000,
                         measuredUntil: 3, frameCount: 1, historyRestarts: 0)
        }
        func endNativeAudioProbe(owner: UUID) { lock.withLock { counts[2] += 1 } }
    }
}
