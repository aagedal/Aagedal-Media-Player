// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class DeferredMainActorTaskTests: XCTestCase {
    func testCancellationPreventsDeferredOperationFromStarting() async {
        let owner = DeferredMainActorTask()
        let probe = DeferredTaskProbe()

        let task = owner.schedule {
            probe.events.append("cancelled")
        }
        owner.cancel()

        await task.value
        XCTAssertTrue(probe.events.isEmpty)
    }

    func testReplacementRunsOnlyLatestDeferredOperation() async {
        let owner = DeferredMainActorTask()
        let probe = DeferredTaskProbe()

        let staleTask = owner.schedule {
            probe.events.append("stale")
        }
        let currentTask = owner.schedule {
            probe.events.append("current")
        }

        await staleTask.value
        await currentTask.value
        XCTAssertEqual(probe.events, ["current"])
    }
}

@MainActor
private final class DeferredTaskProbe {
    var events: [String] = []
}
