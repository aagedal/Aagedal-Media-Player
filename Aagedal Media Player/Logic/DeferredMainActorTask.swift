// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Owns work that must be deferred until the next main-actor scheduling turn.
/// Cancellation and replacement invalidate the queued closure before it can
/// start, which is useful for UI work whose owner may close immediately.
@MainActor
final class DeferredMainActorTask {
    private var generations = OperationGeneration()
    private var task: Task<Void, Never>?

    @discardableResult
    func schedule(
        _ operation: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never> {
        schedule(waitUntilReady: {
            await Task.yield()
        }) {
            operation()
        }
    }

    @discardableResult
    func schedule(
        after delay: Duration,
        _ operation: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never> {
        schedule(waitUntilReady: {
            try await Task.sleep(for: delay)
        }) {
            operation()
        }
    }

    @discardableResult
    func scheduleAsync(
        after delay: Duration,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        schedule(waitUntilReady: {
            try await Task.sleep(for: delay)
        }, operation: operation)
    }

    private func schedule(
        waitUntilReady: @escaping @Sendable () async throws -> Void,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        cancel()
        let generation = generations.advance()

        let scheduledTask = Task { @MainActor [weak self] in
            do {
                try await waitUntilReady()
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  generations.isCurrent(generation) else { return }

            await operation()

            if generations.isCurrent(generation) {
                task = nil
            }
        }
        task = scheduledTask
        return scheduledTask
    }

    func cancel() {
        generations.advance()
        task?.cancel()
        task = nil
    }
}
