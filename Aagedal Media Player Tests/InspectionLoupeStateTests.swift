// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class InspectionLoupeStateTests: XCTestCase {
    private let picture = CGRect(x: 100, y: 60, width: 800, height: 400)

    func testDisabledLoupeDoesNotTrackThePointer() {
        let state = InspectionLoupeState()

        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)

        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(state.pointer)
        XCTAssertFalse(state.isPinned)
    }

    func testEnabledLoupeTracksCoordinatesInsideTheFittedPicture() {
        let state = InspectionLoupeState()
        state.isEnabled = true

        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)

        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.25, y: 0.75))
        XCTAssertEqual(state.pointer, CGPoint(x: 300, y: 360))
    }

    func testMovingIntoBlackBarsPreservesLastInspectedPoint() {
        let state = InspectionLoupeState()
        state.isEnabled = true
        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)

        for location in [CGPoint(x: 99, y: 300), CGPoint(x: 500, y: 59), CGPoint(x: 901, y: 300), CGPoint(x: 500, y: 461)] {
            state.follow(location, pictureRect: picture)
            XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.25, y: 0.75))
            XCTAssertEqual(state.pointer, CGPoint(x: 300, y: 360))
        }
    }

    func testPinnedLoupeKeepsPositionUntilUnpinned() {
        let state = InspectionLoupeState()
        state.isEnabled = true
        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)
        state.isPinned = true

        state.follow(CGPoint(x: 700, y: 160), pictureRect: picture)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.25, y: 0.75))
        XCTAssertEqual(state.pointer, CGPoint(x: 300, y: 360))

        state.isPinned = false
        state.follow(CGPoint(x: 700, y: 160), pictureRect: picture)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.75, y: 0.25))
        XCTAssertEqual(state.pointer, CGPoint(x: 700, y: 160))
    }

    func testCompareCanvasRejectsTheVisibleSourcesBlackBars() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 800, height: 600),
            primaryAspectRatio: 2, secondaryAspectRatio: 0.5
        )
        let state = InspectionLoupeState()
        state.isEnabled = true
        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)
        let cases: [(CompareViewMode, CGPoint)] = [
            (.primary, CGPoint(x: 200, y: 50)),
            (.secondary, CGPoint(x: 100, y: 300)),
            (.sideBySide, CGPoint(x: 100, y: 150)),
            (.sideBySide, CGPoint(x: 425, y: 300)),
            // The divider's right edge belongs to B, including its black bar.
            (.sideBySide, CGPoint(x: 400, y: 300)),
            (.verticalWipe, CGPoint(x: 100, y: 300)),
            (.verticalWipe, CGPoint(x: 600, y: 50)),
            (.horizontalWipe, CGPoint(x: 100, y: 150)),
            (.horizontalWipe, CGPoint(x: 600, y: 550)),
            (.overlay, CGPoint(x: 400, y: 50)),
            (.difference, CGPoint(x: 400, y: 50))
        ]
        for (mode, pointer) in cases {
            state.follow(pointer, geometry: geometry, isComparing: true,
                         mode: mode, wipePosition: 0.5, overlayBlend: 0.5)
            XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.25, y: 0.75), "Mode: \(mode)")
            XCTAssertEqual(state.pointer, CGPoint(x: 300, y: 360), "Mode: \(mode)")
        }
    }

    func testFullySecondaryOverlayFollowsBAndRejectsItsPillarbox() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 800, height: 600),
            primaryAspectRatio: 2, secondaryAspectRatio: 0.5
        )
        let state = InspectionLoupeState()
        state.isEnabled = true
        state.follow(CGPoint(x: 325, y: 150), geometry: geometry, isComparing: true,
                     mode: .overlay, wipePosition: 0.5, overlayBlend: 1)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.25, y: 0.25))
        state.follow(CGPoint(x: 100, y: 300), geometry: geometry, isComparing: true,
                     mode: .overlay, wipePosition: 0.5, overlayBlend: 1)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(state.pointer, CGPoint(x: 325, y: 150))
    }

    func testInactiveCompareUsesARegardlessOfStoredPresentation() {
        let geometry = CompareDisplayGeometry(
            canvasSize: CGSize(width: 800, height: 600),
            primaryAspectRatio: 2, secondaryAspectRatio: 0.5
        )
        let state = InspectionLoupeState()
        state.isEnabled = true
        for mode in CompareViewMode.allCases {
            state.follow(CGPoint(x: 600, y: 400), geometry: geometry, isComparing: false,
                         mode: mode, wipePosition: 1, overlayBlend: 1)
            XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.75, y: 0.75))
        }
    }

    func testCenterAndPinKeepsLoupeEnabledAndSelectedMagnification() {
        let state = InspectionLoupeState()
        state.isEnabled = true
        state.magnification = .eightTimes
        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)

        state.reset()
        state.follow(CGPoint(x: 700, y: 160), pictureRect: picture)

        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.isPinned)
        XCTAssertEqual(state.magnification, .eightTimes)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(state.pointer)
    }

    func testClosingClearsPositionAndPinSoReopenedLoupeCanFollow() {
        let state = InspectionLoupeState()
        state.isEnabled = true
        state.follow(CGPoint(x: 300, y: 360), pictureRect: picture)
        state.isPinned = true

        state.close()

        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.isPinned)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(state.pointer)

        state.isEnabled = true
        state.follow(CGPoint(x: 700, y: 160), pictureRect: picture)
        XCTAssertEqual(state.normalizedPoint, CGPoint(x: 0.75, y: 0.25))
    }
}
