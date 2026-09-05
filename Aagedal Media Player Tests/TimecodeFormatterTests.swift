// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class TimecodeFormatterTests: XCTestCase {
    @MainActor
    func testFrameCountRejectsRoundedIntegerOverflow() {
        let rate = TimecodeRate(frameRate: 1)
        XCTAssertNil(rate.frameCount(forSeconds: Double(Int64.max)))
        XCTAssertNil(rate.frameCount(forSeconds: .greatestFiniteMagnitude))
        XCTAssertEqual(rate.frameCount(forSeconds: Double(Int64.min)), Int64.min)
    }

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
    func test2997DropFrameGoldenBoundaries() {
        let rate = TimecodeRate(numerator: 30_000, denominator: 1_001, dropFrame: true)

        XCTAssertEqual(rate.timecode(forFrameCount: 0), "00:00:00;00")
        XCTAssertEqual(rate.timecode(forFrameCount: 1_800), "00:01:00;02")
        XCTAssertEqual(rate.timecode(forFrameCount: 17_982), "00:10:00;00")
        XCTAssertEqual(rate.timecode(forFrameCount: 107_892), "01:00:00;00")
        XCTAssertEqual(rate.timecode(forFrameCount: 2_589_408), "00:00:00;00")

        XCTAssertEqual(rate.frameCount(forTimecode: "00:01:00;02"), 1_800)
        XCTAssertEqual(rate.frameCount(forTimecode: "00:10:00;00"), 17_982)
        XCTAssertEqual(rate.frameCount(forTimecode: "01:00:00;00"), 107_892)
    }

    @MainActor
    func test5994DropFrameGoldenBoundaries() {
        let rate = TimecodeRate(numerator: 60_000, denominator: 1_001, dropFrame: true)

        XCTAssertEqual(rate.timecode(forFrameCount: 3_600), "00:01:00;04")
        XCTAssertEqual(rate.timecode(forFrameCount: 35_964), "00:10:00;00")
        XCTAssertEqual(rate.timecode(forFrameCount: 215_784), "01:00:00;00")
        XCTAssertEqual(rate.frameCount(forTimecode: "00:01:00;04"), 3_600)
        XCTAssertEqual(rate.frameCount(forTimecode: "00:10:00;00"), 35_964)
    }

    @MainActor
    func testInvalidDroppedLabelsAreRejected() {
        let rate2997 = TimecodeRate(numerator: 30_000, denominator: 1_001, dropFrame: true)
        let rate5994 = TimecodeRate(numerator: 60_000, denominator: 1_001, dropFrame: true)

        XCTAssertNil(rate2997.frameCount(forTimecode: "00:01:00;00"))
        XCTAssertNil(rate2997.frameCount(forTimecode: "00:01:00;01"))
        XCTAssertNotNil(rate2997.frameCount(forTimecode: "00:10:00;00"))
        XCTAssertNil(rate5994.frameCount(forTimecode: "00:01:00;03"))
        XCTAssertNotNil(rate5994.frameCount(forTimecode: "00:01:00;04"))
    }

    @MainActor
    func testDropFrameFormattingAndParsingRoundTrip() {
        let rates = [
            TimecodeRate(numerator: 30_000, denominator: 1_001, dropFrame: true),
            TimecodeRate(numerator: 60_000, denominator: 1_001, dropFrame: true)
        ]
        let frameCounts: [Int64] = [0, 1, 1_797, 1_798, 1_800, 17_981, 17_982, 107_892, 215_784]

        for rate in rates {
            for frames in frameCounts {
                let label = rate.timecode(forFrameCount: frames)
                XCTAssertEqual(rate.frameCount(forTimecode: label), frames, "Failed for \(label)")
            }
        }
    }

    @MainActor
    func testNonDropFractionalRateUsesRationalFrameDuration() {
        let rate = TimecodeRate(numerator: 24_000, denominator: 1_001)

        XCTAssertEqual(rate.timecode(forFrameCount: 86_400), "01:00:00:00")
        XCTAssertEqual(rate.seconds(forFrameCount: 24_000), 1_001, accuracy: 0.000_001)
        XCTAssertEqual(rate.frameCount(forSeconds: 1_001), 24_000)
    }

    @MainActor
    func testNonDropRoundTripAtSupportedCommonRates() {
        let rates = [
            TimecodeRate(numerator: 24_000, denominator: 1_001),
            TimecodeRate(numerator: 24, denominator: 1),
            TimecodeRate(numerator: 25, denominator: 1),
            TimecodeRate(numerator: 30_000, denominator: 1_001),
            TimecodeRate(numerator: 30, denominator: 1),
            TimecodeRate(numerator: 50, denominator: 1),
            TimecodeRate(numerator: 60_000, denominator: 1_001),
            TimecodeRate(numerator: 60, denominator: 1)
        ]

        for rate in rates {
            for frames in [Int64(0), 1, rate.nominalFPS - 1, rate.nominalFPS * 60, rate.nominalFPS * 3_600] {
                let label = rate.timecode(forFrameCount: frames)
                XCTAssertEqual(rate.frameCount(forTimecode: label), frames, "Failed for \(rate.value) fps at \(label)")
            }
        }
    }

    @MainActor
    func testDropFrameRequestIsIgnoredAtUnsupportedRate() {
        let rate = TimecodeRate(numerator: 24_000, denominator: 1_001, dropFrame: true)

        XCTAssertFalse(rate.isDropFrame)
        XCTAssertEqual(rate.timecode(forFrameCount: 24), "00:00:01:00")
    }

    @MainActor
    func testUnifiedInputParserHandlesAbsoluteRelativeAndFrameNavigation() throws {
        let item = MediaItem(
            url: URL(fileURLWithPath: "/tmp/timecode-test.mov"),
            name: "timecode-test.mov",
            size: 0,
            durationSeconds: 100
        )

        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseAbsoluteTimecodeToSeconds("10", item: item, mode: .relative)),
            10,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseAbsoluteTimecodeToSeconds("01:10", item: item, mode: .relative)),
            70,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseInputToSeconds(
                "+..15", item: item, mode: .relative, currentSeconds: 10, duration: 100
            )),
            10.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseInputToSeconds(
                "+..15", item: item, mode: .frames, currentSeconds: 10, duration: 100
            )),
            10.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseInputToSeconds(
                "315", item: item, mode: .frames, currentSeconds: 0, duration: 100
            )),
            10.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseInputToSeconds(
                "+00:00:01:15", item: item, mode: .relative, currentSeconds: 10, duration: 100
            )),
            11.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(TimecodeFormatter.parseInputToSeconds(
                "+90:15", item: item, mode: .relative, currentSeconds: 0, duration: 100
            )),
            90.5,
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testTrimOutDisplaysTheExclusiveFollowingFrame() {
        let item = MediaItem(
            url: URL(fileURLWithPath: "/tmp/timecode-test.mov"),
            name: "timecode-test.mov",
            size: 0
        )

        XCTAssertEqual(
            TimecodeFormatter.formatTimeForDisplayWithMode(seconds: 0, item: item, mode: .relative),
            "00:00:00:00"
        )
        XCTAssertEqual(
            TimecodeFormatter.formatTimeForDisplayWithMode(
                seconds: 0, item: item, mode: .relative, isOutPoint: true
            ),
            "00:00:00:01"
        )
        XCTAssertEqual(
            TimecodeFormatter.formatTimeForDisplayWithMode(
                seconds: 0, item: item, mode: .frames, isOutPoint: true
            ),
            "1"
        )
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
