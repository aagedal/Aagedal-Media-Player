// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareMediaComparisonTests: XCTestCase {
    func testReportsEveryKnownTechnicalMismatch() {
        let primary = descriptor(
            duration: 60,
            frameRate: 24,
            transferFunction: "bt709",
            colorPrimaries: "bt709",
            colorRange: "tv"
        )
        let secondary = descriptor(
            duration: 61,
            frameRate: 25,
            transferFunction: "smpte2084",
            colorPrimaries: "bt2020",
            colorRange: "pc"
        )

        let mismatches = CompareMediaComparison.mismatches(
            primary: primary,
            secondary: secondary
        )

        XCTAssertEqual(mismatches.map(\.kind), [
            .frameRate,
            .duration,
            .transferFunction,
            .colorPrimaries,
            .colorRange
        ])
        XCTAssertEqual(mismatches.first?.primaryValue, "24 fps")
        XCTAssertEqual(mismatches.first?.secondaryValue, "25 fps")
    }

    func testEquivalentAliasesDoNotWarn() {
        let primary = descriptor(
            duration: 10,
            frameRate: 30_000.0 / 1_001.0,
            transferFunction: "smpte2084",
            colorPrimaries: "bt2020-10",
            colorRange: "pc"
        )
        let secondary = descriptor(
            duration: 10.000_5,
            frameRate: 29.970_03,
            transferFunction: "PQ",
            colorPrimaries: "BT.2020",
            colorRange: "full"
        )

        XCTAssertTrue(CompareMediaComparison.mismatches(
            primary: primary,
            secondary: secondary
        ).isEmpty)
    }

    func testValuesMissingFromBothSourcesDoNotCreateWarnings() {
        let primary = descriptor(
            duration: nil,
            frameRate: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            colorRange: nil
        )
        let secondary = descriptor(
            duration: nil,
            frameRate: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            colorRange: nil
        )

        XCTAssertTrue(CompareMediaComparison.mismatches(
            primary: primary,
            secondary: secondary
        ).isEmpty)
    }

    func testOneSidedMissingValuesAreReportedAsUnavailable() {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(),
            secondary: descriptor(
                duration: 30,
                frameRate: 30,
                transferFunction: "hlg",
                colorPrimaries: "bt2020",
                colorRange: "limited"
            )
        )

        XCTAssertEqual(mismatches.map(\.kind), CompareMismatchKind.allCases)
        XCTAssertTrue(mismatches.allSatisfy { $0.primaryValue == "Unavailable" })
    }

    func testUnknownSentinelsAreTreatedAsMissingTags() {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(
                transferFunction: " unknown ",
                colorPrimaries: "N/A",
                colorRange: "unspecified"
            ),
            secondary: descriptor(
                transferFunction: "bt709",
                colorPrimaries: "bt709",
                colorRange: "tv"
            )
        )

        XCTAssertEqual(mismatches.map(\.kind), [
            .transferFunction,
            .colorPrimaries,
            .colorRange
        ])
        XCTAssertTrue(mismatches.allSatisfy { $0.primaryValue == "Unavailable" })
    }

    func testDurationToleranceIgnoresRoundingButReportsFrameDifference() {
        let withinTolerance = CompareMediaComparison.mismatches(
            primary: descriptor(duration: 10, frameRate: 25),
            secondary: descriptor(duration: 10.009, frameRate: 25)
        )
        let beyondTolerance = CompareMediaComparison.mismatches(
            primary: descriptor(duration: 10, frameRate: 25),
            secondary: descriptor(duration: 10.04, frameRate: 25)
        )

        XCTAssertTrue(withinTolerance.isEmpty)
        XCTAssertEqual(beyondTolerance.map(\.kind), [.duration])
    }

    func testDurationLabelsRemainReadablePastOneHour() throws {
        let mismatches = CompareMediaComparison.mismatches(
            primary: descriptor(duration: 3_661.25),
            secondary: descriptor(duration: 3_662.5)
        )

        let mismatch = try XCTUnwrap(mismatches.first)
        XCTAssertEqual(mismatch.kind, .duration)
        XCTAssertEqual(mismatch.primaryValue, "1:01:01.250")
        XCTAssertEqual(mismatch.secondaryValue, "1:01:02.500")
    }

    private func descriptor(
        duration: TimeInterval? = nil,
        frameRate: Double? = nil,
        transferFunction: String? = nil,
        colorPrimaries: String? = nil,
        colorRange: String? = nil
    ) -> CompareMediaDescriptor {
        CompareMediaDescriptor(
            duration: duration,
            frameRate: frameRate,
            transferFunction: transferFunction,
            colorPrimaries: colorPrimaries,
            colorRange: colorRange
        )
    }
}
