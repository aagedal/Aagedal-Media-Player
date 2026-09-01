// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class NumericDefaultsTests: XCTestCase {
    func testClampedPreservesValidZero() {
        XCTAssertEqual(0.0.clamped(to: 0...100, default: 65), 0)
    }

    func testClampedUsesDefaultForNonFiniteValues() {
        XCTAssertEqual(Double.nan.clamped(to: 0...100, default: 65), 65)
        XCTAssertEqual(Double.infinity.clamped(to: 0...100, default: 65), 65)
    }

    func testClampedBoundsStoredValues() {
        XCTAssertEqual((-10.0).clamped(to: 1...100, default: 65), 1)
        XCTAssertEqual(120.0.clamped(to: 1...100, default: 65), 100)
        XCTAssertEqual(42.0.clamped(to: 1...100, default: 65), 42)
    }
}
