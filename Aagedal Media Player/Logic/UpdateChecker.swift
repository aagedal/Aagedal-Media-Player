// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Update checker for the two cases Sparkle deliberately does not handle:
//   1. Homebrew-installed copies — Sparkle would replace the bundle that brew
//      thinks it manages. This checker fetches the latest release info from
//      GitHub and the UI routes the user to `brew upgrade --cask …`.
//   2. Bridge users coming from the pre-Sparkle releases — their old build
//      still polls this checker (now pointed at GitHub) and shows the
//      in-app banner so they can manually install the first Sparkle-enabled
//      release.
//
// Gated off whenever `SparkleUpdater.shared.isActive` is true, so direct-
// download users on the Sparkle-enabled build get exactly one update path.

import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "UpdateChecker")

    @Published var latestVersion: String = ""
    @Published var releaseNotesURL: URL? = nil
    @Published var downloadAssetURL: URL? = nil
    @Published var updateAvailable: Bool = false
    @Published var isChecking: Bool = false

    var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: "updateLastChecked") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "updateLastChecked") }
    }

    /// True when this app was installed via Homebrew. The checker still
    /// fetches the release feed and reports `updateAvailable`, but the UI
    /// branches: brew users get the `brew upgrade --cask …` command instead
    /// of a Download button, so we don't replace a bundle brew thinks it
    /// manages.
    let isHomebrewInstall: Bool = (InstallSource.current == .homebrew)

    /// The shell command shown to Homebrew-managed users when an update
    /// exists. Single source of truth for the Settings hint and the banner.
    static let homebrewUpgradeCommand = "brew upgrade --cask aagedal-media-player"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private let releasesAPIURL = URL(string: "https://api.github.com/repos/aagedal/Aagedal-Media-Player/releases/latest")!
    private let fallbackReleasesPageURL = URL(string: "https://github.com/aagedal/Aagedal-Media-Player/releases/latest")!

    private init() {}

    func checkIfNeeded() {
        guard !SparkleUpdater.shared.isActive else { return }

        let interval = UserDefaults.standard.double(forKey: "updateCheckInterval")
        let checkInterval = interval > 0 ? interval : 7 * 24 * 3600 // Default: weekly

        if let last = lastChecked, Date().timeIntervalSince(last) < checkInterval {
            return
        }

        Task { await checkNow(isUserInitiated: false) }
    }

    func checkNow(isUserInitiated: Bool = true) async {
        guard !isChecking else { return }
        guard !SparkleUpdater.shared.isActive else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: releasesAPIURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let delegate = GitHubRedirectGuard()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Self.logger.error("Update check returned non-200 status")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawTag = json["tag_name"] as? String else {
                Self.logger.error("Update check could not parse tag_name from release JSON")
                return
            }

            let remoteVersion = AppVersion.normalized(rawTag)
            let notesURL = (json["html_url"] as? String).flatMap(URL.init(string:))
            let assetURL = pickDownloadAsset(from: json["assets"] as? [[String: Any]] ?? [])

            self.latestVersion = remoteVersion
            self.releaseNotesURL = notesURL
            self.downloadAssetURL = assetURL
            self.updateAvailable = AppVersion.isNewer(remoteVersion, than: currentVersion)

            if !isUserInitiated {
                self.lastChecked = Date()
            }
        } catch {
            Self.logger.error("Error checking for updates: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pickDownloadAsset(from assets: [[String: Any]]) -> URL? {
        let candidates: [(name: String, url: URL)] = assets.compactMap { asset in
            guard let name = asset["name"] as? String,
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else {
                return nil
            }
            return (name, url)
        }

        if let zip = candidates.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
            return zip.url
        }
        if let dmg = candidates.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return dmg.url
        }
        return nil
    }

    func openDownloadAsset() {
        NSWorkspace.shared.open(downloadAssetURL ?? fallbackReleasesPageURL)
    }

    func openReleaseNotes() {
        NSWorkspace.shared.open(releaseNotesURL ?? fallbackReleasesPageURL)
    }

    private static let userAgent: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.aagedal.MediaPlayer"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "\(bundleID)/\(version)"
    }()
}

// MARK: - GitHub redirect guard

/// Refuses HTTP redirects away from GitHub's API host. A cross-host redirect
/// indicates either a hijack or a misconfigured request and is rejected.
private final class GitHubRedirectGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let host = request.url?.host?.lowercased() else {
            completionHandler(nil)
            return
        }
        if host == "api.github.com" {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
