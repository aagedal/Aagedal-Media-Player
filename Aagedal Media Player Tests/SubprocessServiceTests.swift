// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class SubprocessServiceTests: XCTestCase {
    func testDrainsBothStreamsAndKeepsBoundedTails() async throws {
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '1234567890'; printf 'abcdefghij' >&2"],
            outputLimit: 6
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), "567890")
        XCTAssertEqual(String(decoding: result.standardError, as: UTF8.self), "efghij")
    }

    func testReassemblesLinesSplitAcrossPipeReads() async throws {
        let received = LineRecorder()
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'out_time_'; sleep 0.05; printf 'us=500000\\nprogress=end\\n'"],
            onStandardOutputLine: { received.append($0) }
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(received.lines, ["out_time_us=500000", "progress=end"])
    }

    func testReassemblesStandardErrorLinesSplitAcrossPipeReads() async throws {
        let received = LineRecorder()
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'packet_ts' >&2; sleep 0.05; printf '=48000\\nend\\n' >&2"],
            onStandardErrorLine: { received.append($0) }
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(received.lines, ["packet_ts=48000", "end"])
    }

    func testStreamsStandardOutputWithoutRetainingIt() async throws {
        let received = DataRecorder()
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'streamed-pcm'; printf 'diagnostic' >&2"],
            standardOutputLimit: 0,
            onStandardOutputData: { received.append($0) }
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.standardOutput.isEmpty)
        XCTAssertEqual(String(decoding: result.standardError, as: UTF8.self), "diagnostic")
        XCTAssertEqual(String(decoding: received.data, as: UTF8.self), "streamed-pcm")
    }

    func testWaitsForFinalStreamingCallbackBeforeReturning() async throws {
        let received = DataRecorder()
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'final-stream-chunk'"],
            standardOutputLimit: 0,
            onStandardOutputData: { data in
                Thread.sleep(forTimeInterval: 0.1)
                received.append(data)
            }
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(decoding: received.data, as: UTF8.self), "final-stream-chunk")
    }

    func testTerminationDrainsFinalErrorFramingBeforeWaitingForOutputCallback() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("subprocess-cross-pipe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let recorder = CrossPipeRecorder(marker: marker)
        let script = "printf 'pcm'; while [ ! -f '\(marker.path)' ]; do sleep 0.01; done; printf 'frame-record' >&2"

        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            standardOutputLimit: 0,
            onStandardOutputData: { recorder.consumeOutput($0) },
            onStandardErrorLine: { recorder.consumeErrorLine($0) }
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(recorder.output, "pcm")
        XCTAssertEqual(recorder.errorLine, "frame-record")
        XCTAssertTrue(recorder.outputWaitedForErrorLine)
        XCTAssertTrue(recorder.outputWasReleasedByErrorLine)
    }

    func testTaskCancellationTerminatesChildProcess() async throws {
        let task = Task {
            try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"]
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCancellationBeforeAttachmentIsRemembered() async {
        let handle = SubprocessHandle()
        handle.cancel()

        do {
            _ = try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"],
                handle: handle
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuspendAndResumePreserveTheAttachedProcess() async throws {
        let handle = SubprocessHandle()
        let received = LineRecorder()
        let task = Task {
            try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'first\\n'; sleep 0.25; printf 'second\\n'"],
                handle: handle,
                onStandardOutputLine: { received.append($0) }
            )
        }

        for _ in 0..<100 where received.lines.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(received.lines, ["first"])
        handle.suspend()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(received.lines, ["first"])
        handle.resume()

        let result = try await task.value
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(received.lines, ["first", "second"])
    }

    func testSuspendBeforeAttachmentIsRemembered() async throws {
        let handle = SubprocessHandle()
        let received = LineRecorder()
        handle.suspend()
        let task = Task {
            try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'attached\\n'"],
                handle: handle,
                onStandardOutputLine: { received.append($0) }
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(received.lines.isEmpty)
        handle.resume()
        _ = try await task.value
        XCTAssertEqual(received.lines, ["attached"])
    }

    func testCancellationTerminatesSuspendedProcess() async throws {
        let handle = SubprocessHandle()
        let task = Task {
            try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"], handle: handle
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        handle.suspend()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private final class LineRecorder: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storage: [String] = []

    nonisolated func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }

    nonisolated var lines: [String] {
        lock.withLock { storage }
    }
}

private final class DataRecorder: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storage = Data()

    nonisolated func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }

    nonisolated var data: Data {
        lock.withLock { storage }
    }
}

private final class CrossPipeRecorder: Sendable {
    private let condition = NSCondition()
    private let marker: URL
    private nonisolated(unsafe) var outputStorage = ""
    private nonisolated(unsafe) var errorStorage: String?
    private nonisolated(unsafe) var waited = false
    private nonisolated(unsafe) var released = false

    nonisolated init(marker: URL) {
        self.marker = marker
    }

    nonisolated func consumeOutput(_ data: Data) {
        condition.lock()
        outputStorage += String(decoding: data, as: UTF8.self)
        waited = errorStorage == nil
        _ = FileManager.default.createFile(atPath: marker.path, contents: Data())
        let deadline = Date().addingTimeInterval(2)
        while errorStorage == nil, condition.wait(until: deadline) {}
        released = errorStorage != nil
        condition.unlock()
    }

    nonisolated func consumeErrorLine(_ line: String) {
        condition.withLock {
            errorStorage = line
            condition.broadcast()
        }
    }

    nonisolated var output: String { condition.withLock { outputStorage } }
    nonisolated var errorLine: String? { condition.withLock { errorStorage } }
    nonisolated var outputWaitedForErrorLine: Bool { condition.withLock { waited } }
    nonisolated var outputWasReleasedByErrorLine: Bool { condition.withLock { released } }
}
