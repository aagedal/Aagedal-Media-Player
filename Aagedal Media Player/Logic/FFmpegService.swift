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
    case loudnessNoSamples
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
        case .loudnessNoSamples:
            return "No audio samples were found in the selected stream and interval. Choose a range containing audio or measure the whole file."
        case .invalidAudioStream:
            return "Choose a valid audio stream for loudness analysis"
        case .cancelled:
            return "ffmpeg operation was cancelled"
        }
    }
}

enum FFmpegService {
    nonisolated static var ffmpegPath: String? {
        Bundle.main.path(forResource: "ffmpeg", ofType: nil)
    }

    static func run(arguments: [String]) async throws {
        try await run(arguments: arguments, duration: nil, onProgress: nil)
    }

    /// Run ffmpeg while consuming its standard output incrementally. The output
    /// is not retained by the subprocess service, keeping memory bounded for
    /// binary streams such as decoded PCM.
    nonisolated static func runStreamingOutput(
        arguments: [String],
        handle: SubprocessHandle? = nil,
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
                handle: handle,
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

    enum LoudnessWeightingCorrection: String, Sendable, Codable {
        case bs1770Conventional7Point1RearChannels
    }

    struct LUFSResult: Sendable, Codable {
        let integratedLoudness: Double
        let loudnessRange: Double
        let truePeak: Double
        var analysisRange: LoudnessRange? = nil
        // Optional so previously exported results decode as uncorrected.
        var weightingCorrection: LoudnessWeightingCorrection? = nil
    }

    /// Run the EBU R128 loudness analysis on a specific audio stream.
    /// `audioStreamIndex` is the zero-based index among audio streams (used with `-map 0:a:<index>`).
    static func analyzeLUFS(
        url: URL, audioStreamIndex: Int, range: LoudnessRange? = nil,
        channels: Int? = nil, channelLayout: String? = nil
    ) async throws -> LUFSResult {
        let arguments = try loudnessArguments(
            url: url, audioStreamIndex: audioStreamIndex, range: range,
            channels: channels, channelLayout: channelLayout,
            inputAudioArguments: RIFXAudioDecoding.ffmpegInputArguments(for: url)
        )
        var parsed = try await analyzeLoudness(arguments: arguments, range: range)
        if usesConventional7Point1LoudnessCorrection(channels: channels, channelLayout: channelLayout) {
            parsed.weightingCorrection = .bs1770Conventional7Point1RearChannels
        }
        return parsed
    }

    /// Measure a programme assembled from explicitly assigned mono tracks.
    /// Missing time in an assigned channel is silence on the file timeline.
    static func analyzeProgrammeLUFS(
        url: URL, mapping: ProgrammeLoudnessMapping,
        audioStreams: [MediaMetadata.AudioStream], duration: Double?,
        range: LoudnessRange? = nil
    ) async throws -> ProgrammeLoudnessResult {
        let arguments = try programmeLoudnessArguments(
            url: url, mapping: mapping, audioStreams: audioStreams, duration: duration,
            range: range, inputAudioArguments: RIFXAudioDecoding.ffmpegInputArguments(for: url)
        )
        return ProgrammeLoudnessResult(
            mapping: mapping, loudness: try await analyzeLoudness(arguments: arguments, range: range)
        )
    }

    nonisolated static func programmeLoudnessArguments(
        url: URL, mapping: ProgrammeLoudnessMapping,
        audioStreams: [MediaMetadata.AudioStream], duration: Double?,
        range: LoudnessRange? = nil, inputAudioArguments: [String] = []
    ) throws -> [String] {
        try mapping.validate(audioStreams: audioStreams)
        guard let duration, duration.isFinite, duration > 0,
              duration < Double(Int64.max) / 1_000_000 else {
            throw ProgrammeLoudnessError.durationRequired
        }
        if let range {
            _ = try LoudnessRange(start: range.start, end: range.end)
            guard range.start < duration, range.end <= duration else {
                throw FFmpegError.invalidLoudnessRange
            }
        }
        let end = range?.end ?? duration
        let start = range?.start ?? 0
        // Retain the highest source rate rather than silently reducing the
        // bandwidth of high-rate channels before true-peak measurement.
        let sampleRate = mapping.audioStreamIndices.compactMap { audioStreams[$0].sampleRate }.max()!
        var chains = mapping.audioStreamIndices.enumerated().map { channel, stream in
            // first_pts pads initial delay; async=1 fills/trims timestamp gaps
            // without stretching. Never reset individual stream PTS before this.
            // Finite padding prevents join ending at the shortest source, and
            // equal trims bound every input and preserve file-relative ranges.
            // https://ffmpeg.org/ffmpeg-resampler.html (async, first_pts)
            // https://ffmpeg.org/ffmpeg-filters.html (apad, atrim, join)
            "[\(channel):a:\(stream)]aresample=\(sampleRate):async=1:first_pts=0," +
            "apad=whole_dur=\(end),atrim=start=\(start):end=\(end)," +
            "asetpts=PTS-STARTPTS[programme\(channel)]"
        }
        let inputs = mapping.audioStreamIndices.indices.map { "[programme\($0)]" }.joined()
        let roles = mapping.layout.channelRoles.enumerated().map { "\($0.offset).0-\($0.element)" }.joined(separator: "|")
        chains.append(inputs + "join=inputs=\(mapping.audioStreamIndices.count):" +
                      "channel_layout=\(mapping.layout.ffmpegLayout):map=\(roles),ebur128=peak=true[programme]")
        // Give each selected track an independent demuxer. With one shared
        // input, advancing one branch can retain other tracks' compressed
        // packets for much of a long file. Separate inputs preserve the same
        // source timeline while allowing unused tracks to be discarded.
        // The shared-input graph also lost all but its first channel in the
        // final 30 seconds of an eight-hour split-mono ALAC regression file.
        // This remains one cancellable process; container indexes still take
        // memory proportional to the source's packet count.
        let inputsArguments = mapping.audioStreamIndices.flatMap { _ in
            ["-t", String(end)] + inputAudioArguments + ["-i", url.path]
        }
        return ["-hide_banner", "-nostats", "-progress", "pipe:1"] + inputsArguments +
            ["-filter_complex", chains.joined(separator: ";"), "-map", "[programme]", "-f", "null", "-"]
    }

    private static func analyzeLoudness(arguments: [String], range: LoudnessRange?) async throws -> LUFSResult {
        guard let path = ffmpegPath else { throw FFmpegError.ffmpegMissing }
        let result: SubprocessResult
        do {
            result = try await SubprocessService.run(
                executableURL: URL(fileURLWithPath: path), arguments: arguments
            )
        } catch is CancellationError {
            throw FFmpegError.cancelled
        }
        let output = String(data: result.standardError, encoding: .utf8) ?? ""
        guard result.terminationStatus == 0 else {
            throw FFmpegError.processFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // A successful empty ebur128 graph still reports a plausible summary.
        // Require output samples; genuine digital silence advances this clock.
        let progress = String(data: result.standardOutput, encoding: .utf8) ?? ""
        let hasSamples = progress.split(whereSeparator: \.isNewline).contains { line in
            guard line.hasPrefix("out_time_us="),
                  let microseconds = Double(line.dropFirst("out_time_us=".count)) else { return false }
            return microseconds.isFinite && microseconds > 0
        }
        guard hasSamples else { throw FFmpegError.loudnessNoSamples }
        guard var parsed = parseLUFSOutput(output) else {
            throw FFmpegError.processFailed("Could not parse LUFS output")
        }
        parsed.analysisRange = range
        return parsed
    }

    nonisolated static func usesConventional7Point1LoudnessCorrection(
        channels: Int?, channelLayout: String?
    ) -> Bool {
        channels == 8 && channelLayout?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "7.1"
    }

    /// Trim decoded samples before the loudness filter so its summary describes
    /// only the selected interval, including non-keyframe boundaries.
    nonisolated static func loudnessArguments(
        url: URL, audioStreamIndex: Int, range: LoudnessRange? = nil,
        channels: Int? = nil, channelLayout: String? = nil,
        inputAudioArguments: [String] = []
    ) throws -> [String] {
        guard audioStreamIndex >= 0 else { throw FFmpegError.invalidAudioStream }
        var filter = "ebur128=peak=true"
        if usesConventional7Point1LoudnessCorrection(channels: channels, channelLayout: channelLayout) {
            // BS.1770-5 Annex 3 assigns unit weight to conventional 7.1's rear
            // speakers, but this FFmpeg weights BL/BR by 1.41. Relabel only in
            // the analysis graph to select unit weights without scaling samples
            // or changing true peaks. Named mappings require every source speaker.
            // Use channelmap: pan can negotiate an unwanted input rematrix here.
            filter = "channelmap=map=FL-FL|FR-FR|FC-FC|LFE-LFE|BL-FLC|BR-FRC|SL-SL|SR-SR:channel_layout=7.1(wide-side)," + filter
        }
        var inputArguments = ["-hide_banner", "-nostats", "-progress", "pipe:1"]
        if let range {
            // Validate again because Codable can construct a range without its initializer.
            _ = try LoudnessRange(start: range.start, end: range.end)
            inputArguments += ["-t", String(range.end)]
            filter = "atrim=start=\(range.start):end=\(range.end),asetpts=PTS-STARTPTS," + filter
        }
        return inputArguments + inputAudioArguments + [
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
