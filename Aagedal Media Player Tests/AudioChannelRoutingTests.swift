// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AudioToolbox
import Libmpv
import XCTest
@testable import Aagedal_Media_Player

final class AudioChannelRoutingTests: XCTestCase {
    @MainActor
    func testBundledMPVSwitchesBetweenMonoStereoAndSurroundProgrammes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("eight-mono.mkv")
        var arguments = ["-v", "error", "-y"]
        for track in 0..<8 {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=\(300 + track * 100):sample_rate=48000:duration=4"]
        }
        for track in 0..<8 { arguments += ["-map", "\(track):a"] }
        try await FFmpegService.run(arguments: arguments + ["-c:a", "pcm_s16le", file.path])

        let handle = try XCTUnwrap(mpv_create())
        defer { mpv_terminate_destroy(handle) }
        for (name, value) in [("vo", "null"), ("ao", "null"), ("pause", "no"), ("loop-file", "inf"), ("audio-channels", "auto")] {
            XCTAssertGreaterThanOrEqual(mpv_set_option_string(handle, name, value), 0)
        }
        XCTAssertGreaterThanOrEqual(mpv_request_log_messages(handle, "warn"), 0)
        XCTAssertGreaterThanOrEqual(mpv_initialize(handle), 0)
        XCTAssertGreaterThanOrEqual(mpv_command_string(handle, "loadfile \"\(file.path)\""), 0)

        func property(_ name: String) -> String? {
            guard let value = mpv_get_property_string(handle, name) else { return nil }
            defer { mpv_free(value) }
            return String(cString: value)
        }
        var decoderMessages: [String] = []
        func waitFor(_ name: String, _ expected: String) async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while ContinuousClock.now < deadline {
                while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
                    if event.pointee.event_id == MPV_EVENT_LOG_MESSAGE, let data = event.pointee.data {
                        let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                        decoderMessages.append(String(cString: message.text))
                    }
                }
                if property(name) == expected { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("Expected \(name)=\(expected), got \(property(name) ?? "nil"): \(decoderMessages.joined())")
        }
        try await waitFor("track-list/count", "8")
        for (layout, ids) in [
            (MonoPlaybackProgramme.Layout.stereo, [1, 2]),
            (.surround, [1, 2, 3, 4, 5, 6]),
            (.stereo, [7, 8]),
        ] {
            let programme = try XCTUnwrap(MonoPlaybackProgramme(layout: layout, trackIDs: ids))
            XCTAssertGreaterThanOrEqual(mpv_set_property_string(handle, "lavfi-complex", programme.mpvFilterGraph), 0)
            try await waitFor("audio-out-params/channel-count", String(ids.count))
            XCTAssertEqual(property("audio-out-params/channels"), layout.ffmpegLayout)
        }
        XCTAssertGreaterThanOrEqual(mpv_set_property_string(handle, "lavfi-complex", ""), 0)
        XCTAssertGreaterThanOrEqual(mpv_set_property_string(handle, "aid", "1"), 0)
        try await waitFor("audio-out-params/channel-count", "1")
    }

    func testMonoProgrammeUsesExplicitSpeakerAssignments() {
        let stereo = MonoPlaybackProgramme(layout: .stereo, trackIDs: [2, 4])!
        XCTAssertEqual(stereo.mpvFilterGraph, "[aid2]pan=stereo|FL=c0|FR=0*c0[mono0];[aid4]pan=stereo|FL=0*c0|FR=c0[mono1];[mono0][mono1]amix=inputs=2:normalize=0:dropout_transition=0[ao]")
        let surround = MonoPlaybackProgramme(layout: .surround, trackIDs: [1, 2, 3, 4, 5, 6])!
        XCTAssertTrue(surround.mpvFilterGraph.contains("[aid4]pan=5.1|FL=0*c0|FR=0*c0|FC=0*c0|LFE=c0|BL=0*c0|BR=0*c0[mono3]"))
        XCTAssertTrue(surround.mpvFilterGraph.hasSuffix("amix=inputs=6:normalize=0:dropout_transition=0[ao]"))
        XCTAssertNil(MonoPlaybackProgramme(layout: .stereo, trackIDs: [1, 1]))
        XCTAssertNil(MonoPlaybackProgramme(layout: .surround, trackIDs: [1, 2]))
        XCTAssertNil(MonoPlaybackProgramme(layout: .stereo, trackIDs: [-2, 1]))
    }

    func testMonoSpeakerReassignmentSwapsExistingTrack() {
        let programme = MonoPlaybackProgramme(layout: .stereo, trackIDs: [1, 2])!
        XCTAssertEqual(programme.assigning(trackID: 2, to: 0)?.trackIDs, [2, 1])
        XCTAssertEqual(programme.assigning(trackID: 8, to: 1)?.trackIDs, [1, 8])
        XCTAssertNil(programme.assigning(trackID: 3, to: 2))
    }

    func testInvalidChannelIndexesAreDiscarded() {
        let routing = AudioChannelRouting(
            channelCount: 2,
            mutedChannels: [-1, 0, 3],
            soloedChannels: [1, 9]
        )

        XCTAssertEqual(routing.mutedChannels, [0])
        XCTAssertEqual(routing.soloedChannels, [1])
        XCTAssertEqual(routing.audibleChannels, [1])
    }

    func testMuteIsAppliedAfterSolo() {
        let routing = AudioChannelRouting(
            channelCount: 6,
            mutedChannels: [2],
            soloedChannels: [2, 3]
        )

        XCTAssertEqual(routing.audibleChannels, [3])
        XCTAssertFalse(routing.isAudible(2))
        XCTAssertTrue(routing.isAudible(3))
    }

    func testMuteAndSoloTogglesAreReversible() {
        let all = AudioChannelRouting(channelCount: 2)
        let muted = all.togglingMute(for: 0)
        let soloed = muted.togglingSolo(for: 1)

        XCTAssertEqual(muted.mutedChannels, [0])
        XCTAssertEqual(soloed.soloedChannels, [1])
        XCTAssertEqual(soloed.togglingSolo(for: 1).soloedChannels, [])
        XCTAssertEqual(muted.togglingMute(for: 0).mutedChannels, [])
    }

    func testMPVFilterPreservesLayoutAndZerosOnlyInaudibleChannels() {
        let routing = AudioChannelRouting(channelCount: 3, soloedChannels: [1])

        XCTAssertEqual(
            routing.mpvAudioFilter,
            "lavfi=[pan=3c|c0=0*c0|c1=c1|c2=0*c2]"
        )
        XCTAssertNil(AudioChannelRouting(channelCount: 3).mpvAudioFilter)
    }

    func testAVDSPZerosOnlyMutedInterleavedSamples() {
        var samples: [Float] = [1, 2, 3, 4, 5, 6]
        let byteCount = samples.count * MemoryLayout<Float>.size
        samples.withUnsafeMutableBytes { bytes in
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 3,
                    mDataByteSize: UInt32(byteCount),
                    mData: bytes.baseAddress
                )
            )
            let format = AudioStreamBasicDescription(
                mSampleRate: 48_000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 12,
                mFramesPerPacket: 1,
                mBytesPerFrame: 12,
                mChannelsPerFrame: 3,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            applyAudioChannelRouting(
                in: &bufferList,
                frameCount: 2,
                routing: AudioChannelRouting(channelCount: 3, mutedChannels: [1]),
                processingFormat: format
            )
        }

        XCTAssertEqual(samples, [1, 0, 3, 4, 0, 6])
    }

    func testKnownChannelLabelsMatchWaveformConventions() {
        XCTAssertEqual(
            AudioChannelLabels.names(count: 6, layout: "5.1(side)"),
            ["Left", "Right", "Center", "LFE", "Side Left", "Side Right"]
        )
        XCTAssertEqual(
            AudioChannelLabels.names(count: 3, layout: nil),
            ["Channel 1", "Channel 2", "Channel 3"]
        )
    }

    func testCompareMatcherUsesSemanticRolesAcrossDifferentLayouts() {
        let options = CompareAudioChannelMatcher.options(
            primaryCount: 6,
            primaryLayout: "5.1",
            secondaryCount: 6,
            secondaryLayout: "5.1(side)"
        )

        XCTAssertEqual(options.map(\.label), ["Left", "Right", "Center", "LFE"])
        XCTAssertEqual(options.map(\.primaryIndex), [0, 1, 2, 3])
        XCTAssertEqual(options.map(\.secondaryIndex), [0, 1, 2, 3])
    }

    func testCompareMatcherRejectsUnsafeOrdinalMapping() {
        XCTAssertEqual(
            CompareAudioChannelMatcher.options(
                primaryCount: 4,
                primaryLayout: nil,
                secondaryCount: 6,
                secondaryLayout: nil
            ),
            []
        )
    }

    func testCompareMatcherAllowsOrdinalMappingForEqualUnknownLayouts() {
        let options = CompareAudioChannelMatcher.options(
            primaryCount: 4,
            primaryLayout: nil,
            secondaryCount: 4,
            secondaryLayout: nil
        )

        XCTAssertEqual(options.map(\.label), ["Channel 1 (by position)", "Channel 2 (by position)", "Channel 3 (by position)", "Channel 4 (by position)"])
        XCTAssertEqual(options.map(\.secondaryIndex), [0, 1, 2, 3])
    }
    func testLayoutSummaryExposesUnmatchedSpeakerRoles() {
        let summary = CompareAudioLayoutSummary(
            primaryCount: 6, primaryLayout: "5.1",
            secondaryCount: 6, secondaryLayout: "5.1(side)"
        )
        XCTAssertTrue(summary.hasMismatch)
        XCTAssertFalse(summary.usesOrdinalMatching)
        XCTAssertEqual(summary.unmatchedPrimary, ["Back Left", "Back Right"])
        XCTAssertEqual(summary.unmatchedSecondary, ["Side Left", "Side Right"])
    }

    func testUnknownLayoutNeverClaimsSemanticChannelMatching() {
        let summary = CompareAudioLayoutSummary(
            primaryCount: 6, primaryLayout: "5.1",
            secondaryCount: 6, secondaryLayout: nil
        )
        XCTAssertTrue(summary.hasMismatch)
        XCTAssertTrue(summary.usesOrdinalMatching)
        XCTAssertEqual(summary.unmatchedPrimary, [])
        let options = CompareAudioChannelMatcher.options(
            primaryCount: 6, primaryLayout: "5.1",
            secondaryCount: 6, secondaryLayout: nil
        )
        XCTAssertEqual(options[2].label, "Channel 3 (by position)")
    }

    func testMatchingLayoutsIgnoreCaseAndSurroundingWhitespace() {
        let summary = CompareAudioLayoutSummary(
            primaryCount: 6, primaryLayout: " 5.1(SIDE) ",
            secondaryCount: 6, secondaryLayout: "5.1(side)"
        )
        XCTAssertFalse(summary.hasMismatch)
        XCTAssertFalse(summary.usesOrdinalMatching)
        XCTAssertTrue(summary.unmatchedPrimary.isEmpty)
        XCTAssertTrue(summary.unmatchedSecondary.isEmpty)
    }

    func testMissingAudioReportsEveryOtherChannelAsUnmatched() {
        let summary = CompareAudioLayoutSummary(
            primaryCount: 2, primaryLayout: "stereo",
            secondaryCount: 0, secondaryLayout: nil
        )
        XCTAssertTrue(summary.hasMismatch)
        XCTAssertFalse(summary.usesOrdinalMatching)
        XCTAssertEqual(summary.unmatchedPrimary, ["Left", "Right"])
        XCTAssertEqual(summary.secondaryLayout, "No active audio channels")
    }

    func testUnknownLayoutsWithDifferentCountsExplainUnavailablePairing() {
        let summary = CompareAudioLayoutSummary(
            primaryCount: 4, primaryLayout: nil,
            secondaryCount: 6, secondaryLayout: nil
        )
        XCTAssertTrue(summary.hasMismatch)
        XCTAssertFalse(summary.usesOrdinalMatching)
        XCTAssertFalse(summary.hasMatchingChannels)
        XCTAssertEqual(summary.unmatchedPrimary.count, 4)
        XCTAssertEqual(summary.unmatchedSecondary.count, 6)
        XCTAssertEqual(
            summary.matchingExplanation,
            "No reliable channel pairs are available for these selected tracks. Use All Channels to monitor each source."
        )
    }

}
