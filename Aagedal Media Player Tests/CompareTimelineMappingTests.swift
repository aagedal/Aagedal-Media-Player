// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareTimelineMappingTests: XCTestCase {
    func testSourceTimecodeMappingUsesAbsoluteTimeline() {
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 3_600,
            secondaryStartSeconds: 3_590,
            secondaryDuration: 120
        )

        XCTAssertEqual(mapping.mode, .sourceTimecode)
        XCTAssertEqual(mapping.offset, 10)
        XCTAssertEqual(mapping.secondaryTime(forPrimaryTime: 25), 35)
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
