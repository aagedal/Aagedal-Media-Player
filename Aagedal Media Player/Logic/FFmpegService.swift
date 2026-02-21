// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lightweight service to locate and run the bundled ffmpeg binary.

import Foundation

enum FFmpegError: Error, LocalizedError {
    case ffmpegMissing
    case processFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "ffmpeg binary not found in app bundle"
        case .processFailed(let message):
            return "ffmpeg failed: \(message)"
        case .outputMissing:
            return "ffmpeg produced no output file"
        }
    }
}

enum FFmpegService {
    static var ffmpegPath: String? {
        Bundle.main.path(forResource: "ffmpeg", ofType: nil)
    }

    static func run(arguments: [String]) async throws {
        guard let path = ffmpegPath else {
            throw FFmpegError.ffmpegMissing
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = Pipe()
                let stderrPipe = Pipe()
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: stderrData, encoding: .utf8) ?? "Unknown ffmpeg error"
                    continuation.resume(throwing: FFmpegError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
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
