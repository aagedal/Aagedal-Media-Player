// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Metadata extraction service using SwiftMediaMetadata's SwiftExif module.

import AVFoundation
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
    private var inFlightRequests: [URL: Task<MediaMetadata, Error>] = [:]

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

        if let inFlight = inFlightRequests[url] {
            return try await inFlight.value
        }

        let request = Task {
            try await loadMetadata(for: url)
        }
        inFlightRequests[url] = request

        do {
            let metadata = try await request.value
            inFlightRequests[url] = nil
            cache.setObject(CachedMetadata(metadata: metadata), forKey: url as NSURL)
            return metadata
        } catch {
            inFlightRequests[url] = nil
            throw error
        }
    }

    /// Performs one uncached metadata read. `metadata(for:)` retains the Task
    /// so callers arriving after the preload deadline join this same work
    /// instead of launching a duplicate parser and AVAsset pass.
    private func loadMetadata(for url: URL) async throws -> MediaMetadata {
        var video: VideoMetadata
        do {
            video = try await readVideoMetadata(from: url)
        } catch {
            logger.error("SwiftMediaMetadata read failed for \(url.path): \(error.localizedDescription)")
            throw MetadataError.readFailed(error.localizedDescription)
        }

        // For QuickTime/MP4-family containers, AVAsset's preferredTransform
        // is the authoritative rotation source — it's what the OS applies
        // during AVPlayer playback, and SwiftMediaMetadata's tkhd parsing can disagree
        // depending on which atoms a file carries (the `pasp` path writes
        // displayWidth/displayHeight in coded orientation, the tkhd fallback
        // writes them post-rotation). Overriding stream.rotation here lets
        // the downstream display-dim resolution stay consistent with
        // playback.
        if let avRotation = await avAssetRotation(for: url) {
            for i in 0..<video.videoStreams.count {
                video.videoStreams[i].rotation = avRotation
            }
        }

        let metadata = MetadataMapper.makeMediaMetadata(from: video)
        return metadata
    }

    /// Reads the first video track's `preferredTransform` and returns the
    /// implied rotation in degrees (matching SwiftMediaMetadata/ffprobe convention:
    /// `θ = -atan2(b, a)`). Returns nil for non-QuickTime containers,
    /// unreadable assets, or an identity transform.
    private func avAssetRotation(for url: URL) async -> Int? {
        let ext = url.pathExtension.lowercased()
        guard ["mov", "mp4", "m4v", "qt"].contains(ext) else { return nil }
        let asset = AVURLAsset(url: url)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return nil }
            let transform = try await track.load(.preferredTransform)
            if transform.a == 0 && transform.b == 0 { return nil }
            let degrees = -atan2(transform.b, transform.a) * 180.0 / .pi
            let rounded = Int(degrees.rounded())
            return rounded == 0 ? nil : rounded
        } catch {
            return nil
        }
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
        let chapters = video.chapters.map {
            MediaMetadata.Chapter(
                id: $0.id,
                index: $0.index,
                startTime: $0.startTime,
                endTime: $0.endTime,
                title: $0.title,
                languageCode: $0.language?.lowercased()
            )
        }

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
            subtitleStreams: subtitleStreams,
            chapters: chapters
        )
    }

    nonisolated private static func makeVideoStream(from stream: VideoStream) -> MediaMetadata.VideoStream {
        let pixelAspectRatio: MediaMetadata.Ratio? = stream.pixelAspectRatio.flatMap { par in
            MediaMetadata.Ratio(numerator: par.0, denominator: par.1)
        }

        // Resolve display dimensions, mirroring ffprobe's resolution priority:
        //   1. explicit display dimensions from the container,
        //   2. PAR-corrected coded dimensions (anamorphic content),
        //   3. coded dimensions as a square-pixel fallback.
        //
        // SwiftMediaMetadata populates `displayWidth`/`displayHeight` inconsistently
        // depending on which atoms a file carries:
        //   - MP4/MOV with `pasp` (most iPhone HEVC clips) populates them from
        //     coded × PAR, in the coded *orientation* — for square-pixel
        //     portrait recordings this matches the coded grid and the tkhd
        //     rotation is reported separately on `stream.rotation`.
        //   - MP4/MOV without `pasp` falls back to the tkhd width/height,
        //     which are already post-rotation (different orientation from the
        //     coded grid).
        //   - MKV uses the container's explicit DisplayWidth/DisplayHeight
        //     (no rotation involved).
        //
        // So we detect whether dims still share the coded orientation and
        // only then apply the rotation swap, to avoid double-rotating tkhd
        // values.
        let normalizedRotation = ((stream.rotation ?? 0) % 360 + 360) % 360
        let rotationIsQuarter = normalizedRotation == 90 || normalizedRotation == 270
        let displayDims: (Int, Int)? = {
            let baseDims: (Int, Int)?
            if let w = stream.displayWidth, let h = stream.displayHeight, w > 0, h > 0 {
                baseDims = (w, h)
            } else if let par = stream.pixelAspectRatio,
                      par.0 > 0, par.1 > 0, par.0 != par.1,
                      let codedW = stream.width, let codedH = stream.height,
                      codedW > 0, codedH > 0 {
                let displayW = Int((Double(codedW) * Double(par.0) / Double(par.1)).rounded())
                baseDims = (displayW, codedH)
            } else if let codedW = stream.width, let codedH = stream.height,
                      codedW > 0, codedH > 0 {
                baseDims = (codedW, codedH)
            } else {
                baseDims = nil
            }
            guard let (w, h) = baseDims else { return nil }
            guard let codedW = stream.width, let codedH = stream.height,
                  codedW > 0, codedH > 0 else { return (w, h) }
            let displayLandscape = w >= h
            let codedLandscape = codedW >= codedH
            let needsRotationSwap = rotationIsQuarter && (displayLandscape == codedLandscape)
            return needsRotationSwap ? (h, w) : (w, h)
        }()
        let displayWidth = displayDims?.0
        let displayHeight = displayDims?.1
        let displayAspectRatio: MediaMetadata.Ratio? = {
            guard let (w, h) = displayDims else { return nil }
            return MediaMetadata.Ratio(numerator: w, denominator: h)
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
            displayWidth: displayWidth,
            displayHeight: displayHeight,
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
            rotation: stream.rotation,
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
