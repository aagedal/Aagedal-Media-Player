// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ComparePresentationTests: XCTestCase {
    func testWipePositionClampsToUnitInterval() {
        let session = CompareSessionController()

        session.setWipePosition(-0.25)
        XCTAssertEqual(session.wipePosition, 0)

        session.setWipePosition(1.25)
        XCTAssertEqual(session.wipePosition, 1)

        session.setWipePosition(.infinity)
        XCTAssertEqual(session.wipePosition, 0.5)
    }

    func testMovingWipeUsesClampedPosition() {
        let session = CompareSessionController()

        session.moveWipe(by: 0.2)
        XCTAssertEqual(session.wipePosition, 0.7, accuracy: 0.000_001)

        session.moveWipe(by: 1)
        XCTAssertEqual(session.wipePosition, 1)
    }

    func testOverlayBlendUsesTheSameClampedRange() {
        let session = CompareSessionController()

        session.setOverlayBlend(-1)
        XCTAssertEqual(session.overlayBlend, 0)

        session.setOverlayBlend(2)
        XCTAssertEqual(session.overlayBlend, 1)
    }

    func testDifferenceGainClampsToSupportedRange() {
        let session = CompareSessionController()

        session.setDifferenceGain(0)
        XCTAssertEqual(session.differenceGain, 1)

        session.setDifferenceGain(8.5)
        XCTAssertEqual(session.differenceGain, 8.5)

        session.setDifferenceGain(20)
        XCTAssertEqual(session.differenceGain, 16)

        session.setDifferenceGain(.nan)
        XCTAssertEqual(session.differenceGain, 1)
    }

    func testDifferenceBrightnessCompensatesForContrastLift() {
        XCTAssertEqual(
            CompareSessionController.differenceBrightness(forGain: 1),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CompareSessionController.differenceBrightness(forGain: 2),
            0.25,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CompareSessionController.differenceBrightness(forGain: 4),
            0.375,
            accuracy: 0.000_001
        )
    }

    func testABToggleEntersPrimaryAndAlternatesSources() {
        let session = CompareSessionController()

        session.viewMode = .verticalWipe
        session.togglePrimarySecondary()
        XCTAssertEqual(session.viewMode, .primary)

        session.togglePrimarySecondary()
        XCTAssertEqual(session.viewMode, .secondary)
    }

    func testOnlyWipeModesReportWipeControls() {
        XCTAssertTrue(CompareViewMode.verticalWipe.isWipe)
        XCTAssertTrue(CompareViewMode.horizontalWipe.isWipe)
        XCTAssertFalse(CompareViewMode.overlay.isWipe)
        XCTAssertFalse(CompareViewMode.difference.isWipe)
        XCTAssertFalse(CompareViewMode.sideBySide.isWipe)
    }

    func testEquivalentDisplayAspectsShareTheSameComparisonRect() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 1_920.0 / 1_080.0,
            // For example, 1440x1080 coded pixels after a 4:3 PAR is applied.
            secondaryAspectRatio: 1_920.0 / 1_080.0
        )

        XCTAssertEqual(geometry.primaryReferenceRect.minY, 60, accuracy: 0.000_001)
        XCTAssertEqual(geometry.primaryReferenceRect.width, 1_920, accuracy: 0.000_001)
        XCTAssertEqual(geometry.primaryReferenceRect.height, 1_080, accuracy: 0.000_001)
        XCTAssertEqual(
            CompareDisplayGeometry.aspectFitRect(
                aspectRatio: geometry.secondaryAspectRatio,
                in: geometry.canvasRect
            ),
            geometry.primaryReferenceRect
        )
    }

    func testRotatedAndPhysicallyPortraitSourcesShareDisplayGeometry() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_600, height: 900),
            // Both inputs are post-display ratios: one can originate from a
            // rotated 1920x1080 stream and the other from a 1080x1920 raster.
            primaryAspectRatio: 9.0 / 16.0,
            secondaryAspectRatio: 1_080.0 / 1_920.0
        )

        let secondaryRect = CompareDisplayGeometry.aspectFitRect(
            aspectRatio: geometry.secondaryAspectRatio,
            in: geometry.canvasRect
        )
        XCTAssertEqual(secondaryRect, geometry.primaryReferenceRect)
        XCTAssertEqual(geometry.primaryReferenceRect.width, 506.25, accuracy: 0.000_001)
        XCTAssertEqual(geometry.primaryReferenceRect.height, 900, accuracy: 0.000_001)
    }

    func testSideBySideFitsPortraitSourcesToFullPaneHeight() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_600, height: 900),
            primaryAspectRatio: 9.0 / 16.0,
            secondaryAspectRatio: 9.0 / 16.0
        )

        let primary = geometry.sideBySideTransform(for: .primary)
        let secondary = geometry.sideBySideTransform(for: .secondary)

        XCTAssertEqual(primary.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(primary.offset.x, -400, accuracy: 0.000_001)
        XCTAssertEqual(primary.offset.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(secondary.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(secondary.offset.x, 400, accuracy: 0.000_001)
        XCTAssertEqual(secondary.offset.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            geometry.presentationClipRect(for: .primary, mode: .sideBySide),
            CGRect(x: 0, y: 0, width: 800, height: 900)
        )
        XCTAssertEqual(
            geometry.presentationClipRect(for: .secondary, mode: .sideBySide),
            CGRect(x: 800, y: 0, width: 800, height: 900)
        )
    }

    func testWipeClipUsesPrimaryVisiblePictureBounds() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 16.0 / 9.0,
            secondaryAspectRatio: 16.0 / 9.0
        )

        XCTAssertEqual(
            geometry.secondaryClipRect(for: .verticalWipe, wipePosition: 0.5),
            CGRect(x: 0, y: 60, width: 960, height: 1_080)
        )
        XCTAssertEqual(
            geometry.secondaryClipRect(for: .horizontalWipe, wipePosition: 0.5),
            CGRect(x: 0, y: 60, width: 1_920, height: 540)
        )
    }

    func testDifferingDisplayAspectsRetainIndependentFullFrameFits() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 1_920, height: 1_200),
            primaryAspectRatio: 16.0 / 9.0,
            secondaryAspectRatio: 4.0 / 3.0
        )

        XCTAssertFalse(geometry.displayAspectsMatch)
        XCTAssertEqual(geometry.comparisonReferenceRect, geometry.canvasRect)
        XCTAssertEqual(
            geometry.secondaryClipRect(for: .verticalWipe, wipePosition: 1),
            geometry.canvasRect
        )
        XCTAssertEqual(
            geometry.secondaryClipRect(for: .difference, wipePosition: 0.5),
            geometry.canvasRect
        )
    }

    func testInvalidGeometryFallsBackWithoutProducingNonFiniteValues() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: CGFloat.infinity, height: CGFloat.nan),
            primaryAspectRatio: CGFloat.nan,
            secondaryAspectRatio: -CGFloat.infinity
        )

        XCTAssertEqual(geometry.canvasSize, CGSize.zero)
        XCTAssertEqual(geometry.primaryAspectRatio, 16.0 / 9.0)
        XCTAssertEqual(geometry.secondaryAspectRatio, 16.0 / 9.0)
        XCTAssertEqual(geometry.primaryReferenceRect, CGRect.zero)
    }
}
