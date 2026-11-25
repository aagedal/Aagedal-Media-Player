// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class SettingsNavigationTests: XCTestCase {
    func testAllCategoriesBelongToExactlyOneGroup() {
        let grouped = SettingsCategoryGroup.allCases.flatMap(\.categories)
        XCTAssertEqual(grouped.count, SettingsCategory.allCases.count)
        XCTAssertEqual(Set(grouped), Set(SettingsCategory.allCases))
    }

    func testEveryCategoryIsIndexedForSearch() {
        let indexedCategories = Set(SettingsSearchIndex.allItems.map(\.category))
        XCTAssertEqual(indexedCategories, Set(SettingsCategory.allCases))
    }

    func testSearchFindsCleanfeedSettingsByHardwareAndSignalKeywords() {
        XCTAssertTrue(SettingsSearchIndex.search("Blackmagic").contains { $0.category == .cleanfeed })
        XCTAssertTrue(SettingsSearchIndex.search("UltraStudio").contains { $0.category == .cleanfeed })
        XCTAssertTrue(SettingsSearchIndex.search("v210").contains { $0.category == .cleanfeed })
        XCTAssertTrue(SettingsSearchIndex.search("4K limit").contains { $0.id == "cleanfeed.resolution" })
        XCTAssertTrue(SettingsSearchIndex.search("HDR PQ").contains { $0.id == "cleanfeed.colorspace" })
        XCTAssertTrue(SettingsSearchIndex.search("SMPTE").contains { $0.id == "cleanfeed.timecode" })
    }

    func testSearchMatchesAcrossOtherCategoriesAndHandlesEmptyOrMissing() {
        XCTAssertTrue(SettingsSearchIndex.search("jxl").contains { $0.category == .screenshots })
        XCTAssertTrue(SettingsSearchIndex.search("hevc").contains { $0.category == .export })
        XCTAssertTrue(SettingsSearchIndex.search("parade").contains { $0.category == .scopes })
        XCTAssertTrue(SettingsSearchIndex.search("multi-mono").contains { $0.category == .audio })
        XCTAssertTrue(SettingsSearchIndex.search("homebrew").contains { $0.category == .updates })
        XCTAssertTrue(SettingsSearchIndex.search("   ").isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search("zzzznonexistent").isEmpty)
    }
}
