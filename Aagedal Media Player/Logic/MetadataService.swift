// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Metadata extraction service using FFprobe.
// Locates FFprobe from Aagedal Media Converter app bundle or system path.

import Foundation
import OSLog

enum MetadataError: Error {
    case ffprobeMissing
    case processFailed(String)
    case decodingFailed(String)
    case timeout
}

actor MetadataService {
    static let shared = MetadataService()

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "MetadataService")
    private let cache = NSCache<NSURL, CachedMetadata>()

    private final class CachedMetadata: NSObject {
        let metadata: MediaMetadata
        init(metadata: MediaMetadata) {
            self.metadata = metadata
        }
    }

    /// Locate FFprobe binary
    private func findFFprobe() -> String? {
        // 1. Check Aagedal Media Converter in ~/Applications
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Aagedal Media Converter.app/Contents/Resources/ffprobe")
        if FileManager.default.isExecutableFile(atPath: homeApps.path) {
            return homeApps.path
        }

        // 2. Check /Applications
        let systemApps = "/Applications/Aagedal Media Converter.app/Contents/Resources/ffprobe"
        if FileManager.default.isExecutableFile(atPath: systemApps) {
            return systemApps
        }

        // 3. Check /usr/local/bin
        let usrLocal = "/usr/local/bin/ffprobe"
        if FileManager.default.isExecutableFile(atPath: usrLocal) {
            return usrLocal
        }

        // 4. Check /opt/homebrew/bin
        let homebrew = "/opt/homebrew/bin/ffprobe"
        if FileManager.default.isExecutableFile(atPath: homebrew) {
            return homebrew
        }

        // 5. Try `which ffprobe`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffprobe"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}

        return nil
    }

    func metadata(for url: URL) async throws -> MediaMetadata {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.metadata
        }

        guard let ffprobePath = findFFprobe() else {
            throw MetadataError.ffprobeMissing
        }

        let formatResponse = try await fetchFFprobeResponse(
            url: url,
            ffprobePath: ffprobePath,
            arguments: ["-v", "error", "-show_format", "-of", "json"]
        )

        let videoResponse = try await fetchFFprobeResponse(
            url: url,
            ffprobePath: ffprobePath,
            arguments: ["-v", "error", "-select_streams", "v", "-show_streams", "-of", "json"],
            allowNoStreams: true
        )

        let audioResponse = try await fetchFFprobeResponse(
            url: url,
            ffprobePath: ffprobePath,
            arguments: ["-v", "error", "-select_streams", "a", "-show_streams", "-of", "json"],
            allowNoStreams: true
        )

        let subtitleResponse = try await fetchFFprobeResponse(
            url: url,
            ffprobePath: ffprobePath,
            arguments: ["-v", "error", "-select_streams", "s", "-show_streams", "-of", "json"],
            allowNoStreams: true
        )

        let metadata = try buildMetadata(
            format: formatResponse.format,
            videoStreams: videoResponse.streams,
            audioStreams: audioResponse.streams,
            subtitleStreams: subtitleResponse.streams
        )
        cache.setObject(CachedMetadata(metadata: metadata), forKey: url as NSURL)
        return metadata
    }

    private func runFFprobeJSON(url: URL, ffprobePath: String, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffprobePath)
                var args = arguments
                args.append(url.path)
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timeoutSeconds: TimeInterval = 10
                let checkInterval: TimeInterval = 0.5
                var elapsed: TimeInterval = 0

                while process.isRunning && elapsed < timeoutSeconds {
                    try? await Task.sleep(for: .seconds(checkInterval))
                    elapsed += checkInterval
                }

                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(for: .seconds(0.1))
                    if process.isRunning {
                        process.interrupt()
                    }
                    continuation.resume(throwing: MetadataError.timeout)
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdoutData)
                } else {
                    let message = String(data: stderrData, encoding: .utf8) ?? "Unknown ffprobe error"
                    continuation.resume(throwing: MetadataError.processFailed(message))
                }
            }
        }
    }

    private func fetchFFprobeResponse(url: URL, ffprobePath: String, arguments: [String], allowNoStreams: Bool = false) async throws -> FFprobeResponse {
        do {
            let data = try await runFFprobeJSON(url: url, ffprobePath: ffprobePath, arguments: arguments)
            return try decodeFFprobeResponse(jsonData: data)
        } catch MetadataError.processFailed(let message) {
            if allowNoStreams, message.contains("Stream specifier") {
                return FFprobeResponse(format: nil, streams: [])
            }
            throw MetadataError.processFailed(message)
        }
    }

    private func decodeFFprobeResponse(jsonData: Data) throws -> FFprobeResponse {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(FFprobeResponse.self, from: jsonData)
        } catch {
            let message = String(data: jsonData, encoding: .utf8) ?? "<non-UTF8>"
            logger.error("Failed to decode ffprobe JSON: \(message)")
            throw MetadataError.decodingFailed(error.localizedDescription)
        }
    }

    private func buildMetadata(format: FFprobeResponse.Format?, videoStreams: [FFprobeResponse.Stream], audioStreams: [FFprobeResponse.Stream], subtitleStreams: [FFprobeResponse.Stream]) throws -> MediaMetadata {
        let filteredVideoStreams = videoStreams.filter { stream in
            stream.codecType == "video" && stream.disposition?.attachedPic != 1
        }
        let primaryVideoStream = filteredVideoStreams.first

        let filteredAudioStreams = audioStreams.filter { $0.codecType == "audio" }

        let timecode = format?.tags?.timecode ?? primaryVideoStream?.tags?.timecode

        let frameCount: Int? = {
            if let nbFrames = primaryVideoStream?.nbFrames, let count = Int(nbFrames) {
                return count
            }
            if let durationStr = format?.duration,
               let duration = Double(durationStr),
               let frameRateStr = primaryVideoStream?.avgFrameRate ?? primaryVideoStream?.rFrameRate,
               let frameRate = MediaMetadata.FrameRate(frameRateString: frameRateStr),
               let fps = frameRate.value,
               fps > 0 {
                return Int(round(duration * fps))
            }
            return nil
        }()

        let video = filteredVideoStreams.map { stream -> MediaMetadata.VideoStream in
            let frameRateString = stream.avgFrameRate ?? stream.rFrameRate
            let hasAlpha = stream.pixFmt.map { hasAlphaChannel(pixelFormat: $0) } ?? false
            let bitDepth: Int? = stream.bitsPerRawSample.flatMap { Int($0) }
                ?? stream.pixFmt.flatMap { bitDepthFromPixelFormat($0) }
            let chromaSubsampling = stream.pixFmt.flatMap { chromaSubsamplingFromPixelFormat($0) }
            return MediaMetadata.VideoStream(
                codec: stream.codecName,
                codecLongName: stream.codecLongName,
                profile: stream.profile,
                width: stream.width,
                height: stream.height,
                pixelFormat: stream.pixFmt,
                hasAlpha: hasAlpha,
                pixelAspectRatio: stream.sampleAspectRatio.flatMap(MediaMetadata.Ratio.init(ratioString:)),
                displayAspectRatio: stream.displayAspectRatio.flatMap(MediaMetadata.Ratio.init(ratioString:)),
                frameRate: frameRateString.flatMap(MediaMetadata.FrameRate.init(frameRateString:)),
                bitDepth: bitDepth,
                chromaSubsampling: chromaSubsampling,
                colorPrimaries: stream.colorPrimaries,
                colorTransfer: stream.colorTransfer,
                colorSpace: stream.colorSpace,
                colorRange: stream.colorRange,
                chromaLocation: stream.chromaLocation,
                fieldOrder: stream.fieldOrder,
                isInterlaced: stream.fieldOrder.map {
                    let value = $0.lowercased()
                    return value != "progressive" && value != "unknown"
                }
            )
        }

        let audio = filteredAudioStreams.map { stream -> MediaMetadata.AudioStream in
            MediaMetadata.AudioStream(
                index: stream.index,
                languageCode: stream.tags?.language?.lowercased(),
                title: stream.tags?.title,
                codec: stream.codecName,
                codecLongName: stream.codecLongName,
                profile: stream.profile,
                sampleRate: stream.sampleRate.flatMap { Int($0) },
                channels: stream.channels,
                channelLayout: stream.channelLayout,
                bitDepth: stream.bitsPerRawSample.flatMap { Int($0) },
                bitRate: stream.bitRate.flatMap { Int64($0) },
                isDefault: (stream.disposition?.defaultStream == 1)
            )
        }

        let filteredSubtitleStreams = subtitleStreams.filter { $0.codecType == "subtitle" }

        let subtitles = filteredSubtitleStreams.map { stream -> MediaMetadata.SubtitleStream in
            MediaMetadata.SubtitleStream(
                index: stream.index,
                languageCode: stream.tags?.language?.lowercased(),
                title: stream.tags?.title,
                codec: stream.codecName,
                codecLongName: stream.codecLongName,
                isDefault: (stream.disposition?.defaultStream == 1),
                isForced: (stream.disposition?.forced == 1)
            )
        }

        return MediaMetadata(
            duration: format?.duration.flatMap { Double($0) },
            formatName: format?.formatName,
            containerLongName: format?.formatLongName,
            sizeBytes: format?.size.flatMap { Int64($0) },
            bitRate: format?.bitRate.flatMap { Int64($0) },
            timecode: timecode,
            frameCount: frameCount,
            videoStreams: video,
            audioStreams: audio,
            subtitleStreams: subtitles
        )
    }
}

// MARK: - Pixel Format Helpers

private func bitDepthFromPixelFormat(_ pixelFormat: String) -> Int? {
    let format = pixelFormat.lowercased()
    let patterns = [
        #"(\d{1,2})(le|be)?$"#,
        #"p(\d{1,2})(le|be)?$"#,
    ]
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: format, options: [], range: NSRange(format.startIndex..., in: format)) {
            let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            if let range = Range(captureRange, in: format),
               let bitDepth = Int(format[range]),
               bitDepth >= 8 && bitDepth <= 16 {
                return bitDepth
            }
        }
    }
    if format.contains("24") || format.contains("32") { return 8 }
    if format.contains("48") || format.contains("64") { return 16 }
    let eightBitPatterns = ["yuv420p", "yuv422p", "yuv444p", "yuvj420p", "yuvj422p", "yuvj444p", "nv12", "nv21"]
    for pattern in eightBitPatterns {
        if format == pattern { return 8 }
    }
    return nil
}

private func chromaSubsamplingFromPixelFormat(_ pixelFormat: String) -> String? {
    let format = pixelFormat.lowercased()
    if format.contains("420") || format.contains("nv12") || format.contains("nv21") { return "4:2:0" }
    if format.contains("422") || format.contains("yuyv") || format.contains("uyvy") { return "4:2:2" }
    if format.contains("444") { return "4:4:4" }
    if format.contains("411") { return "4:1:1" }
    if format.contains("410") { return "4:1:0" }
    if format.hasPrefix("rgb") || format.hasPrefix("bgr") || format.hasPrefix("argb") ||
       format.hasPrefix("abgr") || format.hasPrefix("rgba") || format.hasPrefix("bgra") ||
       format.hasPrefix("gbr") { return "4:4:4" }
    if format.hasPrefix("gray") || format.hasPrefix("mono") || format == "y" { return nil }
    return nil
}

private func hasAlphaChannel(pixelFormat: String) -> Bool {
    let format = pixelFormat.lowercased()
    if format.contains("4444") { return true }
    if format.contains("rgba") || format.contains("bgra") ||
       format.contains("argb") || format.contains("abgr") { return true }
    if format.hasPrefix("yuva") { return true }
    if format.hasPrefix("gbrap") { return true }
    if format.contains("alpha") { return true }
    return false
}

// MARK: - FFprobe Response Types

private struct FFprobeResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case format
        case streams
    }

    let format: Format?
    let streams: [Stream]

    init(format: Format?, streams: [Stream]) {
        self.format = format
        self.streams = streams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.format = try container.decodeIfPresent(Format.self, forKey: .format)
        self.streams = try container.decodeIfPresent([Stream].self, forKey: .streams) ?? []
    }

    struct Format: Decodable {
        let duration: String?
        let formatName: String?
        let formatLongName: String?
        let size: String?
        let bitRate: String?
        let tags: Tags?
    }

    struct Stream: Decodable {
        let index: Int?
        let codecName: String?
        let codecLongName: String?
        let profile: String?
        let codecType: String?
        let width: Int?
        let height: Int?
        let pixFmt: String?
        let sampleAspectRatio: String?
        let displayAspectRatio: String?
        let avgFrameRate: String?
        let rFrameRate: String?
        let bitRate: String?
        let bitsPerRawSample: String?
        let sampleRate: String?
        let channels: Int?
        let channelLayout: String?
        let colorPrimaries: String?
        let colorTransfer: String?
        let colorSpace: String?
        let colorRange: String?
        let chromaLocation: String?
        let fieldOrder: String?
        let nbFrames: String?
        let disposition: Disposition?
        let tags: Tags?

        struct Disposition: Decodable {
            let defaultStream: Int?
            let attachedPic: Int?
            let forced: Int?
        }
    }

    struct Tags: Decodable {
        let language: String?
        let title: String?
        let timecode: String?
    }
}
