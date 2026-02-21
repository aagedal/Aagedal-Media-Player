// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Controller for media playback with dual AVPlayer/MPV backend.
// Adapted from Aagedal Media Converter's PreviewPlayerController.

import SwiftUI
import AppKit
import AVKit
import Combine
import OSLog
import UniformTypeIdentifiers

@MainActor
final class PlayerController: ObservableObject {
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

    // MARK: - Published State

    @Published var volume: Double = 100 {
        didSet {
            if useMPV, let mpvPlayer {
                mpvPlayer.volume = volume
            }
        }
    }
    @Published var isMuted: Bool = false {
        didSet {
            if useMPV, let mpvPlayer {
                mpvPlayer.isMuted = isMuted
            }
        }
    }
    @Published var player: AVPlayer?
    @Published var isPreparing = false
    @Published var isReady = false
    @Published var errorMessage: String?
    @Published var currentPlaybackTime: Double = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentPlaybackSpeed: Float = 1.0
    @Published private(set) var isReverseSimulating: Bool = false
    @Published var audioTrackOptions: [AudioTrackOption] = []
    @Published var subtitleTrackOptions: [SubtitleTrackOption] = []
    @Published var videoAspectRatio: CGFloat?

    // Trim points
    @Published var trimIn: Double?
    @Published var trimOut: Double?

    // Screenshot feedback
    @Published var lastScreenshotURL: URL?
    @Published var isSavingScreenshot = false
    @Published var screenshotDone = false

    // Trim export feedback
    @Published var isExportingTrim = false
    @Published var trimExportDone = false

    // Reverse simulation
    private var reverseSpeed: Int = 1
    private var reverseTimer: Timer?

    // MARK: - State

    @Published var mediaItem: MediaItem?
    var loopObserver: Any?
    var playbackTimeObserver: Any?
    weak var playbackTimeObserverOwner: AVPlayer?
    var playerItemStatusObserver: Any?
    weak var playerView: AVPlayerView?
    var selectedAudioTrackOrderIndex: Int = 0
    var selectedSubtitleTrackOrderIndex: Int = -1

    // MARK: - MPV State
    var mpvPlayer: MPVPlayer?
    var useMPV = false
    // MPV loop observer
    var mpvLoopObserverTimer: Timer?
    private var mpvAspectRatioCancellable: AnyCancellable?

    // MARK: - Initialization

    var playbackTimePublisher: Published<Double>.Publisher { $currentPlaybackTime }

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "PlayerController")

    init() {}

    // MARK: - Media Item Management

    func loadMedia(_ item: MediaItem) {
        let previousURL = mediaItem?.url
        mediaItem = item

        // Always prepare if it's a new file, or if it's the first load
        if previousURL != item.url || !isReady {
            videoAspectRatio = nil
            preparePlayback(startTime: 0)
        }
    }

    func updateMetadata(_ item: MediaItem) {
        guard mediaItem?.url == item.url else { return }
        let currentTime = currentPlaybackTime
        mediaItem?.metadata = item.metadata
        mediaItem?.durationSeconds = item.durationSeconds
        mediaItem?.hasVideoStream = item.hasVideoStream

        // Update aspect ratio from FFprobe (authoritative)
        if let ratio = item.videoDisplayAspectRatio, ratio.isFinite, ratio > 0 {
            videoAspectRatio = CGFloat(ratio)
        }

        // If surround audio was detected and we're on AVPlayer, switch to MPV
        if hasSurroundAudio && !hasProResVideoCodec && !useMPV {
            logger.info("Surround audio detected after metadata load, switching to MPV for \(item.url.lastPathComponent)")
            preparePlayback(startTime: currentTime, resetAudioSelection: true)
        }
    }

    func updateLoopPlayback(_ loop: Bool) {
        mediaItem?.loopPlayback = loop
        updatePlayerActionAtEnd()
    }

    // MARK: - Playback Preparation

    /// Check if the video has surround audio (any track with more than 2 channels)
    private var hasSurroundAudio: Bool {
        guard let audioStreams = mediaItem?.metadata?.audioStreams else { return false }
        return audioStreams.contains { ($0.channels ?? 0) > 2 }
    }

    /// Check if the video codec is ProRes
    private var hasProResVideoCodec: Bool {
        guard let videoStream = mediaItem?.metadata?.primaryVideoStream,
              let codec = videoStream.codec?.lowercased() else { return false }

        let proresCodecs = [
            "prores", "prores_ks",
            "ap4h", "ap4x",
            "apcn", "apch", "apcs", "apco",
            "aprn", "aprh",
        ]

        return proresCodecs.contains { codec.contains($0) }
    }

    func preparePlayback(startTime: TimeInterval, resetAudioSelection: Bool = true) {
        teardown(resetAudioSelection: resetAudioSelection)
        isPreparing = true
        isReady = false
        errorMessage = nil
        useMPV = false

        guard let item = mediaItem else {
            isPreparing = false
            return
        }

        let url = item.url

        // Force MPV for surround audio files (unless ProRes)
        if hasSurroundAudio && !hasProResVideoCodec {
            logger.info("Surround audio detected with non-ProRes codec, using MPV player for \(url.lastPathComponent)")
            setupMPV(url: url, startTime: startTime)
            return
        }

        // Try AVPlayer first
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)

        self.player = player

        installPlayerItemStatusObserver(for: playerItem, startTime: startTime)

        self.isPreparing = false
        refreshAudioTrackOptions(playerItem: playerItem)

        let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)

        installLoopObserver(for: playerItem)
        installPlaybackTimeObserver(for: player)
        updatePlayerActionAtEnd()
    }

    func setupMPV(url: URL, startTime: Double) {
        player = nil

        let mpv = MPVPlayer()
        self.mpvPlayer = mpv
        self.useMPV = true
        self.isPreparing = false

        mpv.volume = volume
        mpv.isMuted = isMuted

        mpv.load(url: url, startTime: startTime, autostart: false)

        // Sync time position
        Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await time in mpv.$timePos.values {
                self.currentPlaybackTime = time
            }
        }

        // Observe file loaded state for isReady
        Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await isLoaded in mpv.$isFileLoaded.values {
                if isLoaded {
                    self.isReady = true
                    break
                }
            }
        }

        // Forward MPV aspect ratio
        mpvAspectRatioCancellable = mpv.$videoAspectRatio
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ratio in
                self?.videoAspectRatio = ratio
            }

        // Refresh audio tracks after MPV parses the media
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.refreshAudioTrackOptions(playerItem: nil)
        }

        // Install MPV loop observer
        installMPVLoopObserver()
    }

    // MARK: - Unified Playback Control

    private func syncIsPlaying() {
        if useMPV {
            isPlaying = mpvPlayer?.isPlaying ?? false
        } else {
            isPlaying = (player?.rate ?? 0) > 0
        }
    }

    func togglePlayback() {
        guard isReady else { return }

        if isReverseSimulating {
            stopReverseSimulation()
            return
        }

        if useMPV, let mpv = mpvPlayer {
            let wasPlaying = mpv.isPlaying
            mpv.rate = 1.0
            currentPlaybackSpeed = 1.0

            if wasPlaying {
                mpv.pause()
            } else {
                mpv.play()
            }
        } else if let player = player {
            currentPlaybackSpeed = 1.0
            if player.rate != 0 {
                player.pause()
            } else {
                player.rate = 1.0
                player.play()
            }
        }
        syncIsPlaying()
    }

    func pause() {
        stopReverseSimulation()

        if useMPV, let mpv = mpvPlayer {
            mpv.rate = 1.0
            currentPlaybackSpeed = 1.0
            mpv.pause()
        } else {
            currentPlaybackSpeed = 1.0
            player?.pause()
        }
        syncIsPlaying()
    }

    func play() {
        guard isReady else { return }

        if useMPV, let mpv = mpvPlayer {
            mpv.rate = 1.0
            currentPlaybackSpeed = 1.0
            mpv.play()
        } else if let player = player {
            player.rate = 1.0
            currentPlaybackSpeed = 1.0
            player.play()
        }
        syncIsPlaying()
    }

    func stepRate(forward: Bool) {
        if useMPV, let mpv = mpvPlayer {
            let current = mpv.rate
            let step: Float = 0.5
            let newRate = forward ? current + step : current - step
            mpv.rate = max(0.25, min(newRate, 4.0))
            currentPlaybackSpeed = mpv.rate
        } else if let player = player {
            let current = player.rate
            let step: Float = 1.0
            let newRate = forward ? current + step : current - step
            player.rate = newRate
            currentPlaybackSpeed = player.rate
        }
    }

    func startReverseSimulation() {
        guard isReady else { return }

        if isReverseSimulating {
            reverseSpeed = min(reverseSpeed + 1, 4)
            reverseTimer?.invalidate()
            let interval = (1.0/24.0) / Double(reverseSpeed)
            reverseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.seekByFrames(-1)
                }
            }
            currentPlaybackSpeed = -Float(reverseSpeed)
            return
        }

        pause()
        reverseSpeed = 1
        isReverseSimulating = true
        currentPlaybackSpeed = -1.0

        let interval = 1.0/24.0
        reverseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.seekByFrames(-1)
            }
        }
    }

    func stopReverseSimulation() {
        isReverseSimulating = false
        reverseSpeed = 1
        reverseTimer?.invalidate()
        reverseTimer = nil
        if !isReverseSimulating {
            currentPlaybackSpeed = 1.0
        }
        syncIsPlaying()
    }

    func rewind() {
        stopReverseSimulation()
        stepRate(forward: false)
    }

    func fastForward() {
        guard isReady else { return }

        if isReverseSimulating {
            stopReverseSimulation()
            return
        }

        if useMPV, let mpv = mpvPlayer {
            if !mpv.isPlaying {
                mpv.rate = 1.0
                currentPlaybackSpeed = 1.0
                mpv.play()
                return
            }
        } else if let player = player {
            if player.rate == 0 {
                player.rate = 1.0
                currentPlaybackSpeed = 1.0
                player.play()
                return
            }
        }

        stepRate(forward: true)
        syncIsPlaying()
    }

    func seek(by seconds: Double) {
        guard let item = mediaItem else { return }
        let currentTime = getCurrentTime() ?? 0
        let newTime = currentTime + seconds
        seekTo(max(0, min(newTime, item.durationSeconds)))
    }

    func seekByFrames(_ frameCount: Int) {
        if let frameRate = mediaItem?.metadata?.primaryVideoStream?.frameRate,
           let frameRateValue = frameRate.value, frameRateValue > 0 {
            let secondsPerFrame = 1.0 / frameRateValue
            seek(by: Double(frameCount) * secondsPerFrame)
        } else {
            seek(by: Double(frameCount) / 30.0)
        }
    }

    func seekTo(_ time: Double) {
        guard isReady else { return }

        currentPlaybackTime = time

        if useMPV, let mpv = mpvPlayer {
            mpv.seek(to: time)
            return
        }

        guard let player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func getCurrentTime() -> TimeInterval? {
        return currentPlaybackTime
    }

    func toggleFullscreen() {
        let window = playerView?.window ?? NSApp.keyWindow
        window?.toggleFullScreen(nil)
    }

    // MARK: - Audio Track Selection

    func refreshAudioTrackOptions(playerItem: AVPlayerItem?) {
        let existingSelection = selectedAudioTrackOrderIndex
        Task { @MainActor [weak self] in
            guard let self, let item = self.mediaItem else { return }

            if useMPV {
                guard let mpv = mpvPlayer else { return }
                let names = mpv.audioTrackNames
                let indexes = mpv.audioTrackIndexes
                buildMPVAudioTrackOptions(names: names, indexes: indexes)
                buildMPVSubtitleTrackOptions()
            } else {
                let metadata = item.metadata

                let orderedIndices = metadata.map { self.orderAudioStreams(from: $0) } ?? []
                let mediaGroup: AVMediaSelectionGroup?
                if let playerItem {
                    mediaGroup = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible)
                } else {
                    mediaGroup = nil
                }

                self.buildAudioTrackOptions(metadata: metadata, orderedIndices: orderedIndices, mediaGroup: mediaGroup)
            }

            if self.audioTrackOptions.isEmpty {
                self.selectedAudioTrackOrderIndex = 0
            } else {
                let clamped = min(max(existingSelection, 0), self.audioTrackOptions.count - 1)
                self.selectedAudioTrackOrderIndex = clamped
            }

            self.applySelectedAudioTrack()
        }
    }

    nonisolated private func orderAudioStreams(from metadata: MediaMetadata) -> [Int] {
        guard !metadata.audioStreams.isEmpty else { return [] }
        let sorted = metadata.audioStreams.enumerated().sorted { lhs, rhs in
            let lhsDefault = metadata.isDefaultAudioStream(index: lhs.offset)
            let rhsDefault = metadata.isDefaultAudioStream(index: rhs.offset)
            if lhsDefault != rhsDefault { return lhsDefault }
            let lhsChannels = lhs.element.channels ?? 0
            let rhsChannels = rhs.element.channels ?? 0
            if lhsChannels != rhsChannels { return lhsChannels > rhsChannels }
            return lhs.offset < rhs.offset
        }
        return sorted.map { $0.offset }
    }

    private func buildAudioTrackOptions(metadata: MediaMetadata?, orderedIndices: [Int], mediaGroup: AVMediaSelectionGroup?) {
        let metadataStreams = metadata?.audioStreams ?? []
        let effectiveOrder = orderedIndices.isEmpty ? Array(metadataStreams.indices) : orderedIndices
        let mediaOptions = mediaGroup?.options ?? []

        if metadataStreams.isEmpty && mediaOptions.isEmpty {
            audioTrackOptions = []
            return
        }

        var options: [AudioTrackOption] = []
        let count = max(effectiveOrder.count, mediaOptions.count)
        for position in 0..<count {
            let streamIndex = effectiveOrder.indices.contains(position) ? effectiveOrder[position] : position
            let stream = metadataStreams.indices.contains(streamIndex) ? metadataStreams[streamIndex] : nil
            let mediaOption = mediaOptions.indices.contains(position) ? mediaOptions[position] : nil
            let mediaOptionIndex = mediaOptions.indices.contains(position) ? position : nil

            let title: String
            if let stream {
                title = self.formattedAudioTrackTitle(for: stream, position: position)
            } else if let mediaOption {
                title = mediaOption.displayName
            } else {
                title = "Audio Track \(position + 1)"
            }

            var details: [String] = []
            if let stream {
                if stream.isDefault { details.append("Default") }
                if let channels = stream.channels { details.append("\(channels) ch") }
                if let sampleRate = stream.sampleRate { details.append("\(sampleRate) Hz") }
                if let codec = stream.codecLongName ?? stream.codec { details.append(codec) }
            }

            if let mediaOption, details.isEmpty {
                if let locale = mediaOption.locale {
                    details.append(locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "") ?? locale.identifier)
                }
            }

            options.append(
                AudioTrackOption(
                    id: streamIndex,
                    position: position,
                    streamIndex: streamIndex,
                    mediaOptionIndex: mediaOptionIndex,
                    title: title,
                    subtitle: details.isEmpty ? nil : details.joined(separator: " \u{2022} ")
                )
            )
        }

        audioTrackOptions = options
    }

    private func buildMPVAudioTrackOptions(names: [String], indexes: [Int32]) {
        var options: [AudioTrackOption] = []

        for (index, trackID) in indexes.enumerated() {
            if trackID <= 0 { continue }

            let name = index < names.count ? names[index] : "Track \(trackID)"
            let position = options.count

            options.append(
                AudioTrackOption(
                    id: Int(trackID),
                    position: position,
                    streamIndex: Int(trackID) - 1,
                    mediaOptionIndex: nil,
                    title: name,
                    subtitle: nil
                )
            )
        }

        audioTrackOptions = options

        if !audioTrackOptions.isEmpty {
            if selectedAudioTrackOrderIndex >= audioTrackOptions.count {
                selectedAudioTrackOrderIndex = 0
            }
        }
    }

    private func formattedAudioTrackTitle(for stream: MediaMetadata.AudioStream, position: Int) -> String {
        var components: [String] = []

        if let index = stream.index {
            components.append("#\(index)")
        } else {
            components.append("#\(position)")
        }

        if let language = stream.languageCode, !language.isEmpty {
            components.append(language)
        }

        if let codecName = stream.codecLongName ?? stream.codec, !codecName.isEmpty {
            components.append(codecName)
        }

        if let layout = stream.channelLayout, !layout.isEmpty {
            components.append(layout)
        }

        if components.isEmpty {
            return "Audio Track \(position + 1)"
        }

        return components.joined(separator: " \u{2013} ")
    }

    func selectAudioTrack(at position: Int) {
        guard position != selectedAudioTrackOrderIndex else { return }

        let wasPlaying = (player?.rate ?? 0) > 0 || (mpvPlayer?.isPlaying ?? false)
        if wasPlaying { pause() }

        selectedAudioTrackOrderIndex = position
        applySelectedAudioTrack()

        if wasPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.togglePlayback()
            }
        }
    }

    func applySelectedAudioTrack() {
        if useMPV {
            applySelectedAudioTrackToMPV()
        } else {
            applySelectedAudioTrackToCurrentPlayerItem()
        }
    }

    private func applySelectedAudioTrackToMPV() {
        guard let mpv = mpvPlayer else { return }

        let indexes = mpv.audioTrackIndexes

        if self.selectedAudioTrackOrderIndex < indexes.count {
            let trackID = indexes[self.selectedAudioTrackOrderIndex]
            mpv.currentAudioTrackIndex = trackID
        }
    }

    func applySelectedAudioTrackToCurrentPlayerItem() {
        guard let playerItem = player?.currentItem else { return }

        Task { @MainActor [weak self, weak playerItem] in
            guard let self, let playerItem else { return }

            var mediaGroup: AVMediaSelectionGroup?
            do {
                mediaGroup = try await playerItem.asset.loadMediaSelectionGroup(for: .audible)
            } catch {
                logger.error("Failed to load audible group: \(error)")
            }

            self.buildAudioTrackOptions(metadata: self.mediaItem?.metadata, orderedIndices: [], mediaGroup: mediaGroup)

            guard !self.audioTrackOptions.isEmpty else { return }

            let desiredPosition = min(max(self.selectedAudioTrackOrderIndex, 0), self.audioTrackOptions.count - 1)
            let selectedOption = self.audioTrackOptions[desiredPosition]

            if let mediaGroup, let mappedIndex = selectedOption.mediaOptionIndex, mediaGroup.options.indices.contains(mappedIndex) {
                let avOption = mediaGroup.options[mappedIndex]
                if playerItem.currentMediaSelection.selectedMediaOption(in: mediaGroup) != avOption {
                    playerItem.select(avOption, in: mediaGroup)
                    return
                }
            }

            let tracks = playerItem.tracks
            var audioTracks: [AVPlayerItemTrack] = []
            for track in tracks {
                if track.assetTrack?.mediaType == .audio {
                    audioTracks.append(track)
                }
            }

            if !audioTracks.isEmpty {
                for (index, track) in audioTracks.enumerated() {
                    let shouldEnable = (index == desiredPosition)
                    if track.isEnabled != shouldEnable {
                        track.isEnabled = shouldEnable
                    }
                }
            }
        }
    }

    // MARK: - Subtitle Track Selection

    func buildMPVSubtitleTrackOptions() {
        guard let mpv = mpvPlayer else {
            subtitleTrackOptions = []
            return
        }

        let names = mpv.subtitleTrackNames
        let indexes = mpv.subtitleTrackIndexes

        var options: [SubtitleTrackOption] = []

        for (index, trackID) in indexes.enumerated() {
            if trackID <= 0 { continue }

            let name = index < names.count ? names[index] : "Subtitle \(trackID)"
            let position = options.count

            options.append(
                SubtitleTrackOption(
                    id: Int(trackID),
                    position: position,
                    trackId: trackID,
                    title: name
                )
            )
        }

        subtitleTrackOptions = options
    }

    func selectSubtitleTrack(at position: Int) {
        guard useMPV, let mpv = mpvPlayer else { return }

        if position < 0 {
            mpv.disableSubtitles()
            selectedSubtitleTrackOrderIndex = -1
        } else if position < subtitleTrackOptions.count {
            let option = subtitleTrackOptions[position]
            mpv.currentSubtitleTrackIndex = option.trackId
            selectedSubtitleTrackOrderIndex = position
        }
    }

    // MARK: - Trim Points

    func setTrimIn() {
        trimIn = currentPlaybackTime
        // If trimOut exists and is before trimIn, clear it
        if let out = trimOut, let inn = trimIn, out <= inn {
            trimOut = nil
        }
    }

    func setTrimOut() {
        trimOut = currentPlaybackTime
        // If trimIn exists and is after trimOut, clear it
        if let inn = trimIn, let out = trimOut, inn >= out {
            trimIn = nil
        }
    }

    func clearTrimIn() {
        trimIn = nil
    }

    func clearTrimOut() {
        trimOut = nil
    }

    func clearTrimPoints() {
        trimIn = nil
        trimOut = nil
    }

    // MARK: - Screenshot

    func captureScreenshot() async {
        guard let item = mediaItem else { return }

        let time = currentPlaybackTime
        let stream = item.metadata?.primaryVideoStream
        let bitDepth = stream?.bitDepth ?? 8
        let hasAlpha = stream?.hasAlpha ?? false
        let format = SettingsView.selectedScreenshotFormat

        // Build output filename
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let timeString = String(format: "%.3f", time)
        let outputName = "\(baseName)_\(timestamp)_t\(timeString).\(format.fileExtension)"

        // Resolve output URL based on screenshot location mode
        let outputURL: URL
        let resolvedDir = SettingsView.resolvedScreenshotDirectory(sourceURL: item.url)

        if let dir = resolvedDir {
            // original or custom mode
            let needsSecurityScope = dir != item.url.deletingLastPathComponent()
            if needsSecurityScope { _ = dir.startAccessingSecurityScopedResource() }
            defer { if needsSecurityScope { dir.stopAccessingSecurityScopedResource() } }
            outputURL = dir.appendingPathComponent(outputName)
        } else {
            // ask mode — show save panel
            let chosenURL: URL? = await withCheckedContinuation { continuation in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = outputName
                panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension) ?? .image]
                panel.canCreateDirectories = true
                panel.directoryURL = item.url.deletingLastPathComponent()

                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

            guard let chosen = chosenURL else { return }
            outputURL = chosen
        }

        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(time),
            "-i", item.url.path,
            "-frames:v", "1",
            "-vf", "scale=iw*sar:ih",
        ]

        switch format {
        case .jxl:
            let pixelFormat: String
            if bitDepth > 8 {
                pixelFormat = hasAlpha ? "rgba64le" : "rgb48le"
            } else {
                pixelFormat = hasAlpha ? "rgba" : "rgb24"
            }
            arguments += ["-pix_fmt", pixelFormat, "-c:v", "libjxl", "-distance", "0.5", "-effort", "7"]

        case .png:
            let pixelFormat: String
            if bitDepth > 8 {
                pixelFormat = hasAlpha ? "rgba64be" : "rgb48be"
            } else {
                pixelFormat = hasAlpha ? "rgba" : "rgb24"
            }
            arguments += ["-pix_fmt", pixelFormat, "-c:v", "png"]

        case .jpeg:
            arguments += ["-pix_fmt", "yuvj444p", "-c:v", "mjpeg", "-q:v", "2"]
        }

        FFmpegService.appendColorArguments(from: stream, to: &arguments)

        arguments += ["-y", outputURL.path]

        isSavingScreenshot = true
        screenshotDone = false

        do {
            try await FFmpegService.run(arguments: arguments)
            isSavingScreenshot = false
            if FileManager.default.fileExists(atPath: outputURL.path) {
                lastScreenshotURL = outputURL
                logger.info("Screenshot saved: \(outputURL.lastPathComponent)")
                screenshotDone = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    screenshotDone = false
                }
            } else {
                logger.error("Screenshot output file missing")
            }
        } catch {
            isSavingScreenshot = false
            logger.error("Screenshot failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Trim Export

    func exportTrim() async {
        guard let item = mediaItem else { return }
        guard let inPoint = trimIn, let outPoint = trimOut, outPoint > inPoint else {
            logger.warning("Export requires both trim in and out points")
            return
        }

        let duration = outPoint - inPoint
        let ext = item.url.pathExtension
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let defaultName = "\(baseName)_trimmed.\(ext)"

        // Resolve output URL based on trim location mode
        let outputURL: URL
        let resolvedDir = SettingsView.resolvedTrimDirectory(sourceURL: item.url)

        if let dir = resolvedDir {
            let needsSecurityScope = dir != item.url.deletingLastPathComponent()
            if needsSecurityScope { _ = dir.startAccessingSecurityScopedResource() }
            defer { if needsSecurityScope { dir.stopAccessingSecurityScopedResource() } }
            outputURL = dir.appendingPathComponent(defaultName)
        } else {
            let chosenURL: URL? = await withCheckedContinuation { continuation in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = defaultName
                panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .movie]
                panel.canCreateDirectories = true
                panel.directoryURL = item.url.deletingLastPathComponent()

                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

            guard let chosen = chosenURL else { return }
            outputURL = chosen
        }

        let arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(inPoint),
            "-i", item.url.path,
            "-t", String(duration),
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            "-y", outputURL.path,
        ]

        isExportingTrim = true
        trimExportDone = false

        do {
            try await FFmpegService.run(arguments: arguments)
            isExportingTrim = false
            if FileManager.default.fileExists(atPath: outputURL.path) {
                logger.info("Trim export saved: \(outputURL.lastPathComponent)")
                trimExportDone = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    trimExportDone = false
                }
            } else {
                logger.error("Trim export output file missing")
            }
        } catch {
            isExportingTrim = false
            logger.error("Trim export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Teardown

    func teardown(resetAudioSelection: Bool = true) {
        player?.pause()
        player = nil

        if let mpv = mpvPlayer {
            mpv.stop()
            mpvPlayer = nil
        }
        useMPV = false

        isPreparing = false
        videoAspectRatio = nil
        mpvAspectRatioCancellable = nil
        removeLoopObserver()
        removePlaybackTimeObserver()
        removePlayerItemStatusObserver()
        removeMPVLoopObserver()
        if resetAudioSelection {
            selectedAudioTrackOrderIndex = 0
            selectedSubtitleTrackOrderIndex = -1
        }
        audioTrackOptions = []
        subtitleTrackOptions = []
    }
}
