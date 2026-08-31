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
    /// Pass a `SubprocessHandle` to allow explicit cancellation from UI actions.
    /// Cancelling the calling Swift task always cancels the child process as well.
    static func run(arguments: [String], duration: Double?, onProgress: (@Sendable (Double) -> Void)?, handle: SubprocessHandle? = nil) async throws {
        guard let path = ffmpegPath else {
            throw FFmpegError.ffmpegMissing
        }

        let wantProgress = duration != nil && duration! > 0 && onProgress != nil

        var args = arguments
        if wantProgress {
            if let idx = args.firstIndex(of: "-hide_banner") {
                args.insert(contentsOf: ["-progress", "pipe:1"], at: idx + 1)
            } else {
                args.insert(contentsOf: ["-progress", "pipe:1"], at: 0)
            }
        }

        let progressLineHandler: (@Sendable (String) -> Void)?
        if wantProgress, let totalDuration = duration, let progressCallback = onProgress {
            progressLineHandler = { line in
                guard line.hasPrefix("out_time_us="),
                      let microseconds = Double(line.dropFirst("out_time_us=".count)),
                      microseconds >= 0 else { return }
                progressCallback(min(microseconds / 1_000_000.0 / totalDuration, 1.0))
            }
        } else {
            progressLineHandler = nil
        }

        let result: SubprocessResult
        do {
            result = try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: path),
                arguments: args,
                handle: handle,
                onStandardOutputLine: progressLineHandler
            )
        } catch is CancellationError {
            throw FFmpegError.cancelled
        }

        guard result.terminationStatus == 0 else {
            let message = String(data: result.standardError, encoding: .utf8) ?? "Unknown ffmpeg error"
            throw FFmpegError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - LUFS Analysis

    struct LUFSResult: Sendable, Codable {
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

        let result: SubprocessResult
        do {
            result = try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: path),
                arguments: arguments
            )
        } catch is CancellationError {
            throw FFmpegError.cancelled
        }

        let output = String(data: result.standardError, encoding: .utf8) ?? ""
        guard result.terminationStatus == 0 else {
            throw FFmpegError.processFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let parsed = parseLUFSOutput(output) else {
            throw FFmpegError.processFailed("Could not parse LUFS output")
        }
        return parsed
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
