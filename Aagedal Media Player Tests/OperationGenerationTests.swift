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
}
