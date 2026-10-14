// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MPVRecoveryTests: XCTestCase {
    func testReversalBudgetLeavesRoomForPairedDecodersOnSmallMachines() {
        let gib: UInt64 = 1_073_741_824
        XCTAssertEqual(MPVPlaybackPolicy.reversalBufferBytes(physicalMemory: 8 * gib), gib / 2)
        XCTAssertEqual(MPVPlaybackPolicy.reversalBufferBytes(physicalMemory: 16 * gib), gib)
        XCTAssertEqual(MPVPlaybackPolicy.reversalBufferBytes(physicalMemory: 64 * gib), 4 * gib)
        XCTAssertEqual(MPVPlaybackPolicy.reversalBufferBytes(physicalMemory: UInt64.max), 4 * gib)
        XCTAssertEqual(MPVPlaybackPolicy.reversalBufferBytes(physicalMemory: 0), gib / 4)
    }

    func testReverseFailureWarningPublishesRecoveryInReleaseToo() async {
        let player = MPVPlayer()
        let recovered = expectation(description: "Reverse failure reaches transport")
        let subscription = player.backwardPlaybackFailed.sink {
            XCTAssertTrue(Thread.isMainThread)
            recovered.fulfill()
        }
        player.handleLogMessage(prefix: "vd", level: "warn",
                                text: "Backward playback is likely stuck/broken now.\n")
        await fulfillment(of: [recovered], timeout: 1)
        withExtendedLifetime(subscription) {}
    }

    func testUnrelatedWarningDoesNotTriggerReverseRecovery() async {
        let player = MPVPlayer()
        let unexpected = expectation(description: "Unrelated warning")
        unexpected.isInverted = true
        let subscription = player.backwardPlaybackFailed.sink { unexpected.fulfill() }
        player.handleLogMessage(prefix: "ao", level: "warn", text: "Audio device unavailable\n")
        await fulfillment(of: [unexpected], timeout: 0.1)
        withExtendedLifetime(subscription) {}
    }
}
