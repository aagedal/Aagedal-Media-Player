// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class AsyncDeadlineTests: XCTestCase {
    func testReturnsValueCompletedBeforeDeadline() async {
        let value = await AsyncDeadline.value(within: .seconds(1)) {
            42
        }

        XCTAssertEqual(value, 42)
    }

    func testDeadlineDoesNotWaitForSlowOperation() async {
        let clock = ContinuousClock()
        let start = clock.now

        let value: Int? = await AsyncDeadline.value(within: .milliseconds(20)) {
            try? await Task.sleep(for: .seconds(1))
            return 42
        }

        let elapsed = start.duration(to: clock.now)
        XCTAssertNil(value)
        XCTAssertLessThan(elapsed, .milliseconds(500))
    }

    func testTimedOutOperationContinuesToCompletion() async throws {
        let completion = CompletionProbe()

        let value: Int? = await AsyncDeadline.value(within: .milliseconds(10)) {
            try? await Task.sleep(for: .milliseconds(60))
            await completion.markComplete()
            return 42
        }

        XCTAssertNil(value)
        try await Task.sleep(for: .milliseconds(100))
        let didComplete = await completion.didComplete
        XCTAssertTrue(didComplete)
    }
}

private actor CompletionProbe {
    private(set) var didComplete = false

    func markComplete() {
        didComplete = true
    }
}
