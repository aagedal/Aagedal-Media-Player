// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Thread-safe cancellation state shared by structured tasks and explicit UI actions.
/// A cancellation requested before the process starts is remembered and applied as
/// soon as the child is attached.
final class SubprocessHandle: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var process: Process?
    private nonisolated(unsafe) var cancelled = false
    private nonisolated(unsafe) var suspended = false

    private let sendSignal: @Sendable (Int32, Int32) -> Void

    /// Synchronous signal delivery; an injected sender must not reenter this handle.
    nonisolated init(
        sendSignal: @escaping @Sendable (Int32, Int32) -> Void = { pid, signal in
            kill(pid, signal)
        }
    ) {
        self.sendSignal = sendSignal
    }

    nonisolated var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    nonisolated func attach(_ process: Process) {
        lock.withLock {
            guard process.isRunning else { return }
            self.process = process
            if cancelled { signalAttachedProcess(SIGKILL) }
            else if suspended { signalAttachedProcess(SIGSTOP) }
        }
    }

    nonisolated func detach(_ process: Process) {
        lock.withLock {
            if self.process === process {
                self.process = nil
            }
        }
    }

    nonisolated func cancel() {
        lock.withLock {
            cancelled = true
            signalAttachedProcess(SIGKILL)
        }
    }

    /// Suspends an attached decoder without ending its stdout pipe or task.
    /// A request made before process attachment is remembered, matching the
    /// existing cancellation-before-attachment guarantee.
    nonisolated func suspend() {
        lock.withLock {
            guard !cancelled else { return }
            suspended = true
            signalAttachedProcess(SIGSTOP)
        }
    }

    nonisolated func resume() {
        lock.withLock {
            guard !cancelled else { return }
            suspended = false
            signalAttachedProcess(SIGCONT)
        }
    }

    /// Caller holds the state lock through signal delivery. Sending outside
    /// it can reorder STOP/CONT during attachment or rapid transport changes,
    /// leaving a resumed decoder stopped. Detachment uses the same lock so a
    /// queued signal cannot retain an obsolete process after it is detached.
    nonisolated private func signalAttachedProcess(_ signal: Int32) {
        guard let process, process.isRunning else { return }
        sendSignal(process.processIdentifier, signal)
    }
}

struct SubprocessResult: Sendable {
    nonisolated let terminationStatus: Int32
    nonisolated let terminationReason: Process.TerminationReason
    nonisolated let standardOutput: Data
    nonisolated let standardError: Data

    nonisolated init(
        terminationStatus: Int32,
        terminationReason: Process.TerminationReason,
        standardOutput: Data,
        standardError: Data
    ) {
        self.terminationStatus = terminationStatus
        self.terminationReason = terminationReason
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Runs child processes without blocking Swift's cooperative executor.
/// Both output streams are drained continuously and only their bounded tails are retained.
enum SubprocessService {
    nonisolated static func run(
        executableURL: URL,
        arguments: [String],
        outputLimit: Int = 128 * 1024,
        standardOutputLimit: Int? = nil,
        handle suppliedHandle: SubprocessHandle? = nil,
        onStandardOutputData: (@Sendable (Data) -> Void)? = nil,
        onStandardOutputLine: (@Sendable (String) -> Void)? = nil,
        onStandardErrorData: (@Sendable (Data) -> Void)? = nil,
        onStandardErrorLine: (@Sendable (String) -> Void)? = nil,
        onProcessTermination: (@Sendable () -> Void)? = nil,
        onStandardErrorEnd: (@Sendable () -> Void)? = nil
    ) async throws -> SubprocessResult {
        let handle = suppliedHandle ?? SubprocessHandle()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdoutCollector = BoundedDataCollector(limit: standardOutputLimit ?? outputLimit)
                let stderrCollector = BoundedDataCollector(limit: outputLimit)
                let stdoutCallbacks = SubprocessCallbackBarrier()
                let stderrCallbacks = SubprocessCallbackBarrier()
                let completionQueue = DispatchQueue(
                    label: "com.aagedal.MediaPlayer.subprocess-completion",
                    qos: .utility
                )
                let stdoutLines = LineBuffer(
                    onLine: onStandardOutputLine,
                    maximumPendingByteCount: outputLimit
                )
                let stderrLines = LineBuffer(
                    onLine: onStandardErrorLine,
                    maximumPendingByteCount: outputLimit
                )

                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    stdoutCallbacks.perform {
                        autoreleasepool {
                            let data = fileHandle.availableData
                            guard !data.isEmpty else { return }
                            onStandardOutputData?(data)
                            stdoutCollector.append(data)
                            stdoutLines.append(data)
                        }
                    }
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    stderrCallbacks.perform {
                        autoreleasepool {
                            let data = fileHandle.availableData
                            guard !data.isEmpty else { return }
                            onStandardErrorData?(data)
                            stderrCollector.append(data)
                            stderrLines.append(data)
                        }
                    }
                }

                process.terminationHandler = { terminatedProcess in
                    completionQueue.async {
                        handle.detach(process)
                        onProcessTermination?()

                        // A binary stdout consumer may be waiting for a framing
                        // record carried on stderr. Complete and drain that side
                        // channel first so process exit cannot deadlock the final
                        // stdout callback behind undelivered framing metadata.
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        stderrCallbacks.closeAndWait()

                        let stderrTail = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        if !stderrTail.isEmpty {
                            onStandardErrorData?(stderrTail)
                            stderrCollector.append(stderrTail)
                            stderrLines.append(stderrTail)
                        }
                        stderrLines.finish()
                        onStandardErrorEnd?()

                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stdoutCallbacks.closeAndWait()

                        let stdoutTail = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        if !stdoutTail.isEmpty {
                            onStandardOutputData?(stdoutTail)
                            stdoutCollector.append(stdoutTail)
                            stdoutLines.append(stdoutTail)
                        }
                        stdoutLines.finish()

                        if handle.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: SubprocessResult(
                                terminationStatus: terminatedProcess.terminationStatus,
                                terminationReason: terminatedProcess.terminationReason,
                                standardOutput: stdoutCollector.data,
                                standardError: stderrCollector.data
                            ))
                        }
                    }
                }

                do {
                    try process.run()
                    handle.attach(process)
                } catch {
                    process.terminationHandler = nil
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

/// Prevents process termination from completing while an admitted pipe callback
/// is still delivering bytes. Without this barrier, a fast child exit can race
/// the final readability callback and let callers finish a stream prematurely.
private final class SubprocessCallbackBarrier: Sendable {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private nonisolated(unsafe) var isClosed = false

    nonisolated func perform(_ body: () -> Void) {
        let admitted = lock.withLock {
            guard !isClosed else { return false }
            group.enter()
            return true
        }
        guard admitted else { return }
        defer { group.leave() }
        body()
    }

    nonisolated func closeAndWait() {
        lock.withLock { isClosed = true }
        group.wait()
    }
}

private final class BoundedDataCollector: Sendable {
    private let lock = NSLock()
    private let limit: Int
    private nonisolated(unsafe) var storage = Data()

    nonisolated init(limit: Int) {
        self.limit = max(0, limit)
    }

    nonisolated func append(_ data: Data) {
        guard limit > 0, !data.isEmpty else { return }
        lock.withLock {
            if data.count >= limit {
                storage = Data(data.suffix(limit))
                return
            }
            let overflow = storage.count + data.count - limit
            if overflow > 0 {
                storage.removeFirst(overflow)
            }
            storage.append(data)
        }
    }

    nonisolated var data: Data {
        lock.withLock { storage }
    }
}

/// Converts arbitrary byte chunks into complete UTF-8 lines. Incomplete trailing
/// bytes are retained until the next chunk so split ffmpeg progress records survive.
private final class LineBuffer: Sendable {
    private let lock = NSLock()
    private let onLine: (@Sendable (String) -> Void)?
    private let maximumPendingByteCount: Int
    private nonisolated(unsafe) var pending = Data()

    nonisolated init(onLine: (@Sendable (String) -> Void)?, maximumPendingByteCount: Int) {
        self.onLine = onLine
        self.maximumPendingByteCount = max(0, maximumPendingByteCount)
    }

    nonisolated func append(_ data: Data) {
        guard onLine != nil, !data.isEmpty else { return }
        lock.withLock {
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                deliver(Data(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
            if pending.count > maximumPendingByteCount {
                pending = Data(pending.suffix(maximumPendingByteCount))
            }
        }
    }

    nonisolated func finish() {
        guard onLine != nil else { return }
        lock.withLock {
            defer { pending.removeAll(keepingCapacity: false) }
            if !pending.isEmpty {
                deliver(pending)
            }
        }
    }

    nonisolated private func deliver(_ data: Data) {
        var line = String(decoding: data, as: UTF8.self)
        if line.last == "\r" { line.removeLast() }
        onLine?(line)
    }
}
