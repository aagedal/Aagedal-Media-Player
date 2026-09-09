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

    @MainActor
    func testDecimalFrameRatesNormalizeBroadcastTimebases() throws {
        for (text, numerator) in [("23.976", 24_000), ("29.97", 30_000), ("47.952", 48_000),
                                   ("59.94", 60_000), ("119.88", 120_000),
                                   (String(30_000.0 / 1_001), 30_000), ("59.940060", 60_000)] {
            let rate = try XCTUnwrap(MediaMetadata.FrameRate(frameRateString: text), text)
            XCTAssertEqual(rate.numerator, numerator, text)
            XCTAssertEqual(rate.denominator, 1_001, text)
        }
    }

    @MainActor
    func testDecimalFrameRatesRetainNonbroadcastPrecision() throws {
        for (text, numerator, denominator): (String, Int, Int) in [
            ("24", 24, 1), ("25.125", 201, 8), ("27.123456", 423_804, 15_625),
            ("0.000001", 1, 1_000_000), ("29.968", 3_746, 125),
        ] {
            let rate = try XCTUnwrap(MediaMetadata.FrameRate(frameRateString: text), text)
            XCTAssertEqual(rate.numerator, numerator, text)
            XCTAssertEqual(rate.denominator, denominator, text)
        }
        // An explicit fraction does not request decimal-rate normalization.
        let legacyRate = try XCTUnwrap(MediaMetadata.FrameRate(frameRateString: "29970/1000"))
        XCTAssertEqual(legacyRate.numerator, 29_970)
        XCTAssertEqual(legacyRate.denominator, 1_000)
    }

    @MainActor
    func testFrameRatesRejectInvalidNonfiniteAndOverflowingValues() {
        for text in ["", "abc", "nan", "inf", "-inf", "1e309", "1e100", "0", "-25", "1e-20",
                     "1/0", "0/1", "-24/1", "24/-1", "-24/-1", "1//2", "/24", "24/", "24/1/2",
                     "9223372036854775808/1", "9223372036854775807/1", "9223372036854775807", "nan/1"] {
            XCTAssertNil(MediaMetadata.FrameRate(frameRateString: text), text)
        }
    }

    @MainActor
    func testMediaPresentationKindRequiresResolvedStreamCounts() {
        XCTAssertEqual(
            MediaPresentationKind(videoStreamCount: nil, audioStreamCount: nil),
            .unresolved
        )
    }

    @MainActor
    func testMediaPresentationKindPrefersVideoWhenBothKindsExist() {
        XCTAssertEqual(
            MediaPresentationKind(videoStreamCount: 1, audioStreamCount: 2),
            .video
        )
    }

    @MainActor
    func testMediaPresentationKindRecognizesAudioOnlyMedia() {
        XCTAssertEqual(
            MediaPresentationKind(videoStreamCount: 0, audioStreamCount: 1),
            .audioOnly
        )
        XCTAssertEqual(
            MediaPresentationKind(videoStreamCount: 0, audioStreamCount: 0),
            .noPlayableStreams
        )
    }
}
