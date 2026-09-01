// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MediaOperationStateTests: XCTestCase {
    func testScreenshotVisibilityTracksIdleState() {
        let visibility = [
            ScreenshotOperationState.idle.isVisible,
            ScreenshotOperationState.saving.isVisible,
            ScreenshotOperationState.succeeded(URL(fileURLWithPath: "/tmp/frame.png")).isVisible,
            ScreenshotOperationState.failed("Unable to save").isVisible
        ]

        XCTAssertEqual(visibility, [false, true, true, true])
    }

    func testTrimExportVisibilityTracksEveryFeedbackState() {
        let visibility = [
            TrimExportOperationState.idle.isVisible,
            TrimExportOperationState.warning("Set trim points").isVisible,
            TrimExportOperationState.preparing.isVisible,
            TrimExportOperationState.exporting(progress: 0.5).isVisible,
            TrimExportOperationState.cancelling.isVisible,
            TrimExportOperationState.cancelled.isVisible,
            TrimExportOperationState.succeeded(URL(fileURLWithPath: "/tmp/trim.mov")).isVisible,
            TrimExportOperationState.failed("Unable to export").isVisible
        ]

        XCTAssertEqual(visibility, [false, true, true, true, true, true, true, true])
    }

    func testOnlyActiveOperationsAreInFlight() {
        let screenshotStates: [ScreenshotOperationState] = [
            .idle,
            .saving,
            .succeeded(URL(fileURLWithPath: "/tmp/frame.png")),
            .failed("Unable to save")
        ]
        let exportStates: [TrimExportOperationState] = [
            .idle,
            .warning("Set trim points"),
            .preparing,
            .exporting(progress: 0.5),
            .cancelling,
            .cancelled,
            .succeeded(URL(fileURLWithPath: "/tmp/trim.mov")),
            .failed("Unable to export")
        ]

        XCTAssertEqual(screenshotStates.map(\.isInFlight), [false, true, false, false])
        XCTAssertEqual(exportStates.map(\.isInFlight), [false, false, true, true, true, false, false, false])
        XCTAssertEqual(exportStates.map(\.acceptsProgress), [false, false, true, true, false, false, false, false])
    }
}
