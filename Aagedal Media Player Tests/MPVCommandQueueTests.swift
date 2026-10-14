// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVCommandQueueTests: XCTestCase {
    func testPauseDirectionSpeedAndPlayWaitForEachPreviousReply() throws {
        var queue = MPVCommandQueue()
        let pause = try XCTUnwrap(queue.enqueue(arguments: ["set", "pause", "yes"]))
        XCTAssertNil(queue.enqueue(arguments: ["set", "play-direction", "backward"]))
        XCTAssertNil(queue.enqueue(arguments: ["set", "speed", "2"]))
        XCTAssertNil(queue.enqueue(arguments: ["set", "pause", "no"]))
        XCTAssertNil(queue.completed(id: 0))
        XCTAssertEqual(queue.inFlight, pause)
        let direction = try XCTUnwrap(queue.completed(id: pause.id))
        XCTAssertEqual(direction.arguments, ["set", "play-direction", "backward"])
        XCTAssertNil(queue.completed(id: pause.id))
        let speed = try XCTUnwrap(queue.completed(id: direction.id))
        XCTAssertEqual(speed.arguments, ["set", "speed", "2"])
        let play = try XCTUnwrap(queue.completed(id: speed.id))
        XCTAssertEqual(play.arguments, ["set", "pause", "no"])
        XCTAssertNil(queue.completed(id: play.id))
        XCTAssertNil(queue.inFlight)
    }

    func testSeekAndLoadIDsRemainDistinctAndPendingReplacementWaitsForActiveCommand() throws {
        var queue = MPVCommandQueue()
        let seek = try XCTUnwrap(queue.enqueue(arguments: ["seek", "10"], id: 1))
        XCTAssertNil(queue.enqueue(arguments: ["set", "pause", "no"]))
        queue.discardPending()
        let loadID: UInt64 = (1 << 63) | 5
        XCTAssertNil(queue.enqueue(arguments: ["loadfile", "new.mov"], id: loadID))
        let load = try XCTUnwrap(queue.completed(id: seek.id))
        XCTAssertEqual(load.id, loadID)
        XCTAssertNil(queue.completed(id: load.id))
        let control = try XCTUnwrap(queue.enqueue(arguments: ["set", "pause", "yes"]))
        XCTAssertNotEqual(control.id, 0)
        XCTAssertNotEqual(control.id & (1 << 62), 0)
        XCTAssertEqual(control.id & (1 << 63), 0)
    }

    func testResetDiscardsPendingWorkAndRejectsOldReplies() throws {
        var queue = MPVCommandQueue()
        let first = try XCTUnwrap(queue.enqueue(arguments: ["set", "pause", "yes"]))
        XCTAssertNil(queue.enqueue(arguments: ["seek", "10"], id: 1))
        queue.reset()
        let replacement = try XCTUnwrap(queue.enqueue(arguments: ["set", "pause", "no"]))
        XCTAssertNotEqual(first.id, replacement.id)
        XCTAssertNil(queue.completed(id: first.id))
        XCTAssertEqual(queue.inFlight, replacement)
        XCTAssertNil(queue.completed(id: replacement.id))
    }
}
