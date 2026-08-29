// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class AppVersionTests: XCTestCase {
    func testNormalizationRemovesTagPrefixAndWhitespace() {
        XCTAssertEqual(AppVersion.normalized(" v1.6.1\n"), "1.6.1")
        XCTAssertEqual(AppVersion.normalized("V2.0"), "2.0")
        XCTAssertEqual(AppVersion.normalized("1.5.0"), "1.5.0")
    }

    func testNumericVersionComparison() {
        XCTAssertTrue(AppVersion.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(AppVersion.isNewer("v2.0", than: "1.99"))
        XCTAssertFalse(AppVersion.isNewer("1.6.1", than: "1.6.1"))
        XCTAssertFalse(AppVersion.isNewer("1.6.0", than: "1.6.1"))
    }
}
