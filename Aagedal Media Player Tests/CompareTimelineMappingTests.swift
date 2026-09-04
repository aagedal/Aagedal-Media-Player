// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareTimelineMappingTests: XCTestCase {
    func testDriftPolicyUsesOnePrimaryFramePlusClockMarginAcrossVerificationRates() {
        let rates = [
            24_000.0 / 1_001.0,
            24,
            25,
            30_000.0 / 1_001.0,
            50,
            60_000.0 / 1_001.0,
            60,
        ]

        for rate in rates {
            let policy = CompareDriftPolicy(primaryFrameRate: rate)
            let withinThreshold = 10 + policy.frameDuration
            let beyondThreshold = 10 + policy.correctionThreshold + 0.001

            XCTAssertNil(
                policy.correctionTarget(
                    actualSecondaryTime: withinThreshold,
                    expectedSecondaryTime: 10,
                    timeSinceLastCorrection: .infinity
                ),
                "rate: \(rate)"
            )
            XCTAssertEqual(
                policy.correctionTarget(
                    actualSecondaryTime: beyondThreshold,
                    expectedSecondaryTime: 10,
                    timeSinceLastCorrection: .infinity
                ),
                10,
                "rate: \(rate)"
            )
        }
    }

    func testDriftPolicyPreservesSignedDirectionAndRejectsNonFiniteSamples() {
        let policy = CompareDriftPolicy(primaryFrameRate: 25)

        XCTAssertEqual(
            policy.signedDrift(actualSecondaryTime: 9.9, expectedSecondaryTime: 10)!,
            -0.1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            policy.signedDrift(actualSecondaryTime: 10.1, expectedSecondaryTime: 10)!,
            0.1,
            accuracy: 0.000_001
        )
        XCTAssertNil(
            policy.correctionTarget(
                actualSecondaryTime: .nan,
                expectedSecondaryTime: 10,
                timeSinceLastCorrection: .infinity
            )
        )
    }

    func testDriftPolicyCooldownPreventsRepeatedCorrectionSeeks() {
        let policy = CompareDriftPolicy(primaryFrameRate: 60)
        let actual = 10 + (2 * policy.frameDuration)

        XCTAssertNil(
            policy.correctionTarget(
                actualSecondaryTime: actual,
                expectedSecondaryTime: 10,
                timeSinceLastCorrection: CompareDriftPolicy.correctionCooldown - 0.001
            )
        )
        XCTAssertEqual(
            policy.correctionTarget(
                actualSecondaryTime: actual,
                expectedSecondaryTime: 10,
                timeSinceLastCorrection: CompareDriftPolicy.correctionCooldown
            ),
            10
        )
    }

    func testDriftPolicyFallsBackToThirtyFramesForInvalidRates() {
        for rate in [nil, 0, -1, .infinity, .nan] as [Double?] {
            let policy = CompareDriftPolicy(primaryFrameRate: rate)
            XCTAssertEqual(policy.frameRate, 30)
            XCTAssertEqual(policy.frameDuration, 1.0 / 30.0, accuracy: 0.000_001)
        }
    }

    func testSourceTimecodeMappingUsesAbsoluteTimeline() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 3_600,
            secondaryStartSeconds: 3_590,
            secondaryDuration: 120
        )

        XCTAssertEqual(mapping.mode, .sourceTimecode)
        XCTAssertEqual(mapping.offset, 10)
        XCTAssertEqual(mapping.secondaryTime(forPrimaryTime: 25), 35)
        XCTAssertEqual(mapping.offsetLabel(primaryFrameRate: 25), "B = A +00:00:10:00")
    }

    func testOffsetLabelUsesPrimaryFrameRateAndSignedDirection() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 100,
            secondaryStartSeconds: 101.5,
            secondaryDuration: 120
        )

        XCTAssertEqual(mapping.offsetLabel(primaryFrameRate: 24), "B = A −00:00:01:12")
    }

    func testOffsetLabelUsesPrimaryDropFrameConvention() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 60.06,
            secondaryStartSeconds: 0,
            secondaryDuration: 120
        )

        XCTAssertEqual(
            mapping.offsetLabel(
                primaryFrameRate: 30_000.0 / 1_001.0,
                dropFrame: true
            ),
            "B = A +00:01:00;02"
        )
    }

    func testZeroOffsetLabelMakesRelativeMappingExplicit() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: nil,
            secondaryStartSeconds: nil,
            secondaryDuration: 120
        )

        XCTAssertEqual(mapping.offsetLabel(primaryFrameRate: 24), "B = A +00:00:00:00")
    }

    func testMissingTimecodeFallsBackToRelativeTimeline() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 3_600,
            secondaryStartSeconds: nil,
            secondaryDuration: 120
        )

        XCTAssertEqual(mapping.mode, .relative)
        XCTAssertEqual(mapping.offset, 0)
        XCTAssertEqual(mapping.secondaryTime(forPrimaryTime: 25), 25)
    }

    func testMappedTimeClampsToSecondaryBounds() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 100,
            secondaryStartSeconds: 110,
            secondaryDuration: 20
        )

        XCTAssertEqual(mapping.secondaryTime(forPrimaryTime: 5), 0)
        XCTAssertEqual(mapping.secondaryTime(forPrimaryTime: 40), 20)
    }

    func testMappedTimeUsesDurationDiscoveredByPlaybackBackend() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: nil,
            secondaryStartSeconds: nil,
            secondaryDuration: 0
        )

        XCTAssertEqual(mapping.secondaryTime(forPrimaryTime: 15), 15)
        XCTAssertEqual(
            mapping.secondaryTime(forPrimaryTime: 40, secondaryDuration: 30),
            30
        )
    }

    func testForwardPlaybackDispositionAdvancesOnlyInsideSecondaryBounds() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 90,
            secondaryStartSeconds: 100,
            secondaryDuration: 20
        )

        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 9,
                primaryPlaybackSpeed: 1,
                secondaryDuration: 20
            ),
            .holdAtStart
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 10,
                primaryPlaybackSpeed: 1,
                secondaryDuration: 20
            ),
            .advance
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 20,
                primaryPlaybackSpeed: 1,
                secondaryDuration: 20
            ),
            .advance
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 30,
                primaryPlaybackSpeed: 1,
                secondaryDuration: 20
            ),
            .holdAtEnd
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 31,
                primaryPlaybackSpeed: 1,
                secondaryDuration: 20
            ),
            .holdAtEnd
        )
    }

    func testReversePlaybackDispositionAdvancesOnlyInsideSecondaryBounds() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 90,
            secondaryStartSeconds: 100,
            secondaryDuration: 20
        )

        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 9,
                primaryPlaybackSpeed: -1,
                secondaryDuration: 20
            ),
            .holdAtStart
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 10,
                primaryPlaybackSpeed: -1,
                secondaryDuration: 20
            ),
            .holdAtStart
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 20,
                primaryPlaybackSpeed: -1,
                secondaryDuration: 20
            ),
            .advance
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 30,
                primaryPlaybackSpeed: -1,
                secondaryDuration: 20
            ),
            .advance
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 31,
                primaryPlaybackSpeed: -1,
                secondaryDuration: 20
            ),
            .holdAtEnd
        )
    }

    func testPlaybackDispositionAdvancesWhenSecondaryDurationIsUnknown() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 90,
            secondaryStartSeconds: 100,
            secondaryDuration: 0
        )

        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 9,
                primaryPlaybackSpeed: 1,
                secondaryDuration: nil
            ),
            .advance
        )
        XCTAssertEqual(
            mapping.secondaryPlaybackDisposition(
                forPrimaryTime: 31,
                primaryPlaybackSpeed: -1,
                secondaryDuration: nil
            ),
            .advance
        )
    }

    func testOverlapStatusDistinguishesFullPartialNoneAndUnknown() {
        let relativeMapping = CompareTimelineMapping(
            primaryStartSeconds: nil,
            secondaryStartSeconds: nil,
            secondaryDuration: 0
        )
        let disjointMapping = CompareTimelineMapping(
            primaryStartSeconds: 100,
            secondaryStartSeconds: 200,
            secondaryDuration: 0
        )

        XCTAssertEqual(
            relativeMapping.overlapStatus(
                primaryDuration: 20,
                secondaryDuration: 30
            ),
            .full
        )
        XCTAssertEqual(
            relativeMapping.overlapStatus(
                primaryDuration: 30,
                secondaryDuration: 20
            ),
            .partial
        )
        XCTAssertEqual(
            disjointMapping.overlapStatus(
                primaryDuration: 10,
                secondaryDuration: 10
            ),
            .none
        )
        XCTAssertEqual(
            relativeMapping.overlapStatus(
                primaryDuration: 20,
                secondaryDuration: nil
            ),
            .unknown
        )
    }

    func testOverlapRangeAccountsForPositiveOffset() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 110,
            secondaryStartSeconds: 100,
            secondaryDuration: 30
        )

        XCTAssertEqual(mapping.primaryOverlapRange(primaryDuration: 50), 0...20)
    }

    func testOverlapRangeAccountsForNegativeOffset() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 90,
            secondaryStartSeconds: 100,
            secondaryDuration: 30
        )

        XCTAssertEqual(mapping.primaryOverlapRange(primaryDuration: 50), 10...40)
    }

    func testNonOverlappingTimelinesReturnNil() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 200,
            secondaryStartSeconds: 100,
            secondaryDuration: 30
        )

        XCTAssertNil(mapping.primaryOverlapRange(primaryDuration: 50))
    }
}
