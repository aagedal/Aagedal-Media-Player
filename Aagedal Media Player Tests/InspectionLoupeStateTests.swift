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
