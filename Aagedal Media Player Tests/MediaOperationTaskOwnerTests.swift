// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MediaOperationTaskOwnerTests: XCTestCase {
    func testWindowCloseCancelsOperationDuringPreparation() async throws {
        let owner = MediaOperationTaskOwner()
        let probe = OperationCancellationProbe()

        let token = owner.start(.screenshot) { _, _ in
            probe.markStarted()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                probe.markCancelled()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertNotNil(token)
        try await waitUntil { probe.started }

        owner.cancelAll()

        try await waitUntil { probe.cancelled }
        XCTAssertFalse(owner.isActive(.screenshot))
    }

    func testWindowCloseCancelsAttachedEncodingProcess() async throws {
        let owner = MediaOperationTaskOwner()
        let probe = OperationCancellationProbe()

        let token = owner.start(.trimExport) { _, handle in
            probe.markStarted()
            do {
                _ = try await SubprocessService.run(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["30"],
                    handle: handle
                )
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                probe.markCancelled()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertNotNil(token)
        try await waitUntil { probe.started }

        owner.cancelAll()

        try await waitUntil { probe.cancelled }
        XCTAssertFalse(owner.isActive(.trimExport))
    }

    func testWindowCloseCancellationIsRememberedBeforeProcessAttachment() async throws {
        let owner = MediaOperationTaskOwner()
        let probe = OperationCancellationProbe()
        let attachmentGate = AsyncGate()

        let token = owner.start(.trimExport) { _, handle in
            probe.markStarted()
            await attachmentGate.wait()
            do {
                _ = try await SubprocessService.run(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["30"],
                    handle: handle
                )
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                probe.markCancelled()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertNotNil(token)
        try await waitUntil { probe.started }

        owner.cancelAll()
        await attachmentGate.open()

        try await waitUntil { probe.cancelled }
        XCTAssertFalse(owner.isActive(.trimExport))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @Sendable () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for operation state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class OperationCancellationProbe: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var didStart = false
    private nonisolated(unsafe) var didCancel = false

    nonisolated var started: Bool {
        lock.withLock { didStart }
    }

    nonisolated var cancelled: Bool {
        lock.withLock { didCancel }
    }

    nonisolated func markStarted() {
        lock.withLock { didStart = true }
    }

    nonisolated func markCancelled() {
        lock.withLock { didCancel = true }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
