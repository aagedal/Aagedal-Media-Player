// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Metadata extraction service using SwiftExif.

import Foundation
import OSLog
import SwiftExif

enum MetadataError: Error {
    case readFailed(String)
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

    func metadata(for url: URL) async throws -> MediaMetadata {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.metadata
        }

        let video: VideoMetadata
        do {
            video = try await readVideoMetadata(from: url)
        } catch {
            logger.error("SwiftExif read failed for \(url.path): \(error.localizedDescription)")
            throw MetadataError.readFailed(error.localizedDescription)
        }

        let metadata = MetadataMapper.makeMediaMetadata(from: video)
        cache.setObject(CachedMetadata(metadata: metadata), forKey: url as NSURL)
        return metadata
    }
}

// MARK: - Mapper

private enum MetadataMapper {
    nonisolated static func makeMediaMetadata(from video: VideoMetadata) -> MediaMetadata {
        let videoStreams = video.videoStreams
            .filter { $0.isAttachedPic != true }
            .map(makeVideoStream(from:))

        let audioStreams = video.audioStreams.map(makeAudioStream(from:))
        let subtitleStreams = video.subtitleStreams.map(makeSubtitleStream(from:))

        let frameCount: Int? = {
            if let count = video.videoStreams.first?.frameCount, count > 0 {
                return count
            }
            if let duration = video.duration,
               let stream = video.videoStreams.first,
               let fps = stream.avgFrameRate ?? stream.frameRate ?? stream.rFrameRate,
               fps > 0 {
                return Int((duration * fps).rounded())
            }
            return nil
        }()

        let timecode = video.timecode ?? video.videoStreams.first?.timecode

        return MediaMetadata(
            duration: video.duration,
            formatName: video.format.rawValue,
            containerLongName: video.formatLongName,
            sizeBytes: video.fileSize,
            bitRate: video.bitRate.map { Int64($0) },
            timecode: timecode,
            comment: video.comment,
            encoder: nil,
            frameCount: frameCount,
            videoStreams: videoStreams,
            audioStreams: audioStreams,
            subtitleStreams: subtitleStreams
        )
    }

    nonisolated private static func makeVideoStream(from stream: VideoStream) -> MediaMetadata.VideoStream {
        let pixelAspectRatio: MediaMetadata.Ratio? = stream.pixelAspectRatio.flatMap { par in
            MediaMetadata.Ratio(numerator: par.0, denominator: par.1)
        }

        let displayAspectRatio: MediaMetadata.Ratio? = {
            if let w = stream.displayWidth, let h = stream.displayHeight, h > 0 {
                return MediaMetadata.Ratio(numerator: w, denominator: h)
            }
            return nil
        }()

        let frameRate: MediaMetadata.FrameRate? = {
            let fps = stream.avgFrameRate ?? stream.frameRate ?? stream.rFrameRate
            guard let value = fps, value > 0 else { return nil }
            return MediaMetadata.FrameRate(frameRateString: String(format: "%.6f", value))
        }()

        let colorPrimaries = stream.colorInfo?.primaries.flatMap(ColorMapping.primariesString(for:))
        let colorTransfer = stream.colorInfo?.transfer.flatMap(ColorMapping.transferString(for:))
        let colorSpace = stream.colorInfo?.matrix.flatMap(ColorMapping.matrixString(for:))
        let colorRange = stream.colorInfo?.fullRange.map { $0 ? "pc" : "tv" }

        let isInterlaced: Bool? = stream.fieldOrder.map { order in
            switch order {
            case .progressive, .unknown: return false
            case .topFieldFirst, .bottomFieldFirst, .mixed: return true
            }
        }

        let fieldOrderString: String? = stream.fieldOrder?.rawValue

        let hasAlpha: Bool = {
            if let flag = stream.hasAlphaChannel { return flag }
            if let pixFmt = stream.pixelFormat { return hasAlphaChannel(pixelFormat: pixFmt) }
            return false
        }()

        let contentLight = stream.hdr?.contentLightLevel
        let mastering = stream.hdr?.masteringDisplay

        return MediaMetadata.VideoStream(
            codec: stream.codec,
            codecLongName: stream.codecName,
            profile: stream.profile,
            width: stream.width,
            height: stream.height,
            pixelFormat: stream.pixelFormat,
            hasAlpha: hasAlpha,
            pixelAspectRatio: pixelAspectRatio,
            displayAspectRatio: displayAspectRatio,
            frameRate: frameRate,
            bitDepth: stream.bitDepth,
            chromaSubsampling: stream.chromaSubsampling,
            colorPrimaries: colorPrimaries,
            colorTransfer: colorTransfer,
            colorSpace: colorSpace,
            colorRange: colorRange,
            chromaLocation: stream.chromaLocation,
            fieldOrder: fieldOrderString,
            isInterlaced: isInterlaced,
            maxCLL: contentLight?.maxCLL,
            maxFALL: contentLight?.maxFALL,
            masteringMaxLuminance: mastering?.maxLuminance,
            masteringMinLuminance: mastering?.minLuminance
        )
    }

    nonisolated private static func makeAudioStream(from stream: AudioStream) -> MediaMetadata.AudioStream {
        MediaMetadata.AudioStream(
            index: stream.index,
            languageCode: stream.language?.lowercased(),
            title: stream.title,
            codec: stream.codec,
            codecLongName: stream.codecName,
            profile: stream.profile,
            sampleRate: stream.sampleRate,
            channels: stream.channels,
            channelLayout: stream.channelLayout,
            bitDepth: stream.bitDepth,
            bitRate: stream.bitRate.map { Int64($0) },
            isDefault: stream.isDefault ?? false
        )
    }

    nonisolated private static func makeSubtitleStream(from stream: SubtitleStream) -> MediaMetadata.SubtitleStream {
        MediaMetadata.SubtitleStream(
            index: stream.index,
            languageCode: stream.language?.lowercased(),
            title: stream.title,
            codec: stream.codec,
            codecLongName: stream.codecName,
            isDefault: stream.isDefault ?? false,
            isForced: stream.isForced ?? false
        )
    }
}

// MARK: - H.273 → ffmpeg-style color strings

private enum ColorMapping {
    nonisolated static func primariesString(for code: Int) -> String? {
        switch code {
        case 1: return "bt709"
        case 4: return "bt470m"
        case 5: return "bt470bg"
        case 6: return "smpte170m"
        case 7: return "smpte240m"
        case 8: return "film"
        case 9: return "bt2020"
        case 10: return "smpte428"
        case 11: return "smpte431"
        case 12: return "smpte432"
        case 22: return "jedec-p22"
        default: return nil
        }
    }

    nonisolated static func transferString(for code: Int) -> String? {
        switch code {
        case 1: return "bt709"
        case 4: return "bt470m"
        case 5: return "bt470bg"
        case 6: return "smpte170m"
        case 7: return "smpte240m"
        case 8: return "linear"
        case 9: return "log"
        case 10: return "log-sqrt"
        case 11: return "iec61966-2-4"
        case 12: return "bt1361e"
        case 13: return "iec61966-2-1"
        case 14: return "bt2020-10"
        case 15: return "bt2020-12"
        case 16: return "smpte2084"
        case 17: return "smpte428"
        case 18: return "arib-std-b67"
        default: return nil
        }
    }

    nonisolated static func matrixString(for code: Int) -> String? {
        switch code {
        case 0: return "gbr"
        case 1: return "bt709"
        case 4: return "fcc"
        case 5: return "bt470bg"
        case 6: return "smpte170m"
        case 7: return "smpte240m"
        case 8: return "ycgco"
        case 9: return "bt2020nc"
        case 10: return "bt2020c"
        case 11: return "smpte2085"
        case 12: return "chroma-derived-nc"
        case 13: return "chroma-derived-c"
        case 14: return "ictcp"
        default: return nil
        }
    }
}

// MARK: - Pixel-format alpha fallback

private nonisolated func hasAlphaChannel(pixelFormat: String) -> Bool {
    let format = pixelFormat.lowercased()
    if format.contains("4444") { return true }
    if format.contains("rgba") || format.contains("bgra")
        || format.contains("argb") || format.contains("abgr") { return true }
    if format.hasPrefix("yuva") { return true }
    if format.hasPrefix("gbrap") { return true }
    if format.contains("alpha") { return true }
    return false
}
