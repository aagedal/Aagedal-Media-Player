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

/// Tracks independently replaceable asynchronous operations by key. This is
/// useful when several operations may run concurrently, while a replacement
/// for one key must not let the superseded completion publish or clear the
/// newer operation's state.
nonisolated struct KeyedOperationGeneration<Key: Hashable & Sendable>: Sendable {
    private var nextGeneration: UInt64 = 0
    private var currentGenerations: [Key: UInt64] = [:]

    mutating func begin(for key: Key) -> UInt64 {
        nextGeneration &+= 1
        currentGenerations[key] = nextGeneration
        return nextGeneration
    }

    func isCurrent(_ generation: UInt64, for key: Key) -> Bool {
        currentGenerations[key] == generation
    }

    @discardableResult
    mutating func finish(_ generation: UInt64, for key: Key) -> Bool {
        guard isCurrent(generation, for: key) else { return false }
        currentGenerations.removeValue(forKey: key)
        return true
    }

    mutating func invalidate(for key: Key) {
        currentGenerations.removeValue(forKey: key)
    }

    mutating func invalidateAll() {
        currentGenerations.removeAll()
    }
}
