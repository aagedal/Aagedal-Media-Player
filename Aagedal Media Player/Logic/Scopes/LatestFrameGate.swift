// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

/// Scheduling state for a single-flight, latest-value-wins worker.
///
/// At most one generation is active and one newer generation is pending. A
/// further submission replaces the pending generation instead of growing a
/// queue, which keeps scope work bounded when capture runs faster than compute.
nonisolated struct LatestFrameGate: Sendable {
    nonisolated struct Submission: Equatable, Sendable {
        let generation: UInt64
        let startImmediately: Bool
        let supersededFrame: Bool
    }

    nonisolated struct Completion: Equatable, Sendable {
        let shouldPublish: Bool
        let nextGeneration: UInt64?
    }

    private(set) var latestGeneration: UInt64 = 0
    private(set) var activeGeneration: UInt64?
    private(set) var pendingGeneration: UInt64?

    mutating func submit() -> Submission {
        latestGeneration &+= 1
        let generation = latestGeneration

        if activeGeneration == nil {
            activeGeneration = generation
            return Submission(
                generation: generation,
                startImmediately: true,
                supersededFrame: false
            )
        }

        pendingGeneration = generation
        return Submission(
            generation: generation,
            startImmediately: false,
            supersededFrame: true
        )
    }

    mutating func complete(_ generation: UInt64) -> Completion? {
        guard activeGeneration == generation else { return nil }

        let shouldPublish = generation == latestGeneration
        let next = pendingGeneration
        activeGeneration = next
        pendingGeneration = nil

        return Completion(shouldPublish: shouldPublish, nextGeneration: next)
    }

    mutating func reset() {
        // Invalidate completions that may still arrive from cancelled work.
        latestGeneration &+= 1
        activeGeneration = nil
        pendingGeneration = nil
    }
}
