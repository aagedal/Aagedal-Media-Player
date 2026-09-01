// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Invalidates results from replaced asynchronous operations without requiring
/// the underlying work to respond to cancellation immediately.
nonisolated struct OperationGeneration: Sendable {
    private(set) var current: UInt64 = 0

    @discardableResult
    mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == current
    }
}
