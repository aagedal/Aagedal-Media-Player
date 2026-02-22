// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Combine
import os

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var updateAvailable = false

    var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: "updateLastChecked") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "updateLastChecked") }
    }

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "UpdateChecker")
    private let caskURL = URL(string: "https://raw.githubusercontent.com/aagedal/homebrew-casks/main/Casks/aagedal-media-player.rb")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private init() {
        // Restore cached latest version
        if let cached = UserDefaults.standard.string(forKey: "updateLatestVersion") {
            latestVersion = cached
            updateAvailable = isNewer(cached, than: currentVersion)
        }
    }

    // MARK: - Public

    func checkIfNeeded() {
        let interval = UserDefaults.standard.double(forKey: "updateCheckInterval")
        let checkInterval = interval > 0 ? interval : 7 * 24 * 3600 // Default: weekly

        if let last = lastChecked, Date().timeIntervalSince(last) < checkInterval {
            return
        }

        Task { await checkNow() }
    }

    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: caskURL)
            guard let content = String(data: data, encoding: .utf8) else { return }

            if let match = content.range(of: #"version\s+"([^"]+)""#, options: .regularExpression),
               let capture = content[match].range(of: #""([^"]+)""#, options: .regularExpression) {
                let raw = content[capture]
                let version = String(raw.dropFirst().dropLast()) // Strip quotes

                latestVersion = version
                updateAvailable = isNewer(version, than: currentVersion)
                lastChecked = Date()

                UserDefaults.standard.set(version, forKey: "updateLatestVersion")
                logger.info("Update check complete: latest=\(version, privacy: .public) current=\(self.currentVersion, privacy: .public)")
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Version Comparison

    /// Returns true if `remote` is strictly newer than `local`.
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)

        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
