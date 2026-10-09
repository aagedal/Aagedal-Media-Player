// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

@MainActor
final class MPVMediaLoadingTests: XCTestCase {
    func testSlowHeaderReadLeavesMainActorResponsiveAndReplacementRejectsOldResult() async throws {
        let started = expectation(description: "Background header read started")
        let finished = expectation(description: "Background header read finished")
        let release = DispatchSemaphore(value: 0)
        let player = MPVPlayer(rifxDetector: { url in
            XCTAssertFalse(Thread.isMainThread, "A network signature read must never run on the UI thread.")
            guard url.lastPathComponent == "slow.mkv" else { return false }
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            finished.fulfill()
            return true
        })
        defer { release.signal(); player.destroy() }
        player.load(url: URL(fileURLWithPath: "/tmp/slow.mkv"))
        await fulfillment(of: [started], timeout: 1)
        let heartbeat = expectation(description: "UI remains responsive during disk read")
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 0.5)
        player.load(url: URL(fileURLWithPath: "/tmp/replacement.mkv"))
        release.signal()
        await fulfillment(of: [finished], timeout: 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(player.error, "An old RIFX result must not fail a replacement file.")
        XCTAssertFalse(player.isFileLoaded)
    }

    func testDestroyRejectsHeaderReadThatFinishesAfterClose() async throws {
        let started = expectation(description: "Header read started")
        let finished = expectation(description: "Header read finished")
        let release = DispatchSemaphore(value: 0)
        let player = MPVPlayer(rifxDetector: { _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            finished.fulfill()
            return true
        })
        defer { release.signal() }
        player.load(url: URL(fileURLWithPath: "/tmp/slow.mkv"))
        await fulfillment(of: [started], timeout: 1)
        player.destroy()
        release.signal()
        await fulfillment(of: [finished], timeout: 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(player.error)
        XCTAssertFalse(player.isFileLoaded)
    }
}
