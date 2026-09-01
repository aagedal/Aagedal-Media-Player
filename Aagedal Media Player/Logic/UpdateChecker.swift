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

import AppKit
import Combine
import Foundation
import OSLog

struct UpdateRelease: Equatable, Sendable {
    let version: String
    let releaseNotesURL: URL?
    let downloadAssetURL: URL?
}

enum UpdateCheckFailure: Equatable, Sendable {
    case network(String)
    case serverStatus(Int)
    case invalidResponse

    var isRetryable: Bool {
        switch self {
        case .network:
            true
        case .serverStatus(let statusCode):
            statusCode == 408 || statusCode == 429 || statusCode >= 500
        case .invalidResponse:
            false
        }
    }

    var message: String {
        switch self {
        case .network:
            "Couldn’t reach the update service."
        case .serverStatus(let statusCode):
            "The update service returned HTTP \(statusCode)."
        case .invalidResponse:
            "The update service returned an invalid release description."
        }
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case notChecked
    case checking
    case upToDate(UpdateRelease)
    case updateAvailable(UpdateRelease)
    case failed(UpdateCheckFailure)

    var release: UpdateRelease? {
        switch self {
        case .upToDate(let release), .updateAvailable(let release):
            release
        case .notChecked, .checking, .failed:
            nil
        }
    }
}

struct UpdateHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

@MainActor
final class UpdateChecker: ObservableObject {
    typealias Fetch = @Sendable (URLRequest) async throws -> UpdateHTTPResponse

    static let shared = UpdateChecker()
    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "UpdateChecker")

    @Published private(set) var result: UpdateCheckResult = .notChecked

    var latestVersion: String { result.release?.version ?? "" }
    var releaseNotesURL: URL? { result.release?.releaseNotesURL }
    var downloadAssetURL: URL? { result.release?.downloadAssetURL }
    var updateAvailable: Bool {
        if case .updateAvailable = result { true } else { false }
    }
    var isChecking: Bool { result == .checking }

    var lastChecked: Date? {
        get { defaults.object(forKey: AppSettings.updateLastChecked.key) as? Date }
        set { defaults.set(newValue, forKey: AppSettings.updateLastChecked.key) }
    }

    /// True when this app was installed via Homebrew. The checker still
    /// fetches the release feed and reports `updateAvailable`, but the UI
    /// branches: brew users get the `brew upgrade --cask …` command instead
    /// of a Download button, so we don't replace a bundle brew thinks it
    /// manages.
    let isHomebrewInstall: Bool

    /// The shell command shown to Homebrew-managed users when an update
    /// exists. Single source of truth for the Settings hint and the banner.
    static let homebrewUpgradeCommand = "brew upgrade --cask aagedal-media-player"

    let currentVersion: String

    private let releasesAPIURL = URL(string: "https://api.github.com/repos/aagedal/Aagedal-Media-Player/releases/latest")!
    private let fallbackReleasesPageURL = URL(string: "https://github.com/aagedal/Aagedal-Media-Player/releases/latest")!
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let fetch: Fetch
    private let sparkleIsActive: Bool

    init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
        isHomebrewInstall: Bool = InstallSource.current == .homebrew,
        sparkleIsActive: Bool = SparkleUpdater.shared.isActive,
        fetch: Fetch? = nil
    ) {
        self.defaults = defaults
        self.now = now
        self.currentVersion = currentVersion
        self.isHomebrewInstall = isHomebrewInstall
        self.sparkleIsActive = sparkleIsActive
        self.fetch = fetch ?? Self.fetchLatestRelease
    }

    @discardableResult
    func checkIfNeeded() -> Task<UpdateCheckResult, Never>? {
        guard !sparkleIsActive else { return nil }

        let checkInterval = defaults.value(for: AppSettings.updateCheckInterval)

        if let last = lastChecked, now().timeIntervalSince(last) < checkInterval {
            return nil
        }

        return Task { await checkNow(isUserInitiated: false) }
    }

    @discardableResult
    func checkNow(isUserInitiated _: Bool = true) async -> UpdateCheckResult {
        guard !isChecking, !sparkleIsActive else { return result }
        result = .checking

        var request = URLRequest(url: releasesAPIURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        do {
            let response = try await fetch(request)

            guard response.statusCode == 200 else {
                let failure = UpdateCheckFailure.serverStatus(response.statusCode)
                result = .failed(failure)
                Self.logger.error("Update check returned HTTP \(response.statusCode)")
                return result
            }

            guard let release = Self.parseRelease(from: response.data) else {
                let failure = UpdateCheckFailure.invalidResponse
                result = .failed(failure)
                Self.logger.error("Update check could not parse tag_name from release JSON")
                return result
            }

            lastChecked = now()
            result = AppVersion.isNewer(release.version, than: currentVersion)
                ? .updateAvailable(release)
                : .upToDate(release)
        } catch {
            let failure = UpdateCheckFailure.network(error.localizedDescription)
            result = .failed(failure)
            Self.logger.error("Error checking for updates: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    nonisolated private static func parseRelease(from data: Data) -> UpdateRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawTag = json["tag_name"] as? String else { return nil }

        return UpdateRelease(
            version: AppVersion.normalized(rawTag),
            releaseNotesURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
            downloadAssetURL: pickDownloadAsset(from: json["assets"] as? [[String: Any]] ?? [])
        )
    }

    nonisolated private static func pickDownloadAsset(from assets: [[String: Any]]) -> URL? {
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

    nonisolated private static func fetchLatestRelease(request: URLRequest) async throws -> UpdateHTTPResponse {
        let delegate = GitHubRedirectGuard()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return UpdateHTTPResponse(data: data, statusCode: httpResponse.statusCode)
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
