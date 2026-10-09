// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class MPVSeekSchedulerTests: XCTestCase {
    func testDragWaitsForDecodedFrameAndKeepsOnlyLatestTarget() throws {
        var scheduler = MPVSeekScheduler()
        let first = try XCTUnwrap(scheduler.request(.init(time: 10, exact: false)))
        for time in 11...100 {
            XCTAssertNil(scheduler.request(.init(time: Double(time), exact: false)))
        }
        XCTAssertNil(scheduler.commandReplied(id: first.id, succeeded: true))
        // Command acceptance and unrelated startup restart cannot unblock it.
        XCTAssertNil(scheduler.playbackRestarted())
        XCTAssertEqual(scheduler.inFlight, first)
        scheduler.seekStarted()
        let next = try XCTUnwrap(scheduler.playbackRestarted())
        XCTAssertEqual(next.request, .init(time: 100, exact: false))
        XCTAssertNil(scheduler.pending)
    }

    func testReleaseReplacesPendingPreviewWithPreciseTarget() throws {
        var scheduler = MPVSeekScheduler()
        let first = try XCTUnwrap(scheduler.request(.init(time: 10, exact: false)))
        XCTAssertNil(scheduler.request(.init(time: 20, exact: false)))
        scheduler.cancelPendingPreview()
        XCTAssertNil(scheduler.request(.init(time: 20.75, exact: true)))
        // Cancelling further preview work must preserve the final exact seek.
        scheduler.cancelPendingPreview()
        scheduler.seekStarted()
        XCTAssertNil(scheduler.commandReplied(id: first.id, succeeded: true))
        let final = try XCTUnwrap(scheduler.playbackRestarted())
        XCTAssertEqual(final.request, .init(time: 20.75, exact: true))
        scheduler.seekStarted()
        XCTAssertNil(scheduler.commandReplied(id: final.id, succeeded: true))
        XCTAssertNil(scheduler.playbackRestarted())
        XCTAssertNil(scheduler.inFlight)
        XCTAssertNil(scheduler.pending)
    }

    func testRestartBeforeCommandReplyStillFinishesExactlyOnce() throws {
        var scheduler = MPVSeekScheduler()
        let first = try XCTUnwrap(scheduler.request(.init(time: 10, exact: false)))
        XCTAssertNil(scheduler.request(.init(time: 20, exact: false)))
        scheduler.seekStarted()
        XCTAssertNil(scheduler.playbackRestarted())
        let next = try XCTUnwrap(scheduler.commandReplied(id: first.id, succeeded: true))
        XCTAssertEqual(next.request.time, 20)
        XCTAssertNil(scheduler.commandReplied(id: first.id, succeeded: true))
        XCTAssertNil(scheduler.playbackRestarted())
        XCTAssertEqual(scheduler.inFlight, next)
    }

    func testFailedCommandAllowsLatestRequestAndResetRejectsOldReplies() throws {
        var scheduler = MPVSeekScheduler()
        let first = try XCTUnwrap(scheduler.request(.init(time: 10, exact: false)))
        XCTAssertNil(scheduler.request(.init(time: 20, exact: true)))
        let next = try XCTUnwrap(scheduler.commandReplied(id: first.id, succeeded: false))
        XCTAssertTrue(next.request.exact)
        scheduler.reset()
        XCTAssertNil(scheduler.pending)
        XCTAssertNil(scheduler.inFlight)
        let replacement = try XCTUnwrap(scheduler.request(.init(time: 30, exact: false)))
        XCTAssertNotEqual(replacement.id, next.id)
        XCTAssertNil(scheduler.commandReplied(id: next.id, succeeded: false))
        XCTAssertNil(scheduler.playbackRestarted())
        XCTAssertEqual(scheduler.inFlight, replacement)
    }

    func testCancellationDropsWaitingPreviewAndInvalidTargetsAreIgnored() throws {
        var scheduler = MPVSeekScheduler()
        let first = try XCTUnwrap(scheduler.request(.init(time: 10, exact: false)))
        XCTAssertNil(scheduler.request(.init(time: 20, exact: false)))
        for time in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(scheduler.request(.init(time: time, exact: true)))
        }
        XCTAssertEqual(scheduler.pending?.time, 20)
        scheduler.cancelPendingPreview()
        scheduler.seekStarted()
        XCTAssertNil(scheduler.commandReplied(id: first.id, succeeded: true))
        XCTAssertNil(scheduler.playbackRestarted())
        XCTAssertNil(scheduler.inFlight)
    }
}
