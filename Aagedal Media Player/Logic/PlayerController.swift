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

    struct ChapterOption: Identifiable, Equatable {
        let id: Int
        let position: Int
        let time: Double
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
    @Published private(set) var isReversing: Bool = false
    @Published var audioTrackOptions: [AudioTrackOption] = []
    @Published var subtitleTrackOptions: [SubtitleTrackOption] = []
    @Published var chapterOptions: [ChapterOption] = []

    var currentChapterPosition: Int? {
        guard !chapterOptions.isEmpty else { return nil }
        let t = currentPlaybackTime
        return chapterOptions.last(where: { $0.time <= t + 0.001 })?.position
    }
    @Published var videoAspectRatio: CGFloat?
    @Published var videoSourceSize: NSSize?

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
    @Published var trimExportCancelling = false
    @Published var trimExportCancelled = false
    @Published var trimExportWarning: String?
    /// Export progress fraction 0...1 for re-encoding formats, nil when preparing.
    @Published var trimExportProgress: Double?
    private var exportHandle: FFmpegHandle?

    // Reverse playback
    private var reverseSpeed: Int = 1
    private let slowSteps: [Float] = [0.75, 0.5, 0.25, 0.1]
    private var reverseTimer: Timer?
    var isNativeReverse: Bool = false
    var canNativeReverse: Bool = false
    var canNativeSlowReverse: Bool = false

    /// Effective video frame rate (falls back to 30 if metadata is unavailable).
    private var effectiveFPS: Double {
        if let fr = mediaItem?.metadata?.primaryVideoStream?.frameRate,
           let v = fr.value, v > 0 { return v }
        return 30.0
    }

    // MARK: - State

    @Published var mediaItem: MediaItem?
    var loopObserver: Any?
    var playbackTimeObserver: Any?
    weak var playbackTimeObserverOwner: AVPlayer?
    var playerItemStatusObserver: Any?
    var timeControlStatusObserver: NSKeyValueObservation?
    weak var playerView: AVPlayerView?
    @Published var selectedAudioTrackOrderIndex: Int = 0
    @Published var showAllMonoWaveforms: Bool = UserDefaults.standard.bool(forKey: SettingsView.showAllMonoWaveformsKey)
    var selectedSubtitleTrackOrderIndex: Int = -1

    // MARK: - MPV State
    var mpvPlayer: MPVPlayer?
    var useMPV = false
    // MPV loop observer
    var mpvLoopObserverTimer: Timer?
    private var mpvAspectRatioCancellable: AnyCancellable?
    private var mpvSourceSizeCancellable: AnyCancellable?
    private var mpvGammaCancellable: AnyCancellable?
    private var mpvSigPeakCancellable: AnyCancellable?
    private var mpvIsPlayingCancellable: AnyCancellable?
    private var mpvTimePosTask: Task<Void, Never>?
    private var mpvFileLoadedTask: Task<Void, Never>?
    private var mpvDurationTask: Task<Void, Never>?

    /// Monotonically increasing counter invalidating stale async work from
    /// previous `preparePlayback` / `setupMPV` calls.
    @Published private(set) var preparationID: Int = 0

    // MARK: - Scope Frame Capture

    let frameCapture = FrameCapture()

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
            currentPlaybackTime = 0
            trimIn = nil
            trimOut = nil
            videoAspectRatio = nil
            videoSourceSize = nil
            preparePlayback(startTime: 0)
        }
    }

    func updateMetadata(_ item: MediaItem) {
        guard mediaItem?.url == item.url else { return }
        let currentTime = currentPlaybackTime
        mediaItem?.metadata = item.metadata
        mediaItem?.durationSeconds = item.durationSeconds
        mediaItem?.hasVideoStream = item.hasVideoStream

        // Update aspect ratio from container metadata (authoritative)
        if let ratio = item.videoDisplayAspectRatio, ratio.isFinite, ratio > 0 {
            videoAspectRatio = CGFloat(ratio)
        }

        // Use the metadata's resolved display dimensions directly. MetadataService
        // already accounts for non-square pixels, container display dims, and
        // rotation when populating these, so we don't need to re-derive them.
        if let stream = item.metadata?.primaryVideoStream {
            if let dw = stream.displayWidth, let dh = stream.displayHeight, dw > 0, dh > 0 {
                videoSourceSize = NSSize(width: dw, height: dh)
            } else if let codedW = stream.width, let codedH = stream.height,
                      codedW > 0, codedH > 0 {
                videoSourceSize = NSSize(width: codedW, height: codedH)
            }
        }

        // Detect HDR transfer function from metadata
        updateTransferFunction()

        // If surround audio was detected and we're on AVPlayer, switch to MPV
        if hasSurroundAudio && !hasProResVideoCodec && !useMPV {
            logger.info("Surround audio detected after metadata load, switching to MPV for \(item.url.lastPathComponent)")
            preparePlayback(startTime: currentTime, resetAudioSelection: true)
        }
    }

    /// Detect and set the HDR transfer function from video metadata.
    private func updateTransferFunction() {
        let videoStream = mediaItem?.metadata?.primaryVideoStream
        guard let colorTransfer = videoStream?.colorTransfer?.lowercased() else {
            frameCapture.transferFunction = .sdr
            frameCapture.contentPeakNits = 100
            return
        }

        if colorTransfer.contains("smpte2084") || colorTransfer == "pq" || colorTransfer.contains("st2084") {
            frameCapture.transferFunction = .pq
            // Use MaxCLL or mastering display max luminance for the peak, fall back to 1000
            let peak = peakNitsFromMetadata(videoStream, fallback: 1000)
            frameCapture.contentPeakNits = peak
            logger.info("HDR detected: PQ transfer function, peak \(peak) nits")
        } else if colorTransfer.contains("arib-std-b67") || colorTransfer == "hlg" {
            frameCapture.transferFunction = .hlg
            let peak = peakNitsFromMetadata(videoStream, fallback: 1000)
            frameCapture.contentPeakNits = peak
            logger.info("HDR detected: HLG transfer function, peak \(peak) nits")
        } else {
            frameCapture.transferFunction = .sdr
            frameCapture.contentPeakNits = 100
        }

        // If scopes are active, restart capture with the right pixel format.
        // Suppress pipeline rebuild to avoid a teardown cycle that resets transferFunction.
        if frameCapture.isCapturing {
            frameCapture.stopCapture(rebuildPipeline: false)
            frameCapture.startCapture()
        }
    }

    /// Derive peak nits from MaxCLL or mastering display max luminance metadata.
    private func peakNitsFromMetadata(_ stream: MediaMetadata.VideoStream?, fallback: Float) -> Float {
        // Prefer MaxCLL (content light level) — it's the actual content peak
        if let maxCLL = stream?.maxCLL, maxCLL > 0 {
            return snappedPeakNits(Float(maxCLL))
        }
        // Fall back to mastering display max luminance
        if let masteringMax = stream?.masteringMaxLuminance, masteringMax > 0 {
            return snappedPeakNits(Float(masteringMax))
        }
        return fallback
    }

    /// Snap a raw peak nits value up to the next standard graticule marker level.
    /// Ensures the waveform data scale and graticule markers align to a clean boundary.
    private static let graticuleMarkerNits: [Float] = [100, 203, 400, 600, 1000, 2000, 4000, 10000]

    private func snappedPeakNits(_ raw: Float) -> Float {
        for marker in Self.graticuleMarkerNits {
            if marker >= raw { return marker }
        }
        return raw  // Above 10K: use raw value
    }

    func updateLoopPlayback(_ loop: Bool) {
        mediaItem?.loopPlayback = loop
        updatePlayerActionAtEnd()
    }

    // MARK: - Playback Preparation

    /// Check if the file contains only mono audio tracks (2 or more, all single-channel).
    var isMultiMonoFile: Bool {
        guard let streams = mediaItem?.metadata?.audioStreams, streams.count >= 2 else { return false }
        return streams.allSatisfy { ($0.channels ?? 0) == 1 }
    }

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

    /// Check if the video codec is ProRes RAW (which MPV cannot decode).
    /// Detects via bayer pixel format (most reliable) or codec FourCC tags.
    private var hasProResRAWVideoCodec: Bool {
        guard let videoStream = mediaItem?.metadata?.primaryVideoStream else { return false }
        if let pixFmt = videoStream.pixelFormat?.lowercased(), pixFmt.contains("bayer") {
            return true
        }
        if let codec = videoStream.codec?.lowercased() {
            return codec.contains("aprn") || codec.contains("aprh")
        }
        return false
    }

    func preparePlayback(startTime: TimeInterval, resetAudioSelection: Bool = true) {
        let wasCapturing = frameCapture.isCapturing
        teardown(resetAudioSelection: resetAudioSelection)
        preparationID &+= 1
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
            if wasCapturing { frameCapture.startCapture() }
            return
        }

        // Honor "Always Use MPV" setting (except for ProRes RAW which MPV can't decode)
        if UserDefaults.standard.bool(forKey: "alwaysUseMPV") && !hasProResRAWVideoCodec {
            logger.info("Always Use MPV enabled, using MPV player for \(url.lastPathComponent)")
            setupMPV(url: url, startTime: startTime)
            if wasCapturing { frameCapture.startCapture() }
            return
        }

        // Try AVPlayer first
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)

        self.player = player

        // Attach video output for scope frame capture
        frameCapture.attachAVPlayer(player)
        frameCapture.onAVOutputRemoved = { [weak self] in
            guard let self else { return }
            let time = self.currentPlaybackTime
            self.preparePlayback(startTime: time, resetAudioSelection: false)
        }

        installPlayerItemStatusObserver(for: playerItem, startTime: startTime)

        self.isPreparing = false
        refreshAudioTrackOptions(playerItem: playerItem)
        refreshChapterOptions(playerItem: playerItem)

        let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)

        installLoopObserver(for: playerItem)
        installPlaybackTimeObserver(for: player)
        installTimeControlStatusObserver(for: player)
        updatePlayerActionAtEnd()

        if wasCapturing { frameCapture.startCapture() }
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

        // Attach MPV for scope frame capture (window set later by MPVVideoView)
        frameCapture.attachMPV(mpv)

        let myPrepID = preparationID

        // Sync time position
        mpvTimePosTask = Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await time in mpv.$timePos.values {
                guard !Task.isCancelled, self.preparationID == myPrepID else { break }
                self.currentPlaybackTime = time
            }
        }

        // Observe file loaded state for isReady
        mpvFileLoadedTask = Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await isLoaded in mpv.$isFileLoaded.values {
                guard !Task.isCancelled, self.preparationID == myPrepID else { break }
                if isLoaded {
                    self.isReady = true
                    break
                }
            }
        }

        // Populate duration from MPV so the timeline is usable before metadata finishes
        mpvDurationTask = Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await dur in mpv.$duration.values {
                guard !Task.isCancelled, self.preparationID == myPrepID else { break }
                if dur > 0, (self.mediaItem?.durationSeconds ?? 0) == 0 {
                    self.mediaItem?.durationSeconds = dur
                    break
                }
            }
        }

        // Forward MPV play/pause state so the UI icon stays in sync with mpv's
        // own pause property (EOF, internal pauses, errors).
        mpvIsPlayingCancellable = mpv.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPlaying = playing || self.isReversing
            }

        // Forward MPV aspect ratio and source size
        mpvAspectRatioCancellable = mpv.$videoAspectRatio
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ratio in
                self?.videoAspectRatio = ratio
            }

        mpvSourceSizeCancellable = mpv.$videoSourceSize
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                self?.videoSourceSize = size
            }

        // Forward MPV gamma for HDR detection
        mpvGammaCancellable = mpv.$videoGamma
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] gamma in
                guard let self else { return }
                let wasCapturing = self.frameCapture.isCapturing
                let videoStream = self.mediaItem?.metadata?.primaryVideoStream
                switch gamma {
                case "pq":
                    self.frameCapture.transferFunction = .pq
                    self.frameCapture.contentPeakNits = self.peakNitsFromMetadata(videoStream, fallback: 1000)
                case "hlg":
                    self.frameCapture.transferFunction = .hlg
                    self.frameCapture.contentPeakNits = self.peakNitsFromMetadata(videoStream, fallback: 1000)
                default:
                    self.frameCapture.transferFunction = .sdr
                    self.frameCapture.contentPeakNits = 100
                }
                if wasCapturing {
                    self.frameCapture.stopCapture()
                    self.frameCapture.startCapture()
                }
            }

        // Refine peak nits from MPV signal peak (only if metadata didn't provide a value)
        mpvSigPeakCancellable = mpv.$videoSigPeak
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sigPeak in
                guard let self, sigPeak > 0 else { return }
                let videoStream = self.mediaItem?.metadata?.primaryVideoStream
                // Only use sig-peak if we don't have MaxCLL or mastering luminance from metadata
                guard videoStream?.maxCLL == nil, videoStream?.masteringMaxLuminance == nil else { return }
                if self.frameCapture.transferFunction == .pq {
                    self.frameCapture.contentPeakNits = self.snappedPeakNits(Float(sigPeak * 10000))
                } else if self.frameCapture.transferFunction == .hlg {
                    self.frameCapture.contentPeakNits = self.snappedPeakNits(Float(sigPeak * 1000))
                }
            }

        // Refresh audio tracks after MPV parses the media
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.refreshAudioTrackOptions(playerItem: nil)
            self.refreshChapterOptions(playerItem: nil)
        }

        // Install MPV loop observer
        installMPVLoopObserver()
    }

    // MARK: - Unified Playback Control

    /// Resets speed to 1x and syncs playback state. Callable from extensions.
    func resetPlaybackSpeed() {
        currentPlaybackSpeed = 1.0
        syncIsPlaying()
    }

    func syncIsPlaying() {
        if useMPV {
            isPlaying = (mpvPlayer?.isPlaying ?? false) || isReversing
        } else {
            isPlaying = (player?.timeControlStatus == .playing) || isReversing
        }
    }

    func togglePlayback() {
        guard isReady else { return }

        if isReversing {
            stopReverse()
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
        stopReverse()

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
            mpv.rate = max(0.25, min(newRate, 8.0))
            currentPlaybackSpeed = mpv.rate
        } else if let player = player {
            let current = player.rate
            let step: Float = 0.5
            let newRate = forward ? current + step : current - step
            player.rate = max(0.25, min(newRate, 8.0))
            currentPlaybackSpeed = player.rate
        }
    }

    func startReverse() {
        guard isReady else { return }

        if isReversing {
            // Already reversing — speed up
            if isNativeReverse {
                // Transition from native -1x to simulation at -2x
                player?.rate = 0
                isNativeReverse = false
                reverseSpeed = 2
            } else {
                reverseSpeed = min(reverseSpeed + 1, 8)
            }
            startReverseTimer(skip: reverseSpeed)
            currentPlaybackSpeed = -Float(reverseSpeed)
            return
        }

        // First J press — start reverse
        pause()
        reverseSpeed = 1
        isReversing = true

        if !useMPV, canNativeReverse, let player = player {
            // Native AVPlayer reverse at -1x
            isNativeReverse = true
            player.rate = -1.0
            currentPlaybackSpeed = -1.0
            syncIsPlaying()
        } else {
            // Timer-based simulation (MPV or unsupported format)
            startReverseTimer(skip: reverseSpeed)
            currentPlaybackSpeed = -Float(reverseSpeed)
        }
    }

    private func startReverseTimer(skip: Int) {
        reverseTimer?.invalidate()
        let fps = effectiveFPS
        let interval = 1.0 / fps
        reverseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.currentPlaybackTime <= 0 {
                    self.stopReverse()
                    return
                }
                self.seekByFrames(-skip)
            }
        }
    }

    func stopReverse() {
        if isNativeReverse {
            player?.rate = 0
            isNativeReverse = false
        }
        reverseTimer?.invalidate()
        reverseTimer = nil
        isReversing = false
        reverseSpeed = 1
        currentPlaybackSpeed = 1.0
        syncIsPlaying()
    }

    func rewind() {
        stopReverse()
        stepRate(forward: false)
    }

    func fastForward() {
        guard isReady else { return }

        if isReversing {
            stopReverse()
            return
        }

        if useMPV, let mpv = mpvPlayer {
            if !mpv.isPlaying {
                mpv.rate = 1.0
                currentPlaybackSpeed = 1.0
                mpv.play()
                syncIsPlaying()
                return
            }
        } else if let player = player {
            if player.rate == 0 {
                player.rate = 1.0
                currentPlaybackSpeed = 1.0
                player.play()
                syncIsPlaying()
                return
            }
        }

        stepRate(forward: true)
        syncIsPlaying()
    }

    func slowForward() {
        guard isReady else { return }

        if isReversing {
            stopReverse()
        }

        let current = currentPlaybackSpeed
        let target: Float
        if current >= 1.0 || current <= 0 {
            target = slowSteps[0]
        } else if let idx = slowSteps.firstIndex(where: { abs($0 - current) < 0.01 }) {
            target = slowSteps[min(idx + 1, slowSteps.count - 1)]
        } else {
            target = slowSteps.first(where: { $0 < current }) ?? slowSteps.last!
        }

        if useMPV, let mpv = mpvPlayer {
            if !mpv.isPlaying { mpv.play() }
            mpv.rate = target
        } else if let player = player {
            if player.rate == 0 { player.play() }
            player.rate = target
        }
        currentPlaybackSpeed = target
        syncIsPlaying()
    }

    func slowReverse() {
        guard isReady else { return }

        let current = currentPlaybackSpeed
        let target: Float
        if isReversing {
            let absSpeed = abs(current)
            if let idx = slowSteps.firstIndex(where: { abs($0 - absSpeed) < 0.01 }) {
                target = slowSteps[min(idx + 1, slowSteps.count - 1)]
            } else {
                target = slowSteps[0]
            }
        } else {
            target = slowSteps[0]
        }

        // Stop any current reverse mode (native or simulation)
        if isReversing {
            if isNativeReverse {
                player?.rate = 0
                isNativeReverse = false
            }
            reverseTimer?.invalidate()
            reverseTimer = nil
        } else {
            pause()
        }

        isReversing = true
        reverseSpeed = 1

        if !useMPV, canNativeSlowReverse, let player = player {
            // Native AVPlayer slow reverse
            isNativeReverse = true
            player.rate = -target
            currentPlaybackSpeed = -target
            syncIsPlaying()
        } else {
            // Timer-based simulation
            let fps = effectiveFPS
            let interval = 1.0 / (fps * Double(target))
            reverseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.currentPlaybackTime <= 0 {
                        self.stopReverse()
                        return
                    }
                    self.seekByFrames(-1)
                }
            }
            currentPlaybackSpeed = -target
        }
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

        let wasPlaying = (player?.rate ?? 0) != 0 || (mpvPlayer?.isPlaying ?? false)
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

    // MARK: - Chapter Selection

    func refreshChapterOptions(playerItem: AVPlayerItem?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if useMPV, let mpv = mpvPlayer {
                let raw = mpv.chapters
                self.chapterOptions = raw.enumerated().map { idx, c in
                    ChapterOption(
                        id: idx,
                        position: idx,
                        time: c.time,
                        title: c.title.isEmpty ? "Chapter \(idx + 1)" : c.title
                    )
                }
            } else if let asset = playerItem?.asset {
                let langs = Locale.preferredLanguages
                let groups = (try? await asset.loadChapterMetadataGroups(
                    bestMatchingPreferredLanguages: langs)) ?? []
                var options: [ChapterOption] = []
                for (idx, group) in groups.enumerated() {
                    let start = group.timeRange.start.seconds
                    guard start.isFinite else { continue }
                    var title = "Chapter \(idx + 1)"
                    if let titleItem = group.items.first(where: {
                        $0.commonKey == .commonKeyTitle
                    }), let s = try? await titleItem.load(.stringValue), !s.isEmpty {
                        title = s
                    }
                    options.append(ChapterOption(id: idx, position: idx, time: start, title: title))
                }
                self.chapterOptions = options
            } else {
                self.chapterOptions = []
            }
        }
    }

    func jumpToChapter(at position: Int) {
        guard chapterOptions.indices.contains(position) else { return }
        seekTo(chapterOptions[position].time)
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

        let isInterlaced = stream?.isInterlaced ?? false
        let videoFilter = isInterlaced
            ? "bwdif=mode=0:parity=-1:deint=all,scale=iw*sar:ih"
            : "scale=iw*sar:ih"

        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(time),
            "-i", item.url.path,
            "-frames:v", "1",
            "-vf", videoFilter,
        ]

        switch format {
        case .jxl:
            let pixelFormat: String
            if bitDepth > 8 {
                pixelFormat = hasAlpha ? "rgba64le" : "rgb48le"
            } else {
                pixelFormat = hasAlpha ? "rgba" : "rgb24"
            }
            let jxlQuality = UserDefaults.standard.double(forKey: SettingsView.screenshotJXLQualityKey).clamped(to: 0...100, default: 90)
            let distance = (100 - jxlQuality) / 100.0 * 15.0
            arguments += ["-pix_fmt", pixelFormat, "-c:v", "libjxl", "-distance", String(format: "%.2f", distance), "-effort", "7"]

        case .png:
            let pixelFormat: String
            if bitDepth > 8 {
                pixelFormat = hasAlpha ? "rgba64be" : "rgb48be"
            } else {
                pixelFormat = hasAlpha ? "rgba" : "rgb24"
            }
            arguments += ["-pix_fmt", pixelFormat, "-c:v", "png"]

        case .jpeg:
            let jpegQuality = UserDefaults.standard.double(forKey: SettingsView.screenshotJPEGQualityKey).clamped(to: 0...100, default: 90)
            let qv = 1.0 + (100 - jpegQuality) / 100.0 * 30.0
            arguments += ["-pix_fmt", "yuvj444p", "-c:v", "mjpeg", "-q:v", String(format: "%.1f", qv)]
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
            let missing = trimIn == nil && trimOut == nil ? "Set trim in and out points first."
                : trimIn == nil ? "Set a trim in point first."
                : trimOut == nil ? "Set a trim out point first."
                : "Trim out must be after trim in."
            logger.warning("Export requires both trim in and out points")
            trimExportWarning = missing
            Task {
                try? await Task.sleep(for: .seconds(2))
                trimExportWarning = nil
            }
            return
        }

        let format = SettingsView.selectedTrimExportFormat
        let duration = outPoint - inPoint
        let originalExt = item.url.pathExtension
        let ext = format.fileExtension ?? originalExt
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

        let formatArguments: [String]
        switch format {
        case .copy:
            formatArguments = buildCopyArguments()
        case .gif:
            formatArguments = buildGIFArguments()
        case .animatedAVIF:
            formatArguments = buildAnimatedAVIFArguments()
        case .hardwareH264:
            formatArguments = buildH264Arguments()
        case .hardwareH265:
            formatArguments = buildH265Arguments()
        }

        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(inPoint),
            "-i", item.url.path,
            "-t", String(duration),
        ]
        arguments += formatArguments
        arguments += ["-y", outputURL.path]

        isExportingTrim = true
        trimExportDone = false
        trimExportCancelling = false
        trimExportCancelled = false
        trimExportProgress = nil

        let handle = FFmpegHandle()
        exportHandle = handle

        let progressCallback: (@Sendable (Double) -> Void)?
        if format != .copy {
            progressCallback = { [weak self] fraction in
                let _ = Task { @MainActor [weak self] in
                    self?.trimExportProgress = fraction
                }
            }
        } else {
            progressCallback = nil
        }

        do {
            try await FFmpegService.run(
                arguments: arguments,
                duration: format != .copy ? duration : nil,
                onProgress: progressCallback,
                handle: handle
            )
            exportHandle = nil
            isExportingTrim = false
            trimExportProgress = nil
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
        } catch let error as FFmpegError where error == .cancelled {
            exportHandle = nil
            isExportingTrim = false
            trimExportProgress = nil
            trimExportCancelling = false
            // Clean up partial output file
            try? FileManager.default.removeItem(at: outputURL)
            logger.info("Trim export cancelled")
            trimExportCancelled = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                trimExportCancelled = false
            }
        } catch {
            exportHandle = nil
            isExportingTrim = false
            trimExportCancelling = false
            trimExportProgress = nil
            logger.error("Trim export failed: \(error.localizedDescription)")
        }
    }

    func cancelExport() {
        trimExportCancelling = true
        trimExportProgress = nil
        exportHandle?.cancel()
    }

    // MARK: - Export Argument Builders

    private func buildCopyArguments() -> [String] {
        ["-c", "copy", "-avoid_negative_ts", "make_zero"]
    }

    private func scaleFilter(forKey key: String, default defaultPreset: ExportWidthPreset) -> String? {
        let widthRaw = UserDefaults.standard.integer(forKey: key)
        let preset = ExportWidthPreset(rawValue: widthRaw) ?? defaultPreset
        guard preset != .original else { return nil }
        let s = preset.rawValue
        // Limit the short side: if width <= height (portrait/square) scale width,
        // otherwise scale height. min() prevents upscaling; -2 keeps the other dimension even.
        return "scale='if(lte(iw,ih),min(\(s),iw),-2)':'if(lte(iw,ih),-2,min(\(s),ih))':flags=lanczos"
    }

    private func buildGIFArguments() -> [String] {
        let fps = Int(UserDefaults.standard.double(forKey: SettingsView.gifFrameRateKey).clamped(to: 5...30, default: 15))

        let scaleComponent = scaleFilter(forKey: SettingsView.gifWidthKey, default: .w720)
        let filtergraph: String
        if let scaleComponent {
            filtergraph = "fps=\(fps),\(scaleComponent),split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
        } else {
            filtergraph = "fps=\(fps),split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
        }
        return ["-vf", filtergraph, "-an"]
    }

    private func buildAnimatedAVIFArguments() -> [String] {
        let crf = Int(UserDefaults.standard.double(forKey: SettingsView.avifQualityKey).clamped(to: 0...63, default: 28))
        let speed = Int(UserDefaults.standard.double(forKey: SettingsView.avifSpeedKey).clamped(to: 0...8, default: 4))
        var args = ["-c:v", "libaom-av1", "-crf", String(crf), "-cpu-used", String(speed), "-b:v", "0", "-an"]
        if let scale = scaleFilter(forKey: SettingsView.avifWidthKey, default: .w1080) { args += ["-vf", scale] }
        return args
    }

    private func buildH264Arguments() -> [String] {
        let quality = Int(UserDefaults.standard.double(forKey: SettingsView.h264QualityKey).clamped(to: 1...100, default: 65))
        var args = ["-c:v", "h264_videotoolbox", "-q:v", String(quality), "-c:a", "aac"]
        if let scale = scaleFilter(forKey: SettingsView.h264WidthKey, default: .original) { args += ["-vf", scale] }
        return args
    }

    private func buildH265Arguments() -> [String] {
        let quality = Int(UserDefaults.standard.double(forKey: SettingsView.h265QualityKey).clamped(to: 1...100, default: 65))
        var args = ["-c:v", "hevc_videotoolbox", "-q:v", String(quality), "-c:a", "aac"]
        if let scale = scaleFilter(forKey: SettingsView.h265WidthKey, default: .original) { args += ["-vf", scale] }
        return args
    }

    // MARK: - Teardown

    func teardown(resetAudioSelection: Bool = true) {
        // Stop reverse playback first
        reverseTimer?.invalidate()
        reverseTimer = nil
        isReversing = false
        isNativeReverse = false
        canNativeReverse = false
        canNativeSlowReverse = false
        reverseSpeed = 1

        // Stop scope capture and detach backends
        frameCapture.stopCapture()
        frameCapture.detachAVPlayer()
        frameCapture.detachMPV()
        frameCapture.transferFunction = .sdr
        frameCapture.contentPeakNits = 100

        // Fully detach old AVPlayer — mute, stop, and replace item to ensure
        // no audio/video output even if the object lingers from SwiftUI caching.
        if let oldPlayer = player {
            oldPlayer.isMuted = true
            oldPlayer.rate = 0
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
        }
        // Also nil the AVPlayerView's player reference so the view layer
        // cannot resurrect audio from the old player object.
        playerView?.player = nil
        removePlaybackTimeObserver()
        removePlayerItemStatusObserver()
        removeTimeControlStatusObserver()
        removeLoopObserver()
        player = nil

        // Cancel in-flight MPV observation Tasks before stopping
        mpvTimePosTask?.cancel()
        mpvTimePosTask = nil
        mpvFileLoadedTask?.cancel()
        mpvFileLoadedTask = nil
        mpvDurationTask?.cancel()
        mpvDurationTask = nil

        if let mpv = mpvPlayer {
            mpv.destroy()
            mpvPlayer = nil
        }
        useMPV = false

        isPreparing = false
        isPlaying = false
        currentPlaybackSpeed = 1.0
        videoAspectRatio = nil
        videoSourceSize = nil
        mpvAspectRatioCancellable = nil
        mpvSourceSizeCancellable = nil
        mpvGammaCancellable = nil
        mpvSigPeakCancellable = nil
        mpvIsPlayingCancellable = nil
        removeMPVLoopObserver()
        if resetAudioSelection {
            selectedAudioTrackOrderIndex = 0
            selectedSubtitleTrackOrderIndex = -1
            showAllMonoWaveforms = UserDefaults.standard.bool(forKey: SettingsView.showAllMonoWaveformsKey)
        }
        audioTrackOptions = []
        subtitleTrackOptions = []
        chapterOptions = []
    }
}

// MARK: - Double Clamped Helper

extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        let value = self == 0 ? defaultValue : self
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
