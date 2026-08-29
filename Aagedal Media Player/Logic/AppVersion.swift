// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Pure helpers for normalizing and comparing release version strings.
/// Kept separate from UpdateChecker so version behavior can be tested without
/// constructing update services or making network requests.
enum AppVersion {
    nonisolated static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        normalized(candidate).compare(normalized(current), options: .numeric) == .orderedDescending
    }
}
