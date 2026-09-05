// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import AppKit
import Combine
import XCTest

@MainActor
final class WindowManagerTests: XCTestCase {
    func testMediaWindowCountTracksRegistrationOpeningAndClosing() {
        let manager = WindowManager.shared
        let baseline = manager.mediaWindowCount
        let firstID = UUID()
        let secondID = UUID()
        let first = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let second = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        defer {
            manager.unregister(id: firstID)
            manager.unregister(id: secondID)
        }
        var updates = 0
        let observation = manager.objectWillChange.sink { updates += 1 }
        defer { observation.cancel() }

        manager.register(id: firstID, window: first)
        manager.register(id: secondID, window: second)
        XCTAssertEqual(manager.mediaWindowCount, baseline, "Empty windows are not sync participants")
        manager.markHasMedia(id: firstID)
        XCTAssertEqual(manager.mediaWindowCount, baseline + 1)
        manager.markHasMedia(id: secondID)
        XCTAssertEqual(manager.mediaWindowCount, baseline + 2)
        manager.unregister(id: firstID)
        XCTAssertEqual(manager.mediaWindowCount, baseline + 1)
        manager.unregister(id: secondID)
        XCTAssertEqual(manager.mediaWindowCount, baseline)
        XCTAssertGreaterThanOrEqual(updates, 6, "The visible status must refresh as windows change")
    }

    func testMediaReservationWithoutLiveWindowIsNotCounted() {
        let manager = WindowManager.shared
        let baseline = manager.mediaWindowCount
        let id = UUID()
        defer { manager.unregister(id: id) }
        manager.markHasMedia(id: id)
        XCTAssertEqual(manager.mediaWindowCount, baseline)
    }
}
