// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class MediaMetadataValueTests: XCTestCase {
    @MainActor
    func testRatioReducesToLowestTerms() throws {
        let ratio = try XCTUnwrap(MediaMetadata.Ratio(numerator: 1920, denominator: 1080))

        XCTAssertEqual(ratio.reducedStringValue, "16:9")
        XCTAssertEqual(try XCTUnwrap(ratio.doubleValue), 16.0 / 9.0, accuracy: 0.000_001)
    }

    @MainActor
    func testRatioParsesColonSlashAndDecimalForms() throws {
        XCTAssertEqual(MediaMetadata.Ratio(ratioString: "4:3")?.reducedStringValue, "4:3")
        XCTAssertEqual(MediaMetadata.Ratio(ratioString: "30000/1001")?.stringValue, "30000:1001")

        let decimal = try XCTUnwrap(MediaMetadata.Ratio(ratioString: "1.5"))
        XCTAssertEqual(decimal.reducedStringValue, "3:2")
    }

    @MainActor
    func testRatioRejectsInvalidDenominatorsAndText() {
        XCTAssertNil(MediaMetadata.Ratio(numerator: 1, denominator: 0))
        XCTAssertNil(MediaMetadata.Ratio(ratioString: "16:0"))
        XCTAssertNil(MediaMetadata.Ratio(ratioString: "not-a-ratio"))
    }

    @MainActor
    func testFrameRatePreservesRationalValue() throws {
        let rate = try XCTUnwrap(MediaMetadata.FrameRate(frameRateString: "30000/1001"))

        XCTAssertEqual(rate.numerator, 30_000)
        XCTAssertEqual(rate.denominator, 1_001)
        XCTAssertEqual(try XCTUnwrap(rate.value), 29.970_029_97, accuracy: 0.000_000_01)
        XCTAssertEqual(rate.stringValue, "29.970")
    }
}
