// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Owns asynchronous media-operation tasks for one player window.
///
/// Removing an entry before cancelling it invalidates any late completion from
/// that task. The subprocess handle also remembers cancellation requested
/// before ffmpeg has attached its `Process`, closing the preparation/launch
/// race that otherwise lets an encoder outlive its window.
@MainActor
final class MediaOperationTaskOwner {
    enum Kind: Hashable, Sendable {
        case screenshot
        case trimExport
    }

    struct Token: Equatable, Sendable {
        fileprivate let id = UUID()
    }

    private struct Entry {
        let token: Token
        let task: Task<Void, Never>
        let subprocessHandle: SubprocessHandle
    }

    private var entries: [Kind: Entry] = [:]

    @discardableResult
    func start(
        _ kind: Kind,
        operation: @escaping @MainActor @Sendable (Token, SubprocessHandle) async -> Void
    ) -> Token? {
        guard entries[kind] == nil else { return nil }

        let token = Token()
        let subprocessHandle = SubprocessHandle()
        let task = Task { @MainActor [weak self] in
            await operation(token, subprocessHandle)
            self?.finish(kind, token: token)
        }
        entries[kind] = Entry(
            token: token,
            task: task,
            subprocessHandle: subprocessHandle
        )
        return token
    }

    func isCurrent(_ kind: Kind, token: Token) -> Bool {
        entries[kind]?.token == token
    }

    /// Requests cancellation while keeping the token current so the operation
    /// can publish its user-visible cancelled result before the entry finishes.
    func requestCancellation(_ kind: Kind) {
        guard let entry = entries[kind] else { return }
        entry.task.cancel()
        entry.subprocessHandle.cancel()
    }

    func cancelAll() {
        let activeEntries = Array(entries.values)
        entries.removeAll()
        for entry in activeEntries {
            entry.task.cancel()
            entry.subprocessHandle.cancel()
        }
    }

    func isActive(_ kind: Kind) -> Bool {
        entries[kind] != nil
    }

    private func finish(_ kind: Kind, token: Token) {
        guard entries[kind]?.token == token else { return }
        entries.removeValue(forKey: kind)
    }
}
