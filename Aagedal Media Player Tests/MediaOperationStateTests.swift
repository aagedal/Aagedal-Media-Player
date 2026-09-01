// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import Combine
@testable import Aagedal_Media_Player

@MainActor
final class MediaOperationStateTests: XCTestCase {
    func testPlayerControllerForwardsMediaOperationChanges() {
        let controller = PlayerController()
        var changeCount = 0
        let cancellable = controller.objectWillChange.sink {
            changeCount += 1
        }

        controller.setTrimIn()

        XCTAssertEqual(controller.trimIn, 0)
        XCTAssertGreaterThan(changeCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testSettingTrimInClearsAnOverlappingOutPoint() {
        let operations = MediaOperationsController()
        operations.setTrimOut(at: 10)

        operations.setTrimIn(at: 10)

        XCTAssertEqual(operations.trimIn, 10)
        XCTAssertNil(operations.trimOut)
    }

    func testSettingTrimOutClearsAnOverlappingInPoint() {
        let operations = MediaOperationsController()
        operations.setTrimIn(at: 10)

        operations.setTrimOut(at: 10)

        XCTAssertNil(operations.trimIn)
        XCTAssertEqual(operations.trimOut, 10)
    }

    func testClearTrimPointsResetsBothPoints() {
        let operations = MediaOperationsController()
        operations.setTrimIn(at: 5)
        operations.setTrimOut(at: 10)

        operations.clearTrimPoints()

        XCTAssertNil(operations.trimIn)
        XCTAssertNil(operations.trimOut)
    }

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
