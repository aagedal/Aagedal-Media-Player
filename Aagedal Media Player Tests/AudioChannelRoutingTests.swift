// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AudioToolbox
import XCTest
@testable import Aagedal_Media_Player

final class AudioChannelRoutingTests: XCTestCase {
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
