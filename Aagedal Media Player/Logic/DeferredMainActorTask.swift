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
        cancel()
        let generation = generations.advance()

        let scheduledTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  generations.isCurrent(generation) else { return }

            operation()

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
