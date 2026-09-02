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

@MainActor
final class PlayerController: ObservableObject {
    typealias AudioTrackOption = TrackSelectionController.AudioTrackOption
    typealias SubtitleTrackOption = TrackSelectionController.SubtitleTrackOption
    typealias ChapterOption = TrackSelectionController.ChapterOption

    // MARK: - Published State

    @Published var volume: Double = 100 {
        didSet {
            let clampedVolume = volume.clamped(to: 0...100, default: 100)
            if volume != clampedVolume {
                volume = clampedVolume
                return
            }
            UserDefaults.standard.set(volume, for: AppSettings.playbackVolume)
            backendAdapter?.volume = volume
        }
    }
    @Published var isMuted: Bool = false {
        didSet {
            UserDefaults.standard.set(isMuted, for: AppSettings.playbackMuted)
            backendAdapter?.isMuted = isMuted
        }
    }
    var player: AVPlayer? { backendAdapter?.avPlayer }
    @Published private(set) var playbackPhase: PlaybackPhase = .idle
    var isPreparing: Bool { playbackPhase == .preparing }
    var isReady: Bool { playbackPhase.permitsPlaybackControls }
    var playbackFailure: PlaybackFailure? { playbackPhase.failure }
    @Published var currentPlaybackTime: Double = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentPlaybackSpeed: Float = 1.0
    @Published private(set) var isReversing: Bool = false
    private let trackSelection = TrackSelectionController()
    private var trackSelectionCancellable: AnyCancellable?
    var audioTrackOptions: [AudioTrackOption] { trackSelection.audioTrackOptions }
    var subtitleTrackOptions: [SubtitleTrackOption] { trackSelection.subtitleTrackOptions }
    var chapterOptions: [ChapterOption] { trackSelection.chapterOptions }
    var selectedAudioTrackOrderIndex: Int { trackSelection.selectedAudioTrackOrderIndex }
    var selectedSubtitleTrackOrderIndex: Int { trackSelection.selectedSubtitleTrackOrderIndex }

    var currentChapterPosition: Int? {
        guard !chapterOptions.isEmpty else { return nil }
        let t = currentPlaybackTime
        return chapterOptions.last(where: { $0.time <= t + 0.001 })?.position
    }
    @Published var videoAspectRatio: CGFloat?
    @Published var videoSourceSize: NSSize?

    // Media operation state is owned by a focused coordinator. These computed
    // properties preserve the existing view-facing PlayerController API.
    private let mediaOperations = MediaOperationsController()
    private var mediaOperationsCancellable: AnyCancellable?
    var trimIn: Double? { mediaOperations.trimIn }
    var trimOut: Double? { mediaOperations.trimOut }
    var screenshotState: ScreenshotOperationState { mediaOperations.screenshotState }
    var trimExportState: TrimExportOperationState { mediaOperations.trimExportState }

    // Reverse playback
    private var reverseSpeed: Int = 1
    private let slowSteps: [Float] = [0.75, 0.5, 0.25, 0.1]
    private var reverseTimer: Timer?
    var isNativeReverse: Bool = false
    var canNativeReverse: Bool = false
    var canNativeSlowReverse: Bool = false

    // Interactive scrubbing. Pointer events can arrive much faster than a
    // decoder can complete seeks, so keep only the newest requested position.
    private var pendingScrubTime: TimeInterval?
    private var mpvScrubThrottleTask: Task<Void, Never>?
    private var avPlayerScrubSeekInProgress = false
    private var scrubGeneration = 0
    private static let mpvScrubIntervalNanoseconds: UInt64 = 33_333_333

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
    var playbackFailureObserver: Any?
    var timeControlStatusObserver: NSKeyValueObservation?
    weak var playerView: AVPlayerView?
    @Published var showAllMonoWaveforms = UserDefaults.standard.value(for: AppSettings.showAllMonoWaveforms)

    // MARK: - Playback Backend State
    @Published private var backendAdapter: (any PlayerBackendAdapter)?
    var mpvPlayer: MPVPlayer? { backendAdapter?.mpvPlayer }
    var useMPV: Bool { backendAdapter?.backend == .mpv }
    // MPV loop observer
    var mpvLoopObserverTimer: Timer?
    private var mpvAspectRatioCancellable: AnyCancellable?
    private var mpvSourceSizeCancellable: AnyCancellable?
    private var mpvGammaCancellable: AnyCancellable?
    private var mpvSigPeakCancellable: AnyCancellable?
    private var mpvIsPlayingCancellable: AnyCancellable?
    private var mpvBackwardFailureCancellable: AnyCancellable?
    private var mpvErrorCancellable: AnyCancellable?
    private var mpvBusyCancellable: AnyCancellable?

    /// URLs where mpv's native `play-direction=backward` has previously
    /// failed (it emits "Backward playback is likely stuck/broken now."
    /// for files it can't handle — typically high-bitrate HEVC rips with
    /// mid-stream PPS changes). On subsequent reverse attempts for these
    /// files we skip native backward and go straight to the timer-based
    /// seek simulation. Kept in-memory only; cleared on relaunch.
    private var nativeReverseFailedURLs: Set<URL> = []
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

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.value(for: AppSettings.playbackVolume)
            .clamped(to: 0...100, default: AppSettings.playbackVolume.defaultValue)
        isMuted = defaults.value(for: AppSettings.playbackMuted)
        mediaOperationsCancellable = mediaOperations.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        trackSelectionCancellable = trackSelection.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Media Item Management

    /// Load a new media item.
    ///
    /// Seeds `videoAspectRatio` / `videoSourceSize` from `item.metadata` so
    /// the SwiftUI tree around the new MPVViewController (WindowConfigurator
    /// + PlayerView's aspect modifier) has the correct values on the first
    /// render and mpv builds its Vulkan swapchain at the right size from
    /// frame 1. openFile awaits SwiftMediaMetadata results before calling this so
    /// the metadata path is the normal case; on the 500 ms timeout fallback
    /// the values land later via updateMetadata.
    func loadMedia(_ item: MediaItem) {
        let previousURL = mediaItem?.url
        mediaItem = item

        // Always prepare if it's a new file, or if it's the first load
        if previousURL != item.url || !isReady {
            currentPlaybackTime = 0
            mediaOperations.clearTrimPoints()

            // Aspect ratio from MetadataMapper's resolved DAR.
            if let ratio = item.videoDisplayAspectRatio, ratio.isFinite, ratio > 0 {
                videoAspectRatio = CGFloat(ratio)
            } else {
                videoAspectRatio = nil
            }

            // Source size: prefer MetadataMapper's display dims (post-PAR,
            // post-rotation), fall back to coded dims.
            if let stream = item.metadata?.primaryVideoStream {
                if let dw = stream.displayWidth, let dh = stream.displayHeight, dw > 0, dh > 0 {
                    videoSourceSize = NSSize(width: dw, height: dh)
                } else if let codedW = stream.width, let codedH = stream.height,
                          codedW > 0, codedH > 0 {
                    videoSourceSize = NSSize(width: codedW, height: codedH)
                } else {
                    videoSourceSize = nil
                }
            } else {
                videoSourceSize = nil
            }

            preparePlayback(startTime: 0)
        }
    }

    func updateMetadata(_ item: MediaItem) {
        guard mediaItem?.url == item.url else { return }
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

    /// Determine whether `url` points to a ProRes RAW file. Backend selection
    /// normally has SwiftMediaMetadata results available because openFile awaits them
    /// before loadMedia, but the 500 ms timeout fallback path lets the file
    /// open without metadata — for that case we fall back to querying
    /// AVAsset's CMFormatDescription directly for the codec FourCC.
    ///
    /// MPVKit-GPL can technically decode ProRes RAW, but the result has
    /// incorrect colors and significantly worse playback performance than
    /// VideoToolbox via AVPlayer, so we always route ProRes RAW to AVPlayer.
    private static func isProResRAWFile(url: URL, metadata: MediaMetadata?) async -> Bool {
        // Fast path: metadata is already loaded (Force Reload, re-drag of the
        // same file, etc.).
        if let backend = PlaybackBackendSelector.backend(metadata: metadata) {
            return backend == .avFoundation
        }

        // Slow path: ask AVAsset for the video track's codec FourCC.
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return false }
            let formatDescs = try await track.load(.formatDescriptions)
            guard let formatDesc = formatDescs.first else { return false }
            let subtype = CMFormatDescriptionGetMediaSubType(formatDesc)
            // FourCC: 'aprn' = ProRes RAW, 'aprh' = ProRes RAW HQ
            let aprn: FourCharCode = 0x6170726E
            let aprh: FourCharCode = 0x61707268
            return subtype == aprn || subtype == aprh
        } catch {
            return false
        }
    }

    func preparePlayback(startTime: TimeInterval, resetAudioSelection: Bool = true) {
        let wasCapturing = frameCapture.isCapturing
        teardown(resetAudioSelection: resetAudioSelection)
        preparationID &+= 1
        let myPrepID = preparationID
        playbackPhase = .preparing

        guard let item = mediaItem else {
            playbackPhase = .idle
            return
        }

        let url = item.url
        let cachedMetadata = item.metadata

        // Backend selection has to happen *after* a codec check, because
        // ProRes RAW must go to AVPlayer (VideoToolbox) while everything else
        // goes to MPV. openFile normally awaits SwiftMediaMetadata results before
        // calling loadMedia, so the cached metadata fast path covers the
        // common case; the async helper falls back to a fast AVAsset
        // CMFormatDescription FourCC check for the 500 ms-timeout path.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let isProResRAW = await PlayerController.isProResRAWFile(url: url, metadata: cachedMetadata)
            // A newer preparePlayback may have superseded this one.
            guard self.preparationID == myPrepID else { return }

            if isProResRAW {
                self.logger.info("ProRes RAW detected, using AVPlayer for \(url.lastPathComponent)")
                self.setupAVPlayer(url: url, startTime: startTime, wasCapturing: wasCapturing)
            } else {
                self.logger.info("Using MPV player for \(url.lastPathComponent)")
                self.setupMPV(url: url, startTime: startTime)
                if wasCapturing { self.frameCapture.startCapture() }
            }
        }
    }

    /// AVPlayer-backed setup path. Used only for ProRes RAW (which mpv decodes
    /// with wrong colors and worse performance than VideoToolbox).
    private func setupAVPlayer(url: URL, startTime: TimeInterval, wasCapturing: Bool) {
        playbackPhase = .preparing
        let backend = AVFoundationPlayerBackend(url: url, volume: volume, isMuted: isMuted)
        backendAdapter = backend
        let player = backend.player
        guard let playerItem = player.currentItem else {
            reportPlaybackFailure(
                backend: .avFoundation,
                stage: .initialization,
                message: "AVFoundation could not create a player item."
            )
            return
        }

        // Attach video output for scope frame capture
        frameCapture.attachAVPlayer(player)
        frameCapture.onAVOutputRemoved = { [weak self] in
            guard let self else { return }
            let time = self.currentPlaybackTime
            self.preparePlayback(startTime: time, resetAudioSelection: false)
        }

        installPlayerItemStatusObserver(for: playerItem, startTime: startTime)

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
        playbackPhase = .preparing
        let backend = MPVPlayerBackend(
            url: url,
            startTime: startTime,
            volume: volume,
            isMuted: isMuted
        )
        backendAdapter = backend
        let mpv = backend.player

        // Attach MPV for scope frame capture (window set later by MPVVideoView)
        frameCapture.attachMPV(mpv)

        let myPrepID = preparationID
        let observationIdentity = MPVPlaybackObservationIdentity(
            preparationID: myPrepID,
            player: mpv
        )

        // Sync time position
        mpvTimePosTask = Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await time in mpv.$timePos.values {
                guard !Task.isCancelled,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { break }
                self.currentPlaybackTime = time
            }
        }

        // Observe file loaded state for the controller's typed playback phase.
        mpvFileLoadedTask = Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await isLoaded in mpv.$isFileLoaded.values {
                guard !Task.isCancelled,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { break }
                if isLoaded {
                    guard self.playbackFailure == nil else { break }
                    self.markPlaybackReady(isBuffering: mpv.isBusy)
                    break
                }
            }
        }

        mpvErrorCancellable = mpv.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] message in
                guard let self, let mpv,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
                self.reportPlaybackFailure(
                    backend: .mpv,
                    stage: mpv.errorStage,
                    message: message
                )
            }

        mpvBusyCancellable = mpv.$isBusy
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] busy in
                guard let self, let mpv,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ), mpv.isFileLoaded else { return }
                self.updateBufferingState(busy)
            }

        // Populate duration from MPV so the timeline is usable before metadata finishes
        mpvDurationTask = Task { @MainActor [weak self, weak mpv] in
            guard let self, let mpv else { return }
            for await dur in mpv.$duration.values {
                guard !Task.isCancelled,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { break }
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
            .sink { [weak self, weak mpv] playing in
                guard let self, mpv != nil,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
                self.isPlaying = playing || self.isReversing
            }

        // Forward MPV aspect ratio and source size
        mpvAspectRatioCancellable = mpv.$videoAspectRatio
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] ratio in
                guard let self, mpv != nil,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
                self.videoAspectRatio = ratio
            }

        mpvSourceSizeCancellable = mpv.$videoSourceSize
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] size in
                guard let self, mpv != nil,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
                self.videoSourceSize = size
            }

        // mpv tells us when its experimental backward-playback algorithm
        // gives up; switch the current reverse session to timer simulation
        // and remember this URL so subsequent reverses go straight there.
        mpvBackwardFailureCancellable = mpv.backwardPlaybackFailed
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] in
                guard let self, mpv != nil,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
                self.handleNativeBackwardFailure()
            }

        // Forward MPV gamma for HDR detection
        mpvGammaCancellable = mpv.$videoGamma
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mpv] gamma in
                guard let self, mpv != nil,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
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
            .sink { [weak self, weak mpv] sigPeak in
                guard let self, mpv != nil, sigPeak > 0,
                      observationIdentity.matches(
                          preparationID: self.preparationID,
                          player: self.mpvPlayer
                      ) else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak mpv] in
            guard let self, let mpv,
                  observationIdentity.matches(
                      preparationID: self.preparationID,
                      player: self.mpvPlayer
                  ) else { return }
            self.refreshAudioTrackOptions(playerItem: nil)
            self.refreshChapterOptions(playerItem: nil)
        }

        // Install MPV loop observer
        installMPVLoopObserver()
    }

    func markPlaybackReady(isBuffering: Bool) {
        guard playbackFailure == nil else { return }
        playbackPhase = isBuffering ? .buffering : .ready
    }

    func updateBufferingState(_ isBuffering: Bool) {
        switch playbackPhase {
        case .ready, .buffering:
            playbackPhase = isBuffering ? .buffering : .ready
        case .idle, .preparing, .failed:
            break
        }
    }

    func reportPlaybackFailure(
        backend: PlaybackBackend,
        stage: PlaybackFailureStage,
        message: String
    ) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = PlaybackFailure(
            backend: backend,
            stage: stage,
            message: normalizedMessage.isEmpty ? "An unknown playback error occurred." : normalizedMessage,
            mediaURL: mediaItem?.url
        )
        logger.error("\(failure.diagnosticText, privacy: .public)")
        reverseTimer?.invalidate()
        reverseTimer = nil
        isReversing = false
        isNativeReverse = false
        backendAdapter?.pause()
        playbackPhase = .failed(failure)
        isPlaying = false
    }

    // MARK: - Unified Playback Control

    /// Resets speed to 1x and syncs playback state. Callable from extensions.
    func resetPlaybackSpeed() {
        currentPlaybackSpeed = 1.0
        syncIsPlaying()
    }

    func syncIsPlaying() {
        isPlaying = (backendAdapter?.isPlaying ?? false) || isReversing
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func adjustVolume(by delta: Double) {
        volume = (volume + delta).clamped(to: 0...100, default: 100)
        if volume > 0 {
            isMuted = false
        }
    }

    func togglePlayback() {
        guard isReady else { return }
        logPlaybackTransition("togglePlayback")

        if isReversing {
            stopReverse()
            return
        }

        if let backendAdapter {
            let wasPaused = backendAdapter.isPaused
            backendAdapter.rate = 1.0
            currentPlaybackSpeed = 1.0

            if wasPaused {
                backendAdapter.play()
            } else {
                backendAdapter.pause()
            }
        }
        syncIsPlaying()
    }

    func pause() {
        logPlaybackTransition("pause")
        stopReverse()

        if let backendAdapter {
            backendAdapter.rate = 1.0
            currentPlaybackSpeed = 1.0
            backendAdapter.pause()
        }
        syncIsPlaying()
    }

    func play() {
        guard isReady else { return }
        logPlaybackTransition("play")

        if let backendAdapter {
            backendAdapter.rate = 1.0
            currentPlaybackSpeed = 1.0
            backendAdapter.play()
        }
        syncIsPlaying()
    }

    /// Diagnostic: emit a `scaling` event when a play/pause transition is
    /// requested. Captures the current controller-tracked source size and
    /// aspect ratio so we can correlate "fullscreen → play causes 1:1
    /// collapse" with the state at the moment of play.
    private func logPlaybackTransition(_ source: String) {
        let size = videoSourceSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
        let ratio = videoAspectRatio.map { String(format: "%.4f", Double($0)) } ?? "nil"
        scalingLogger.info("\(source): backend=\(self.useMPV ? "mpv" : "av") wasPlaying=\(self.isPlaying) videoSourceSize=\(size) ratio=\(ratio)")
    }

    func stepRate(forward: Bool) {
        if let backendAdapter {
            let current = backendAdapter.rate
            let step: Float = 0.5
            let newRate = forward ? current + step : current - step
            backendAdapter.rate = max(0.25, min(newRate, 8.0))
            currentPlaybackSpeed = backendAdapter.rate
        }
    }

    func startReverse() {
        guard isReady else { return }

        if isReversing {
            // Already reversing — speed up
            let wasAVNative = isNativeReverse
            if isNativeReverse {
                // Transition from native AVPlayer -1x to simulation at -2x
                player?.rate = 0
                isNativeReverse = false
                reverseSpeed = 2
            } else {
                reverseSpeed = min(reverseSpeed + 1, 8)
            }
            // MPV native backward mode iff: MPV backend, no timer running,
            // not coming from AVPlayer native. Everything else uses the timer.
            if useMPV && reverseTimer == nil && !wasAVNative {
                mpvPlayer?.rate = Float(reverseSpeed)
            } else {
                startReverseTimer(speed: Float(reverseSpeed))
            }
            currentPlaybackSpeed = -Float(reverseSpeed)
            return
        }

        // First J press — start reverse
        pause()
        reverseSpeed = 1
        isReversing = true

        let url = mediaItem?.url
        let shouldUseNative = useMPV && !(url.map { nativeReverseFailedURLs.contains($0) } ?? false)

        if shouldUseNative, let mpv = mpvPlayer {
            // MPV native backward playback. Decoder runs forward into the
            // reversal buffer (configured in setupMPV) and frames are emitted
            // in reverse — no backward seeks, no decoder reference-picture
            // failures on long-GOP files.
            mpv.setPlayDirection("backward")
            mpv.rate = Float(reverseSpeed)
            mpv.play()
            currentPlaybackSpeed = -Float(reverseSpeed)
            syncIsPlaying()
        } else if !useMPV, canNativeReverse, let player = player {
            // Native AVPlayer reverse at -1x (ProRes RAW backend)
            isNativeReverse = true
            player.rate = -1.0
            currentPlaybackSpeed = -1.0
            syncIsPlaying()
        } else {
            // Timer-based seek simulation. Used for the AVPlayer-without-
            // native-reverse edge case, and as the fallback for MPV files
            // where mpv's experimental backward playback is known to fail.
            startReverseTimer(speed: Float(reverseSpeed))
            currentPlaybackSpeed = -Float(reverseSpeed)
        }
    }

    /// Drive reverse playback by ticking a timer at ~15 Hz minimum (capped at
    /// the source fps) and seeking backward by `speed / H` seconds per tick.
    /// Decouples UI refresh rate from playback speed so the timecode stays
    /// responsive at slow speeds, while keeping seek frequency reasonable at
    /// high speeds.
    private func startReverseTimer(speed: Float) {
        reverseTimer?.invalidate()
        let fps = effectiveFPS
        let absSpeed = Double(abs(speed))
        let minHz: Double = 15.0
        let idealHz = absSpeed * fps
        let H = max(minHz, min(fps, idealHz))
        let interval = 1.0 / H
        let secondsPerTick = absSpeed / H

        reverseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.currentPlaybackTime <= 0 {
                    self.stopReverse()
                    return
                }
                self.seek(by: -secondsPerTick)
            }
        }
    }

    func stopReverse() {
        if isNativeReverse {
            player?.rate = 0
            isNativeReverse = false
        }
        let wasReversing = isReversing
        // If a timer is running we were in seek-simulation mode (MPV stayed
        // forward+paused); only the MPV native path needs direction reset.
        let wasNativeBackward = wasReversing && useMPV && reverseTimer == nil
        reverseTimer?.invalidate()
        reverseTimer = nil
        isReversing = false
        reverseSpeed = 1
        currentPlaybackSpeed = 1.0
        if wasNativeBackward, let mpv = mpvPlayer {
            // Return MPV to forward playback and pause on the current frame
            // so the user lands cleanly rather than continuing backward.
            mpv.pause()
            mpv.setPlayDirection("forward")
            mpv.rate = 1.0
        }
        syncIsPlaying()
    }

    /// Invoked when mpv's backward-playback algorithm publishes a failure.
    /// Tears down the native-backward state, blacklists the URL so future
    /// reverse attempts skip native mode, and continues the current reverse
    /// session via the timer-based seek simulation.
    private func handleNativeBackwardFailure() {
        // Only relevant if we're currently reverse-playing via native mode.
        guard isReversing, useMPV, reverseTimer == nil, let mpv = mpvPlayer else { return }
        if let url = mediaItem?.url {
            nativeReverseFailedURLs.insert(url)
            logger.warning("MPV backward playback failed on \(url.lastPathComponent); using timer-based reverse for this file.")
        }
        // Return MPV to forward + paused so seeks from the timer don't fight
        // a half-stuck backward direction.
        mpv.pause()
        mpv.setPlayDirection("forward")
        mpv.rate = 1.0
        // Continue reversing at the current speed via the seek simulation.
        let absSpeed = abs(currentPlaybackSpeed)
        startReverseTimer(speed: absSpeed)
    }

    func rewind() {
        stopReverse()
        stepRate(forward: false)
    }

    func fastForward() {
        guard isReady else { return }

        // L during reverse: instantly switch direction (Resolve/Premiere
        // J↔L behavior). Call play() explicitly rather than falling through
        // because mpv's @Published isPlaying is updated async by the event
        // observer — checking it right after pause() reads the stale "true"
        // and the fall-through would mistakenly take the "already playing,
        // bump speed" branch (showing 1.5x while mpv is actually paused).
        if isReversing {
            stopReverse()
            play()
            return
        }

        if let backendAdapter {
            if backendAdapter.isPaused {
                backendAdapter.rate = 1.0
                currentPlaybackSpeed = 1.0
                backendAdapter.play()
                syncIsPlaying()
                return
            }
        }

        stepRate(forward: true)
        syncIsPlaying()
    }

    func slowForward() {
        guard isReady else { return }

        let wasReversing = isReversing
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

        // Same stale-isPlaying race as fastForward: just exited reverse means
        // mpv was actually playing (backward) and the pause hasn't propagated
        // to @Published isPlaying yet, so we can't trust the conditional play.
        if let backendAdapter {
            if wasReversing || backendAdapter.isPaused { backendAdapter.play() }
            backendAdapter.rate = target
        }
        currentPlaybackSpeed = target
        syncIsPlaying()
    }

    func slowReverse() {
        guard isReady else { return }

        let wasReversing = isReversing
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

        let url = mediaItem?.url
        let inFailedSet = url.map { nativeReverseFailedURLs.contains($0) } ?? false
        // If we were already reversing via the timer (after a fallback), stay
        // there. Otherwise, use MPV native if available and not blacklisted.
        let useTimer = (reverseTimer != nil && wasReversing) || inFailedSet
        let useNative = useMPV && !useTimer

        if useNative, let mpv = mpvPlayer {
            // MPV native backward playback at fractional speed.
            if !wasReversing {
                mpv.setPlayDirection("backward")
            }
            mpv.rate = target
            mpv.play()
            currentPlaybackSpeed = -target
            syncIsPlaying()
        } else if !useMPV, canNativeSlowReverse, let player = player {
            // Native AVPlayer slow reverse
            isNativeReverse = true
            player.rate = -target
            currentPlaybackSpeed = -target
            syncIsPlaying()
        } else {
            // Timer simulation fallback
            startReverseTimer(speed: target)
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

    /// Preview a position during an interactive drag without flooding the
    /// playback backend with more work than it can display.
    func scrub(to time: Double) {
        guard isReady, time.isFinite else { return }

        currentPlaybackTime = time
        pendingScrubTime = time

        if useMPV {
            issuePendingMPVScrubSeek()
        } else {
            issuePendingAVPlayerScrubSeek()
        }
    }

    /// Finish an interactive drag with a frame-accurate seek.
    func endScrubbing(at time: Double) {
        seekTo(time)
    }

    func seekTo(_ time: Double) {
        cancelPendingScrubSeeks()
        guard isReady, time.isFinite else { return }

        currentPlaybackTime = time

        backendAdapter?.seek(to: time)
    }

    private func issuePendingMPVScrubSeek() {
        guard mpvScrubThrottleTask == nil,
              let time = pendingScrubTime,
              let mpv = mpvPlayer else { return }

        pendingScrubTime = nil
        mpv.seekForScrubbing(to: time)

        mpvScrubThrottleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.mpvScrubIntervalNanoseconds)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            self.mpvScrubThrottleTask = nil
            self.issuePendingMPVScrubSeek()
        }
    }

    /// AVFoundation recommends serializing rapid seek requests and "chasing"
    /// only the newest target once the in-flight seek completes.
    private func issuePendingAVPlayerScrubSeek() {
        guard !avPlayerScrubSeekInProgress,
              let time = pendingScrubTime,
              let player else { return }

        pendingScrubTime = nil
        avPlayerScrubSeekInProgress = true
        let generation = scrubGeneration
        let seekTime = CMTime(seconds: time, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1.0 / effectiveFPS, preferredTimescale: 600)

        player.seek(
            to: seekTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self, weak player] in
                guard let self,
                      let player,
                      self.player === player,
                      self.scrubGeneration == generation else { return }

                self.avPlayerScrubSeekInProgress = false
                self.issuePendingAVPlayerScrubSeek()
            }
        }
    }

    private func cancelPendingScrubSeeks() {
        scrubGeneration &+= 1
        pendingScrubTime = nil
        mpvScrubThrottleTask?.cancel()
        mpvScrubThrottleTask = nil

        if avPlayerScrubSeekInProgress {
            player?.currentItem?.cancelPendingSeeks()
            avPlayerScrubSeekInProgress = false
        }
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
        Task { @MainActor [weak self] in
            guard let self, let item = self.mediaItem else { return }
            await self.trackSelection.refreshAudioTrackOptions(
                mediaItem: item,
                playerItem: playerItem,
                mpvPlayer: self.mpvPlayer,
                useMPV: self.useMPV
            )
        }
    }

    func selectAudioTrack(at position: Int) {
        guard position != selectedAudioTrackOrderIndex else { return }

        let myPrepID = preparationID
        let wasPlaying = (player?.rate ?? 0) != 0 || (mpvPlayer?.isPlaying ?? false)
        if wasPlaying { pause() }

        Task { @MainActor [weak self] in
            guard let self,
                  self.preparationID == myPrepID else { return }
            let changed = await self.trackSelection.selectAudioTrack(
                at: position,
                playerItem: self.player?.currentItem,
                mpvPlayer: self.mpvPlayer,
                useMPV: self.useMPV
            )
            if changed, wasPlaying {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled,
                      self.preparationID == myPrepID else { return }
                self.togglePlayback()
            }
        }
    }

    func applySelectedAudioTrack() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.trackSelection.applySelectedAudioTrack(
                playerItem: self.player?.currentItem,
                mpvPlayer: self.mpvPlayer,
                useMPV: self.useMPV
            )
        }
    }

    func applySelectedAudioTrackToCurrentPlayerItem() {
        applySelectedAudioTrack()
    }

    // MARK: - Subtitle Track Selection

    func buildMPVSubtitleTrackOptions() {
        guard let mpvPlayer else { return }
        trackSelection.rebuildMPVTrackOptions(
            audioNames: mpvPlayer.audioTrackNames,
            audioIndexes: mpvPlayer.audioTrackIndexes,
            subtitleNames: mpvPlayer.subtitleTrackNames,
            subtitleIndexes: mpvPlayer.subtitleTrackIndexes
        )
    }

    func selectSubtitleTrack(at position: Int) {
        guard useMPV else { return }
        _ = trackSelection.selectSubtitleTrack(at: position, mpvPlayer: mpvPlayer)
    }

    // MARK: - Chapter Selection

    func refreshChapterOptions(playerItem: AVPlayerItem?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.trackSelection.refreshChapterOptions(
                playerItem: playerItem,
                mpvPlayer: self.mpvPlayer,
                useMPV: self.useMPV
            )
        }
    }

    func jumpToChapter(at position: Int) {
        guard chapterOptions.indices.contains(position) else { return }
        seekTo(chapterOptions[position].time)
    }

    // MARK: - Trim Points

    func setTrimIn() {
        mediaOperations.setTrimIn(at: currentPlaybackTime)
    }

    func setTrimOut() {
        mediaOperations.setTrimOut(at: currentPlaybackTime)
    }

    func clearTrimIn() {
        mediaOperations.clearTrimIn()
    }

    func clearTrimOut() {
        mediaOperations.clearTrimOut()
    }

    func clearTrimPoints() {
        mediaOperations.clearTrimPoints()
    }

    // MARK: - Screenshot

    func captureScreenshot() {
        guard let item = mediaItem else { return }
        mediaOperations.captureScreenshot(for: item, at: currentPlaybackTime)
    }

    func dismissScreenshotFeedback() {
        mediaOperations.dismissScreenshotFeedback()
    }

    // MARK: - Trim Export

    func exportTrim() {
        guard let item = mediaItem else { return }
        mediaOperations.exportTrim(for: item)
    }

    func cancelExport() {
        mediaOperations.cancelExport()
    }

    func dismissTrimExportFeedback() {
        mediaOperations.dismissTrimExportFeedback()
    }

    func cancelMediaOperationsForWindowClose() {
        mediaOperations.cancelOperationsForWindowClose()
    }

    // MARK: - Teardown

    func teardown(resetAudioSelection: Bool = true) {
        cancelPendingScrubSeeks()

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

        // Also nil the AVPlayerView's player reference so the view layer
        // cannot resurrect audio from the old player object.
        playerView?.player = nil
        removePlaybackTimeObserver()
        removePlayerItemStatusObserver()
        removeTimeControlStatusObserver()
        removeLoopObserver()

        // Cancel in-flight MPV observation Tasks before stopping
        mpvTimePosTask?.cancel()
        mpvTimePosTask = nil
        mpvFileLoadedTask?.cancel()
        mpvFileLoadedTask = nil
        mpvDurationTask?.cancel()
        mpvDurationTask = nil

        backendAdapter?.teardown()
        backendAdapter = nil

        playbackPhase = .idle
        isPlaying = false
        currentPlaybackSpeed = 1.0
        // videoAspectRatio / videoSourceSize are intentionally NOT wiped here:
        // the next loadMedia overwrites them with the new file's values, and
        // keeping them set across the player gap avoids a nil-flash that would
        // make PlayerView fall back to 16:9 and WindowConfigurator briefly
        // collapse its aspect lock.
        mpvAspectRatioCancellable = nil
        mpvSourceSizeCancellable = nil
        mpvGammaCancellable = nil
        mpvSigPeakCancellable = nil
        mpvIsPlayingCancellable = nil
        mpvBackwardFailureCancellable = nil
        mpvErrorCancellable = nil
        mpvBusyCancellable = nil
        removeMPVLoopObserver()
        if resetAudioSelection {
            showAllMonoWaveforms = UserDefaults.standard.value(for: AppSettings.showAllMonoWaveforms)
        }
        trackSelection.reset(preservingSelections: !resetAudioSelection)
    }
}

// MARK: - Double Clamped Helper

extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        let value = isFinite ? self : defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
