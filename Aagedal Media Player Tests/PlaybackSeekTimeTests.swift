// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import CoreMedia
import XCTest

final class PlaybackSeekTimeTests: XCTestCase {
    func testTwentyFourFPSBoundaryDoesNotTruncateToPreviousFrame() throws {
        // Comparison mapping adds the B offset after stepping A. This ordering
        // produces 4.041666666666666, just below the exact frame boundary.
        let mappedTime = (3.0 + 1.0 / 24) + 1.0
        let target = try XCTUnwrap(PlaybackSeekTime.make(seconds: mappedTime))
        XCTAssertEqual(target.value, 485_000)
        XCTAssertEqual(target.timescale, 120_000)
        XCTAssertEqual(CMTimeCompare(target, CMTime(value: 97, timescale: 24)), 0)
    }

    func testCommonIntegerAndFractionalFrameBoundariesRoundTripExactly() throws {
        let rates: [(numerator: Int32, denominator: Int64)] = [
            (24_000, 1_001), (24, 1), (25, 1), (30_000, 1_001),
            (30, 1), (50, 1), (60_000, 1_001), (60, 1)
        ]
        for rate in rates {
            for frame: Int64 in [0, 1, 97, 10_001, 1_000_003] {
                let exact = CMTime(value: frame * rate.denominator, timescale: rate.numerator)
                let converted = try XCTUnwrap(PlaybackSeekTime.make(seconds: exact.seconds))
                XCTAssertEqual(CMTimeCompare(converted, exact), 0, "Frame \(frame) at \(rate)")
            }
        }
    }

    func testRejectsInvalidAndUnrepresentableTargets() {
        for seconds in [-1.0, -.leastNonzeroMagnitude, .nan, .infinity, -.infinity, .greatestFiniteMagnitude,
                        Double(Int64.max) / 120_000] {
            XCTAssertNil(PlaybackSeekTime.make(seconds: seconds), "Unexpected target for \(seconds)")
        }
        XCTAssertEqual(PlaybackSeekTime.make(seconds: 0), .zero)
    }

    func testRoundsSubTickValuesToNearestTick() throws {
        let below = try XCTUnwrap(PlaybackSeekTime.make(seconds: 1.49 / 120_000))
        let above = try XCTUnwrap(PlaybackSeekTime.make(seconds: 1.51 / 120_000))
        XCTAssertEqual(below.value, 1)
        XCTAssertEqual(above.value, 2)
    }
}
