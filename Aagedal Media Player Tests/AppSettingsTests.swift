// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRegistersCanonicalDefaults() {
        AppSettings.registerDefaults(in: defaults)

        XCTAssertTrue(defaults.value(for: AppSettings.openAtSourceResolution))
        XCTAssertEqual(defaults.value(for: AppSettings.precisionScrubFactor), 10)
        XCTAssertEqual(defaults.value(for: AppSettings.scopeResolution), 720)
        XCTAssertEqual(defaults.value(for: AppSettings.scopeFrameRate), 15)
        XCTAssertEqual(defaults.value(for: AppSettings.audioWaveformColor), "FF2D78")
        XCTAssertEqual(defaults.value(for: AppSettings.playbackVolume), 100)
        XCTAssertFalse(defaults.value(for: AppSettings.didShowCompareModeCallout))
    }

    func testPersistedValueOverridesRegisteredDefault() {
        defaults.set(1080, for: AppSettings.scopeResolution)
        AppSettings.registerDefaults(in: defaults)

        XCTAssertEqual(defaults.value(for: AppSettings.scopeResolution), 1080)
    }

    func testTypedReadFallsBackBeforeDefaultsAreRegistered() {
        XCTAssertEqual(
            defaults.value(for: AppSettings.trimExportFormat),
            AppSettings.trimExportFormat.defaultValue
        )
        XCTAssertEqual(
            defaults.value(for: AppSettings.updateCheckInterval),
            AppSettings.updateCheckInterval.defaultValue
        )
    }

    func testTypedWritesRoundTrip() {
        defaults.set(42.5, for: AppSettings.playbackVolume)
        defaults.set(true, for: AppSettings.playbackMuted)

        XCTAssertEqual(defaults.value(for: AppSettings.playbackVolume), 42.5)
        XCTAssertTrue(defaults.value(for: AppSettings.playbackMuted))
    }

    func testStorageKeysRemainCompatibleWithExistingVersions() {
        XCTAssertEqual(AppSettings.screenshotLocationMode.key, "screenshotLocationMode")
        XCTAssertEqual(AppSettings.trimExportFormat.key, "trimExportFormat")
        XCTAssertEqual(AppSettings.scopeResolution.key, "scopeResolution")
        XCTAssertEqual(AppSettings.playbackVolume.key, "playbackVolume")
        XCTAssertEqual(AppSettings.didShowCompareModeCallout.key, "didShowCompareModeCallout")
    }
}
