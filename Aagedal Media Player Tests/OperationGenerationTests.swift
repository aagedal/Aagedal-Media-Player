// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class OperationGenerationTests: XCTestCase {
    func testAdvanceInvalidatesPreviousGeneration() {
        var generations = OperationGeneration()
        let initial = generations.current

        let replacement = generations.advance()

        XCTAssertFalse(generations.isCurrent(initial))
        XCTAssertTrue(generations.isCurrent(replacement))
    }

    func testOnlyLatestReplacementRemainsCurrent() {
        var generations = OperationGeneration()
        let first = generations.advance()
        let second = generations.advance()

        XCTAssertFalse(generations.isCurrent(first))
        XCTAssertTrue(generations.isCurrent(second))
    }

    func testKeyedReplacementDoesNotInvalidateConcurrentOperation() {
        var generations = KeyedOperationGeneration<Int>()
        let firstStream = generations.begin(for: 0)
        let secondStream = generations.begin(for: 1)
        let firstStreamReplacement = generations.begin(for: 0)

        XCTAssertFalse(generations.isCurrent(firstStream, for: 0))
        XCTAssertTrue(generations.isCurrent(firstStreamReplacement, for: 0))
        XCTAssertTrue(generations.isCurrent(secondStream, for: 1))
    }

    func testStaleFinishCannotClearReplacement() {
        var generations = KeyedOperationGeneration<Int>()
        let stale = generations.begin(for: 0)
        let replacement = generations.begin(for: 0)

        XCTAssertFalse(generations.finish(stale, for: 0))
        XCTAssertTrue(generations.isCurrent(replacement, for: 0))
        XCTAssertTrue(generations.finish(replacement, for: 0))
        XCTAssertFalse(generations.isCurrent(replacement, for: 0))
    }

    func testInvalidateAllRejectsEveryPendingCompletion() {
        var generations = KeyedOperationGeneration<Int>()
        let firstStream = generations.begin(for: 0)
        let secondStream = generations.begin(for: 1)

        generations.invalidateAll()

        XCTAssertFalse(generations.finish(firstStream, for: 0))
        XCTAssertFalse(generations.finish(secondStream, for: 1))
    }

    func testScopeCaptureTickRequiresCurrentRunningSession() {
        let identity = ScopeCaptureTickIdentity(generation: 7)

        XCTAssertTrue(identity.matches(generation: 7, isCapturing: true))
        XCTAssertFalse(identity.matches(generation: 8, isCapturing: true))
        XCTAssertFalse(identity.matches(generation: 7, isCapturing: false))
    }

    func testReversePlaybackTickRequiresCurrentActivePreparation() {
        let identity = ReversePlaybackTickIdentity(
            generation: 11,
            preparationID: 3
        )

        XCTAssertTrue(identity.matches(
            generation: 11,
            preparationID: 3,
            isReversing: true
        ))
        XCTAssertFalse(identity.matches(
            generation: 12,
            preparationID: 3,
            isReversing: true
        ))
        XCTAssertFalse(identity.matches(
            generation: 11,
            preparationID: 4,
            isReversing: true
        ))
        XCTAssertFalse(identity.matches(
            generation: 11,
            preparationID: 3,
            isReversing: false
        ))
    }
}
