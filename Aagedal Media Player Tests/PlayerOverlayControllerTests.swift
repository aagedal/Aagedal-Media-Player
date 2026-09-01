// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerOverlayControllerTests: XCTestCase {
    func testRightEdgeHoverHidesAndLeavingRevealsOverlay() {
        let controller = PlayerOverlayController()

        controller.setRightEdgeHovered(
            true,
            isPlaying: { false },
            isEditingTimecode: { false }
        )
        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(controller.isRightEdgeHovered)

        controller.setRightEdgeHovered(
            false,
            isPlaying: { false },
            isEditingTimecode: { false }
        )
        XCTAssertTrue(controller.isVisible)
        XCTAssertFalse(controller.isRightEdgeHovered)
    }

    func testControlHoverPreventsScheduledHide() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        controller.setControlsHovered(true)
        controller.scheduleHide(
            isPlaying: { true },
            isEditingTimecode: { false }
        )

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(controller.isVisible)
    }

    func testScheduledHideUsesLatestPlaybackState() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        var isPlaying = true
        controller.scheduleHide(
            isPlaying: { isPlaying },
            isEditingTimecode: { false }
        )
        isPlaying = false

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(controller.isVisible)
    }

    func testScheduledHideDismissesOverlayDuringPlayback() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        controller.scheduleHide(
            isPlaying: { true },
            isEditingTimecode: { false }
        )

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(controller.isVisible)
    }
}
