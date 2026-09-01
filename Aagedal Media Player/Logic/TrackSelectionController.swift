// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Combine
import Foundation
import OSLog

/// Owns the selectable audio, subtitle, and chapter state for the active media.
///
/// `PlayerController` remains responsible for playback orchestration (pausing
/// around a track switch and seeking to chapters), while this type owns option
/// discovery, selection validation, and backend-specific track application.
@MainActor
final class TrackSelectionController: ObservableObject {
    struct AudioTrackOption: Identifiable, Equatable {
        let id: Int
        let position: Int
        let streamIndex: Int
        let mediaOptionIndex: Int?
        let title: String
        let subtitle: String?
    }

    struct SubtitleTrackOption: Identifiable, Equatable {
        let id: Int
        let position: Int
        let trackId: Int32
        let title: String
    }

    struct ChapterOption: Identifiable, Equatable {
        let id: Int
        let position: Int
        let time: Double
        let title: String
    }

    @Published private(set) var audioTrackOptions: [AudioTrackOption] = []
    @Published private(set) var subtitleTrackOptions: [SubtitleTrackOption] = []
    @Published private(set) var chapterOptions: [ChapterOption] = []
    @Published private(set) var selectedAudioTrackOrderIndex = 0
    @Published private(set) var selectedSubtitleTrackOrderIndex = -1

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "TrackSelectionController")

    func refreshAudioTrackOptions(
        mediaItem: MediaItem,
        playerItem: AVPlayerItem?,
        mpvPlayer: MPVPlayer?,
        useMPV: Bool
    ) async {
        let existingSelection = selectedAudioTrackOrderIndex

        if useMPV {
            guard let mpvPlayer else { return }
            rebuildMPVTrackOptions(
                audioNames: mpvPlayer.audioTrackNames,
                audioIndexes: mpvPlayer.audioTrackIndexes,
                subtitleNames: mpvPlayer.subtitleTrackNames,
                subtitleIndexes: mpvPlayer.subtitleTrackIndexes
            )
        } else {
            let metadata = mediaItem.metadata
            let orderedIndices = metadata.map(Self.orderAudioStreams(from:)) ?? []
            let mediaGroup: AVMediaSelectionGroup?
            if let playerItem {
                mediaGroup = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible)
            } else {
                mediaGroup = nil
            }
            buildAVAudioTrackOptions(
                metadata: metadata,
                orderedIndices: orderedIndices,
                mediaGroup: mediaGroup
            )
        }

        selectedAudioTrackOrderIndex = clampedAudioSelection(existingSelection)
        await applySelectedAudioTrack(playerItem: playerItem, mpvPlayer: mpvPlayer, useMPV: useMPV)
    }

    func selectAudioTrack(
        at position: Int,
        playerItem: AVPlayerItem?,
        mpvPlayer: MPVPlayer?,
        useMPV: Bool
    ) async -> Bool {
        guard audioTrackOptions.indices.contains(position),
              position != selectedAudioTrackOrderIndex else { return false }

        selectedAudioTrackOrderIndex = position
        await applySelectedAudioTrack(playerItem: playerItem, mpvPlayer: mpvPlayer, useMPV: useMPV)
        return true
    }

    func applySelectedAudioTrack(
        playerItem: AVPlayerItem?,
        mpvPlayer: MPVPlayer?,
        useMPV: Bool
    ) async {
        if useMPV {
            applySelectedAudioTrackToMPV(mpvPlayer)
        } else if let playerItem {
            await applySelectedAudioTrackToAVPlayer(playerItem)
        }
    }

    func selectSubtitleTrack(at position: Int, mpvPlayer: MPVPlayer?) -> Bool {
        guard let mpvPlayer else { return false }

        if position < 0 {
            mpvPlayer.disableSubtitles()
            selectedSubtitleTrackOrderIndex = -1
            return true
        }

        guard subtitleTrackOptions.indices.contains(position) else { return false }
        let option = subtitleTrackOptions[position]
        mpvPlayer.currentSubtitleTrackIndex = option.trackId
        selectedSubtitleTrackOrderIndex = position
        return true
    }

    func refreshChapterOptions(playerItem: AVPlayerItem?, mpvPlayer: MPVPlayer?, useMPV: Bool) async {
        if useMPV, let mpvPlayer {
            chapterOptions = mpvPlayer.chapters.enumerated().map { index, chapter in
                ChapterOption(
                    id: index,
                    position: index,
                    time: chapter.time,
                    title: chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title
                )
            }
        } else if let asset = playerItem?.asset {
            let groups = (try? await asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: Locale.preferredLanguages
            )) ?? []
            var options: [ChapterOption] = []
            for (index, group) in groups.enumerated() {
                let start = group.timeRange.start.seconds
                guard start.isFinite else { continue }
                var title = "Chapter \(index + 1)"
                if let titleItem = group.items.first(where: { $0.commonKey == .commonKeyTitle }),
                   let value = try? await titleItem.load(.stringValue), !value.isEmpty {
                    title = value
                }
                options.append(ChapterOption(id: index, position: index, time: start, title: title))
            }
            chapterOptions = options
        } else {
            chapterOptions = []
        }
    }

    func reset(preservingSelections: Bool) {
        if !preservingSelections {
            selectedAudioTrackOrderIndex = 0
            selectedSubtitleTrackOrderIndex = -1
        }
        audioTrackOptions = []
        subtitleTrackOptions = []
        chapterOptions = []
    }

    /// Pure MPV option mapping kept internal so it can be regression tested
    /// without constructing an MPV playback backend.
    func rebuildMPVTrackOptions(
        audioNames: [String],
        audioIndexes: [Int32],
        subtitleNames: [String],
        subtitleIndexes: [Int32]
    ) {
        audioTrackOptions = audioIndexes.enumerated().compactMap { index, trackID in
            guard trackID > 0 else { return nil }
            return AudioTrackOption(
                id: Int(trackID),
                position: audioIndexes[..<index].filter { $0 > 0 }.count,
                streamIndex: Int(trackID) - 1,
                mediaOptionIndex: nil,
                title: index < audioNames.count ? audioNames[index] : "Track \(trackID)",
                subtitle: nil
            )
        }

        subtitleTrackOptions = subtitleIndexes.enumerated().compactMap { index, trackID in
            guard trackID > 0 else { return nil }
            return SubtitleTrackOption(
                id: Int(trackID),
                position: subtitleIndexes[..<index].filter { $0 > 0 }.count,
                trackId: trackID,
                title: index < subtitleNames.count ? subtitleNames[index] : "Subtitle \(trackID)"
            )
        }

        selectedAudioTrackOrderIndex = clampedAudioSelection(selectedAudioTrackOrderIndex)
        if !subtitleTrackOptions.indices.contains(selectedSubtitleTrackOrderIndex) {
            selectedSubtitleTrackOrderIndex = -1
        }
    }

    nonisolated static func orderAudioStreams(from metadata: MediaMetadata) -> [Int] {
        metadata.audioStreams.enumerated().sorted { lhs, rhs in
            if lhs.element.isDefault != rhs.element.isDefault {
                return lhs.element.isDefault
            }
            let lhsChannels = lhs.element.channels ?? 0
            let rhsChannels = rhs.element.channels ?? 0
            if lhsChannels != rhsChannels { return lhsChannels > rhsChannels }
            return lhs.offset < rhs.offset
        }.map(\.offset)
    }

    private func buildAVAudioTrackOptions(
        metadata: MediaMetadata?,
        orderedIndices: [Int],
        mediaGroup: AVMediaSelectionGroup?
    ) {
        let metadataStreams = metadata?.audioStreams ?? []
        let effectiveOrder = orderedIndices.isEmpty ? Array(metadataStreams.indices) : orderedIndices
        let mediaOptions = mediaGroup?.options ?? []

        guard !metadataStreams.isEmpty || !mediaOptions.isEmpty else {
            audioTrackOptions = []
            return
        }

        audioTrackOptions = (0..<max(effectiveOrder.count, mediaOptions.count)).map { position in
            let streamIndex = effectiveOrder.indices.contains(position) ? effectiveOrder[position] : position
            let stream = metadataStreams.indices.contains(streamIndex) ? metadataStreams[streamIndex] : nil
            let mediaOption = mediaOptions.indices.contains(position) ? mediaOptions[position] : nil
            let title = stream.map { formattedAudioTrackTitle(for: $0, position: position) }
                ?? mediaOption?.displayName
                ?? "Audio Track \(position + 1)"

            var details: [String] = []
            if let stream {
                if stream.isDefault { details.append("Default") }
                if let channels = stream.channels { details.append("\(channels) ch") }
                if let sampleRate = stream.sampleRate { details.append("\(sampleRate) Hz") }
                if let codec = stream.codecLongName ?? stream.codec { details.append(codec) }
            } else if let locale = mediaOption?.locale {
                let languageCode = locale.language.languageCode?.identifier ?? ""
                details.append(locale.localizedString(forLanguageCode: languageCode) ?? locale.identifier)
            }

            return AudioTrackOption(
                id: streamIndex,
                position: position,
                streamIndex: streamIndex,
                mediaOptionIndex: mediaOptions.indices.contains(position) ? position : nil,
                title: title,
                subtitle: details.isEmpty ? nil : details.joined(separator: " \u{2022} ")
            )
        }
    }

    private func formattedAudioTrackTitle(for stream: MediaMetadata.AudioStream, position: Int) -> String {
        var components = ["#\(stream.index ?? position)"]
        if let language = stream.languageCode, !language.isEmpty { components.append(language) }
        if let codec = stream.codecLongName ?? stream.codec, !codec.isEmpty { components.append(codec) }
        if let layout = stream.channelLayout, !layout.isEmpty { components.append(layout) }
        return components.joined(separator: " \u{2013} ")
    }

    private func clampedAudioSelection(_ selection: Int) -> Int {
        audioTrackOptions.isEmpty ? 0 : min(max(selection, 0), audioTrackOptions.count - 1)
    }

    private func applySelectedAudioTrackToMPV(_ mpvPlayer: MPVPlayer?) {
        guard let mpvPlayer,
              audioTrackOptions.indices.contains(selectedAudioTrackOrderIndex) else { return }
        mpvPlayer.currentAudioTrackIndex = Int32(audioTrackOptions[selectedAudioTrackOrderIndex].id)
    }

    private func applySelectedAudioTrackToAVPlayer(_ playerItem: AVPlayerItem) async {
        let mediaGroup: AVMediaSelectionGroup?
        do {
            mediaGroup = try await playerItem.asset.loadMediaSelectionGroup(for: .audible)
        } catch {
            logger.error("Failed to load audible group: \(error)")
            mediaGroup = nil
        }

        guard audioTrackOptions.indices.contains(selectedAudioTrackOrderIndex) else { return }
        let selectedOption = audioTrackOptions[selectedAudioTrackOrderIndex]

        if let mediaGroup,
           let mappedIndex = selectedOption.mediaOptionIndex,
           mediaGroup.options.indices.contains(mappedIndex) {
            let avOption = mediaGroup.options[mappedIndex]
            if playerItem.currentMediaSelection.selectedMediaOption(in: mediaGroup) != avOption {
                playerItem.select(avOption, in: mediaGroup)
                return
            }
        }

        let audioTracks = playerItem.tracks.filter { $0.assetTrack?.mediaType == .audio }
        for (index, track) in audioTracks.enumerated() {
            let shouldEnable = index == selectedAudioTrackOrderIndex
            if track.isEnabled != shouldEnable { track.isEnabled = shouldEnable }
        }
    }
}
