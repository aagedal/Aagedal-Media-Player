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
        XCTAssertFalse(CompareViewMode.sideBySide.isWipe)
    }
}
