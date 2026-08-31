// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class LatestFrameGateTests: XCTestCase {
    func testKeepsOnlyNewestPendingGeneration() {
        var gate = LatestFrameGate()

        let first = gate.submit()
        let second = gate.submit()
        let third = gate.submit()

        XCTAssertTrue(first.startImmediately)
        XCTAssertFalse(second.startImmediately)
        XCTAssertFalse(third.startImmediately)
        XCTAssertEqual(gate.activeGeneration, first.generation)
        XCTAssertEqual(gate.pendingGeneration, third.generation)
    }

    func testStaleCompletionStartsNewestPendingWithoutPublishing() {
        var gate = LatestFrameGate()
        let first = gate.submit()
        _ = gate.submit()
        let latest = gate.submit()

        let firstCompletion = gate.complete(first.generation)
        XCTAssertEqual(
            firstCompletion,
            LatestFrameGate.Completion(shouldPublish: false, nextGeneration: latest.generation)
        )

        let latestCompletion = gate.complete(latest.generation)
        XCTAssertEqual(
            latestCompletion,
            LatestFrameGate.Completion(shouldPublish: true, nextGeneration: nil)
        )
    }

    func testResetInvalidatesAnOutstandingCompletion() {
        var gate = LatestFrameGate()
        let submission = gate.submit()

        gate.reset()

        XCTAssertNil(gate.complete(submission.generation))
        XCTAssertNil(gate.activeGeneration)
        XCTAssertNil(gate.pendingGeneration)
    }
}
