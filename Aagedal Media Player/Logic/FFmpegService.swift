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
    case invalidLoudnessRange
    case invalidAudioStream

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "ffmpeg binary not found in app bundle"
        case .processFailed(let message):
            return "ffmpeg failed: \(message)"
        case .outputMissing:
            return "ffmpeg produced no output file"
        case .invalidLoudnessRange:
            return "Choose a finite, non-negative In point and a later Out point for loudness analysis"
        case .invalidAudioStream:
            return "Choose a valid audio stream for loudness analysis"
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

    /// Run ffmpeg while consuming its standard output incrementally. The output
    /// is not retained by the subprocess service, keeping memory bounded for
    /// binary streams such as decoded PCM.
    static func runStreamingOutput(
        arguments: [String],
        onStandardOutputData: @escaping @Sendable (Data) -> Void
    ) async throws {
        guard let path = ffmpegPath else {
            throw FFmpegError.ffmpegMissing
        }

        let result: SubprocessResult
        do {
            result = try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: path),
                arguments: arguments,
                standardOutputLimit: 0,
                onStandardOutputData: onStandardOutputData
            )
        } catch is CancellationError {
            throw FFmpegError.cancelled
        }

        guard result.terminationStatus == 0 else {
            let message = String(data: result.standardError, encoding: .utf8) ?? "Unknown ffmpeg error"
            throw FFmpegError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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

    struct LoudnessRange: Sendable, Codable, Equatable {
        let start: Double
        let end: Double

        nonisolated init(start: Double, end: Double) throws {
            guard start.isFinite, end.isFinite, start >= 0, end > start else {
                throw FFmpegError.invalidLoudnessRange
            }
            self.start = start
            self.end = end
        }
    }

    struct LUFSResult: Sendable, Codable {
        let integratedLoudness: Double
        let loudnessRange: Double
        let truePeak: Double
        var analysisRange: LoudnessRange? = nil
    }

    /// Run the EBU R128 loudness analysis on a specific audio stream.
    /// `audioStreamIndex` is the zero-based index among audio streams (used with `-map 0:a:<index>`).
    static func analyzeLUFS(url: URL, audioStreamIndex: Int, range: LoudnessRange? = nil) async throws -> LUFSResult {
        let arguments = try loudnessArguments(url: url, audioStreamIndex: audioStreamIndex, range: range)
        guard let path = ffmpegPath else {
            throw FFmpegError.ffmpegMissing
        }

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
        guard var parsed = parseLUFSOutput(output) else {
            throw FFmpegError.processFailed("Could not parse LUFS output")
        }
        parsed.analysisRange = range
        return parsed
    }

    /// Trim decoded samples before the loudness filter so its summary describes
    /// only the selected interval, including non-keyframe boundaries.
    nonisolated static func loudnessArguments(
        url: URL, audioStreamIndex: Int, range: LoudnessRange? = nil
    ) throws -> [String] {
        guard audioStreamIndex >= 0 else { throw FFmpegError.invalidAudioStream }
        var filter = "ebur128=peak=true"
        var inputArguments = ["-hide_banner", "-nostats"]
        if let range {
            // Validate again because Codable can construct a range without its initializer.
            _ = try LoudnessRange(start: range.start, end: range.end)
            inputArguments += ["-t", String(range.end)]
            filter = "atrim=start=\(range.start):end=\(range.end),asetpts=PTS-STARTPTS," + filter
        }
        return inputArguments + [
            "-i", url.path,
            "-map", "0:a:\(audioStreamIndex)",
            "-af", filter, "-f", "null", "-",
        ]
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

}
