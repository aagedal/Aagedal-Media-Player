// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lightweight service to locate and run the bundled ffmpeg binary.

import Foundation

enum FFmpegError: Error, LocalizedError, Equatable {
    case ffmpegMissing
    case processFailed(String)
    case outputMissing
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "ffmpeg binary not found in app bundle"
        case .processFailed(let message):
            return "ffmpeg failed: \(message)"
        case .outputMissing:
            return "ffmpeg produced no output file"
        case .cancelled:
            return "ffmpeg operation was cancelled"
        }
    }
}

/// Handle for cancelling a running ffmpeg process.
/// Uses manual locking for thread safety — not bound to any actor.
final class FFmpegHandle: Sendable {
    private nonisolated(unsafe) var _process: Process?
    private let lock = NSLock()

    nonisolated func attach(_ process: Process) {
        lock.lock()
        _process = process
        lock.unlock()
    }

    nonisolated func cancel() {
        lock.lock()
        let p = _process
        lock.unlock()
        if let p, p.isRunning {
            kill(p.processIdentifier, SIGKILL)
        }
    }
}

enum FFmpegService {
    static var ffmpegPath: String? {
        Bundle.main.path(forResource: "ffmpeg", ofType: nil)
    }

    static func run(arguments: [String]) async throws {
        try await run(arguments: arguments, duration: nil, onProgress: nil)
    }

    /// Run ffmpeg with progress reporting and optional cancellation.
    /// When `duration` is provided, `-progress pipe:1` is injected and `onProgress` is called
    /// with a fraction 0...1 as ffmpeg writes progress updates to stdout.
    /// Pass an `FFmpegHandle` to enable cancellation.
    static func run(arguments: [String], duration: Double?, onProgress: (@Sendable (Double) -> Void)?, handle: FFmpegHandle? = nil) async throws {
        guard let path = ffmpegPath else {
            throw FFmpegError.ffmpegMissing
        }

        let wantProgress = duration != nil && duration! > 0 && onProgress != nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)

                var args = arguments
                if wantProgress {
                    // Insert -progress pipe:1 right after -hide_banner (or at the start)
                    if let idx = args.firstIndex(of: "-hide_banner") {
                        args.insert(contentsOf: ["-progress", "pipe:1"], at: idx + 1)
                    } else {
                        args.insert(contentsOf: ["-progress", "pipe:1"], at: 0)
                    }
                }
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                if wantProgress, let totalDuration = duration, let progressCallback = onProgress {
                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

                        // Parse lines like "out_time_us=12345678"
                        for line in text.components(separatedBy: .newlines) {
                            if line.hasPrefix("out_time_us=") {
                                let valueStr = line.dropFirst("out_time_us=".count)
                                if let us = Double(valueStr), us > 0 {
                                    let seconds = us / 1_000_000.0
                                    let fraction = min(seconds / totalDuration, 1.0)
                                    progressCallback(fraction)
                                }
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    handle?.attach(process)
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: FFmpegError.cancelled)
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: stderrData, encoding: .utf8) ?? "Unknown ffmpeg error"
                    continuation.resume(throwing: FFmpegError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }

    // MARK: - LUFS Analysis

    struct LUFSResult: Sendable {
        let integratedLoudness: Double
        let loudnessRange: Double
        let truePeak: Double
    }

    /// Run the EBU R128 loudness analysis on a specific audio stream.
    /// `audioStreamIndex` is the zero-based index among audio streams (used with `-map 0:a:<index>`).
    static func analyzeLUFS(url: URL, audioStreamIndex: Int) async throws -> LUFSResult {
        guard let path = ffmpegPath else {
            throw FFmpegError.ffmpegMissing
        }

        let arguments = [
            "-hide_banner", "-nostats",
            "-i", url.path,
            "-map", "0:a:\(audioStreamIndex)",
            "-af", "ebur128=peak=true",
            "-f", "null", "-",
        ]

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LUFSResult, Error>) in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let stderrPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = stderrPipe

                // Collect stderr asynchronously to prevent pipe buffer deadlock.
                // ebur128 outputs per-frame data that can fill the 64 KB buffer.
                let collector = StderrCollector()
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    collector.append(data)
                }

                do {
                    try process.run()
                } catch {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // Drain any remaining data
                let remaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty { collector.append(remaining) }
                let output = String(data: collector.combined(), encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: FFmpegError.processFailed(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }

                guard let result = parseLUFSOutput(output) else {
                    continuation.resume(throwing: FFmpegError.processFailed("Could not parse LUFS output"))
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    private final class StderrCollector: Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var chunks: [Data] = []

        nonisolated func append(_ data: Data) {
            lock.lock()
            chunks.append(data)
            lock.unlock()
        }

        nonisolated func combined() -> Data {
            lock.lock()
            let result = chunks.reduce(Data(), +)
            lock.unlock()
            return result
        }
    }

    nonisolated private static func parseLUFSOutput(_ output: String) -> LUFSResult? {
        // Only parse lines after the "Summary:" marker to avoid matching per-frame data.
        //   Integrated loudness:
        //     I:         -14.0 LUFS
        //   Loudness range:
        //     LRA:        7.2 LU
        //   True peak:
        //     Peak:       -0.3 dBFS (or dBTP)
        guard let summaryRange = output.range(of: "Summary:") else { return nil }
        let summary = String(output[summaryRange.upperBound...])

        var integrated: Double?
        var lra: Double?
        var peak: Double?

        for line in summary.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("I:") && trimmed.hasSuffix("LUFS") {
                integrated = parseValue(trimmed, prefix: "I:", suffix: "LUFS")
            } else if trimmed.hasPrefix("LRA:") && trimmed.hasSuffix("LU") {
                lra = parseValue(trimmed, prefix: "LRA:", suffix: "LU")
            } else if trimmed.hasPrefix("Peak:") {
                // True peak may be reported as dBTP or dBFS depending on ffmpeg version
                if trimmed.hasSuffix("dBTP") {
                    peak = parseValue(trimmed, prefix: "Peak:", suffix: "dBTP")
                } else if trimmed.hasSuffix("dBFS") {
                    peak = parseValue(trimmed, prefix: "Peak:", suffix: "dBFS")
                }
            }
        }

        guard let i = integrated, let l = lra, let p = peak else { return nil }
        return LUFSResult(integratedLoudness: i, loudnessRange: l, truePeak: p)
    }

    nonisolated private static func parseValue(_ line: String, prefix: String, suffix: String) -> Double? {
        var s = line
        s = String(s.dropFirst(prefix.count))
        if s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        return Double(s.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Color Argument Helpers

    static func appendColorArguments(from stream: MediaMetadata.VideoStream?, to arguments: inout [String]) {
        guard let stream else { return }

        if !isMissingColorMetadata(stream.colorPrimaries), let normalized = normalizedColorPrimaries(stream.colorPrimaries) {
            arguments += ["-color_primaries", normalized]
        }
        if !isMissingColorMetadata(stream.colorTransfer), let normalized = normalizedColorTransfer(stream.colorTransfer) {
            arguments += ["-color_trc", normalized]
        }
        if !isMissingColorMetadata(stream.colorSpace), let normalized = normalizedColorSpace(stream.colorSpace) {
            arguments += ["-colorspace", normalized]
        }
        if !isMissingColorMetadata(stream.colorRange), let normalized = normalizedColorRange(stream.colorRange) {
            arguments += ["-color_range", normalized]
        }
    }

    private static func normalizedColorPrimaries(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: [
            "bt709", "bt470bg", "smpte170m", "smpte240m", "bt2020", "smpte432", "smpte432-1",
        ], mapping: [
            "bt2020": "bt2020", "bt2020-10": "bt2020", "bt2020-12": "bt2020",
        ])
    }

    private static func normalizedColorTransfer(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: [
            "bt709", "smpte2084", "arib-std-b67", "iec61966-2-4", "bt470bg", "smpte170m", "bt2020-10", "bt2020-12",
        ], mapping: [
            "bt2020-10": "bt2020-10", "bt2020-12": "bt2020-12",
        ])
    }

    private static func normalizedColorSpace(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: [
            "bt709", "smpte170m", "smpte240m", "bt2020nc", "bt2020c", "bt2020ncl",
        ], mapping: [
            "bt2020": "bt2020nc", "bt2020-ncl": "bt2020nc", "bt2020-cl": "bt2020c",
        ])
    }

    private static func normalizedColorRange(_ value: String?) -> String? {
        normalizedColorValue(value, allowed: ["tv", "pc"], mapping: [
            "limited": "tv", "full": "pc",
        ])
    }

    private static func normalizedColorValue(_ value: String?, allowed: [String], mapping: [String: String]) -> String? {
        guard let raw = value?.lowercased() else { return nil }
        if let mapped = mapping[raw] { return mapped }
        if allowed.contains(raw) { return raw }
        return nil
    }

    private static func isMissingColorMetadata(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return true
        }
        let normalized = value.lowercased()
        return normalized == "unknown" || normalized == "unspecified" || normalized == "na"
    }
}
