// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Returns the first of an optional asynchronous value or a deadline without
/// cancelling the underlying operation. This is useful for cache-filling work
/// that should continue after a latency-sensitive caller has moved on.
nonisolated enum AsyncDeadline {
    static func value<Value: Sendable>(
        within timeout: Duration,
        operation: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        let completion = DeadlineCompletion<Value>()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)

                Task.detached(priority: .userInitiated) {
                    completion.resolve(await operation())
                }

                Task.detached {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    completion.resolve(nil)
                }
            }
        } onCancel: {
            completion.resolve(nil)
        }
    }
}

/// Lock-protected, exactly-once continuation storage. Cancellation can arrive
/// before the continuation is installed, so a completed result is retained and
/// delivered as soon as installation occurs.
private final class DeadlineCompletion<Value: Sendable>: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: CheckedContinuation<Value?, Never>?
    private nonisolated(unsafe) var result: Value?
    private nonisolated(unsafe) var isResolved = false

    nonisolated func install(_ continuation: CheckedContinuation<Value?, Never>) {
        let resolvedResult: (Bool, Value?) = lock.withLock {
            if isResolved {
                return (true, result)
            }
            self.continuation = continuation
            return (false, nil)
        }

        if resolvedResult.0 {
            continuation.resume(returning: resolvedResult.1)
        }
    }

    nonisolated func resolve(_ result: Value?) {
        let continuationToResume: CheckedContinuation<Value?, Never>? = lock.withLock {
            guard !isResolved else { return nil }
            isResolved = true
            self.result = result
            defer { continuation = nil }
            return continuation
        }
        continuationToResume?.resume(returning: result)
    }
}
