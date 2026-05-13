// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import Sparkle
import SwiftUI

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController` so the rest of
/// the app can interact with the updater through one stable handle and
/// pre-flight checks. Two gates decide whether the updater actually runs:
///
/// 1. **Install source** — Homebrew installs use the in-app `UpdateChecker`
///    (notify, route to `brew upgrade`) so Sparkle never replaces a bundle
///    brew thinks it manages.
/// 2. **Sparkle configuration** — if `SUFeedURL` isn't present in Info.plist,
///    Sparkle has nothing to talk to. We avoid starting the updater so the
///    console doesn't fill with misconfiguration warnings during development.
///
/// Both gates fail closed: `isActive == false` means the updater object still
/// exists (so SwiftUI bindings compile), but `startingUpdater` was `false` and
/// no checks will fire.
@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    let controller: SPUStandardUpdaterController

    /// True when Sparkle is actually polling and able to install updates.
    /// False for Homebrew installs or when SUFeedURL is unset.
    let isActive: Bool

    /// `UserDefaults` flag tracking whether the one-time "automatic updates
    /// are on" notice has been shown. Stored in `UserDefaults.standard` so it
    /// survives every app/Sparkle bundle swap.
    private static let didShowAutoUpdateNoticeKey = "didShowAutoUpdateNotice"

    private init() {
        let hasFeedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .isEmpty == false
        let isDirectInstall = InstallSource.current == .directDownload
        let active = hasFeedURL && isDirectInstall

        self.isActive = active
        self.controller = SPUStandardUpdaterController(
            startingUpdater: active,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { controller.updater }

    /// One-time notice that automatic updates are on, so users discover the
    /// opt-out without having to find Settings → Updates on their own.
    func presentFirstLaunchNoticeIfNeeded() {
        guard isActive else { return }
        guard updater.automaticallyDownloadsUpdates else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didShowAutoUpdateNoticeKey) else { return }
        defaults.set(true, forKey: Self.didShowAutoUpdateNoticeKey)

        let alert = NSAlert()
        alert.messageText = "Automatic updates are on"
        alert.informativeText = "New releases will download and install in the background so you stay current without thinking about it. You can turn this off any time in Settings → Updates."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings\u{2026}")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
