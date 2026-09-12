// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Immutable, playback-facing identity for one selected source audio stream.
/// `audioStreamOrderIndex` is always the zero-based audio-only order expected
/// by FFmpeg's `0:a:N`, never a toolbar row or container-wide stream number.
nonisolated struct LiveAudioMeterPlaybackSource: Equatable, Sendable {
    enum Failure: Error, Equatable, LocalizedError {
        case noMedia
        case noSelectedAudioTrack
        case missingSampleRate
        case missingChannelCount
        case unsupportedSampleRate(Int)
        case unsupportedChannelCount(Int)
        case invalidPlaybackTime

        var errorDescription: String? {
            switch self {
            case .noMedia:
                "Load a media file before opening live audio meters."
            case .noSelectedAudioTrack:
                "The selected source has no meterable audio track."
            case .missingSampleRate:
                "The selected audio track does not declare a sample rate."
            case .missingChannelCount:
                "The selected audio track does not declare a channel count."
            case .unsupportedSampleRate(let rate):
                "Live meters do not yet support the selected \(rate) Hz audio track."
            case .unsupportedChannelCount(let count):
                "Live meters support one through eight channels; the selected track has \(count)."
            case .invalidPlaybackTime:
                "The live meter start position must be a finite playback time."
            }
        }
    }

    let id: String
    let label: String
    let url: URL
    let audioStreamOrderIndex: Int
    let containerStreamIndex: Int?
    let trackLabel: String
    let format: LiveAudioMeterFormat
    let declaredChannelLayout: String?
    let channelLabels: [String]
    let duration: TimeInterval

    init(
        id: String,
        label: String,
        url: URL,
        audioStreamOrderIndex: Int,
        stream: MediaMetadata.AudioStream,
        trackLabel: String,
        duration: TimeInterval
    ) throws {
        guard let sampleRate = stream.sampleRate else { throw Failure.missingSampleRate }
        guard let channels = stream.channels else { throw Failure.missingChannelCount }
        guard [44_100, 48_000, 96_000].contains(sampleRate) else {
            throw Failure.unsupportedSampleRate(sampleRate)
        }
        guard (1...8).contains(channels) else { throw Failure.unsupportedChannelCount(channels) }

        self.id = id
        self.label = label
        self.url = url
        self.audioStreamOrderIndex = audioStreamOrderIndex
        containerStreamIndex = stream.index
        self.trackLabel = trackLabel
        declaredChannelLayout = stream.channelLayout
        channelLabels = AudioChannelLabels.names(count: channels, layout: stream.channelLayout)
        self.duration = duration.isFinite ? max(0, duration) : 0
        format = try LiveAudioMeterFormat(
            sampleRate: sampleRate,
            layout: Self.meterLayout(channels: channels, declared: stream.channelLayout)
        )
    }

    func request(at playbackTime: TimeInterval) throws -> LiveAudioMeterDecodeRequest {
        guard playbackTime.isFinite else { throw Failure.invalidPlaybackTime }
        let boundedTime = min(max(0, playbackTime), duration > 0 ? duration : .greatestFiniteMagnitude)
        let scaledFrame = (boundedTime * Double(format.sampleRate)).rounded()
        guard scaledFrame.isFinite, scaledFrame < Double(Int64.max) else {
            throw Failure.invalidPlaybackTime
        }
        let startFrame = Int64(scaledFrame)
        let exactTime = Double(startFrame) / Double(format.sampleRate)
        return try LiveAudioMeterDecodeRequest(
            url: url,
            audioStreamOrderIndex: audioStreamOrderIndex,
            format: format,
            startSourceFrame: startFrame,
            startSourceTime: exactTime
        )
    }

    var sourceOption: LiveAudioMeterSourceOption {
        LiveAudioMeterSourceOption(id: id, label: label, detail: trackLabel)
    }

    private static func meterLayout(
        channels: Int, declared: String?
    ) -> LiveAudioMeterFormat.Layout {
        let layout = declared?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch (channels, layout) {
        case (1, _): return .mono
        case (2, _): return .stereo
        case (6, "5.1(side)"): return .surround5Point1
        case (8, "7.1"): return .surround7Point1
        default: return .unknown(channels: channels)
        }
    }
}

extension PlayerController {
    /// Resolves the selected toolbar row to FFmpeg's audio-only stream order.
    /// The row position and a container-wide metadata index are not safe here.
    func liveAudioMeterSource(id: String, label: String) throws -> LiveAudioMeterPlaybackSource {
        guard let item = mediaItem else { throw LiveAudioMeterPlaybackSource.Failure.noMedia }
        guard audioTrackOptions.indices.contains(selectedAudioTrackOrderIndex),
              let stream = selectedAudioStream else {
            throw LiveAudioMeterPlaybackSource.Failure.noSelectedAudioTrack
        }
        let option = audioTrackOptions[selectedAudioTrackOrderIndex]
        return try LiveAudioMeterPlaybackSource(
            id: id,
            label: label,
            url: item.url,
            audioStreamOrderIndex: option.streamIndex,
            stream: stream,
            trackLabel: option.title,
            duration: item.durationSeconds
        )
    }
}
