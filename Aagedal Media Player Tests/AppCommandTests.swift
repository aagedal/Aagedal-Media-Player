// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Combine
import Foundation
import XCTest

final class AppCommandTests: XCTestCase {
    @MainActor
    func testTypedPayloadRoundTripsThroughCommandChannel() {
        let center = NotificationCenter()
        var receivedCommand: AppCommand?
        let cancellable = center.appCommandPublisher.sink { notification in
            receivedCommand = notification.appCommand
        }

        center.post(.seekBySeconds(-10))

        guard case let .seekBySeconds(seconds) = receivedCommand else {
            return XCTFail("Expected a typed seek command")
        }
        XCTAssertEqual(seconds, -10)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testOpenFileRetainsTypedWindowTarget() {
        let center = NotificationCenter()
        let targetWindow = NSWindow()
        let url = URL(fileURLWithPath: "/tmp/example.mov")
        var receivedCommand: AppCommand?
        let cancellable = center.appCommandPublisher.sink { notification in
            receivedCommand = notification.appCommand
        }

        center.post(.openFile(url, targetWindow: targetWindow))

        guard case let .openFile(receivedURL, receivedWindow) = receivedCommand else {
            return XCTFail("Expected a typed open-file command")
        }
        XCTAssertEqual(receivedURL, url)
        XCTAssertTrue(receivedWindow === targetWindow)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testUnrelatedNotificationIsNotAnAppCommand() {
        let notification = Notification(name: NSApplication.didBecomeActiveNotification)
        XCTAssertNil(notification.appCommand)
    }
}
