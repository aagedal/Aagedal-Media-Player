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
