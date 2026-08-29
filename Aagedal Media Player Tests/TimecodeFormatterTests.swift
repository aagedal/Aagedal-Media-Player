// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class TimecodeFormatterTests: XCTestCase {
    @MainActor
    func testTwentyFourFPSFormatting() {
        XCTAssertEqual(
            TimecodeFormatter.timecode(from: 3_661.5, frameRate: 24),
            "01:01:01:12"
        )
    }

    @MainActor
    func testSourceTimecodeOffsetIsApplied() {
        XCTAssertEqual(
            TimecodeFormatter.timecode(
                from: 10.5,
                frameRate: 24,
                startTimecode: "01:00:00:00"
            ),
            "01:00:10:12"
        )
    }

    @MainActor
    func testFrameParsingAtCommonRates() {
        XCTAssertEqual(TimecodeFormatter.parseTimecodeToFrames("01:00:00:00", fps: 24), 86_400)
        XCTAssertEqual(TimecodeFormatter.parseTimecodeToFrames("00:01:00:00", fps: 25), 1_500)
        XCTAssertEqual(TimecodeFormatter.parseTimecodeToFrames("00:00:10:15", fps: 30), 315)
    }

    @MainActor
    func testInvalidTimeValuesUsePlaceholder() {
        XCTAssertEqual(TimecodeFormatter.timecode(from: -.infinity), "--:--:--:--")
        XCTAssertEqual(TimecodeFormatter.timecode(from: .nan), "--:--:--:--")
        XCTAssertEqual(TimecodeFormatter.timecode(from: -0.1), "--:--:--:--")
    }

    @MainActor
    func testTraditionalTimeFormatting() {
        XCTAssertEqual(TimecodeFormatter.formatTraditionalTime(65), "01:05")
        XCTAssertEqual(TimecodeFormatter.formatTraditionalTime(3_661), "1:01:01")
        XCTAssertEqual(TimecodeFormatter.formatTraditionalTime(.infinity), "--:--")
    }
}
