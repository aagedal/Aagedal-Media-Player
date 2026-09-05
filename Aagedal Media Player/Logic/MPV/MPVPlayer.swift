// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Combine
import AppKit
import Libmpv
import OSLog

/// Free function used as the mpv wakeup callback.  Defined at file scope
/// so it is `nonisolated` and does NOT inherit `@MainActor` isolation from
/// `MPVPlayer` (which is implicitly `@MainActor` under Swift 6's default
/// actor isolation).  This prevents a runtime `dispatch_assert_queue` crash
/// when mpv invokes the callback from its own background thread.
private nonisolated func mpvWakeupCallback(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let player = Unmanaged<MPVPlayer>.fromOpaque(ctx).takeUnretainedValue()
    player.readEvents()
}

/// MPV Player - NOT an actor to allow background thread access for event handling
/// All @Published property updates are dispatched to main thread
/// Marked @unchecked Sendable because we handle thread safety manually with DispatchQueue
final class MPVPlayer: NSObject, ObservableObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "MPVPlayer")

    // MPV context
    private nonisolated(unsafe) var mpv: OpaquePointer?
    private var metalLayer: MPVMetalLayer?
    private let queue = DispatchQueue(label: "com.aagedal.mpv", qos: .userInitiated)

    // Published properties for playback state
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var timePos: Double = 0
    @Published var volume: Double = 100 {
        didSet {
            setDouble(MPVProperty.volume, volume)
        }
    }
    @Published var isMuted: Bool = false {
        didSet {
            setFlag(MPVProperty.mute, isMuted)
        }
    }
    @Published var isSeekable = false
    @Published var isBusy = false
    @Published var isFileLoaded = false
    @Published var videoAspectRatio: CGFloat?
    @Published var videoSourceSize: NSSize?
    @Published var error: String?
    @Published private(set) var errorStage: PlaybackFailureStage = .loading
    @Published var videoGamma: String?
    @Published var videoSigPeak: Double = 1.0

    /// Fires when mpv itself gives up on backward playback (it emits
    /// "Backward playback is likely stuck/broken now." when its experimental
    /// algorithm can't keep up with the file — typically high-bitrate HEVC
    /// content with mid-stream parameter-set changes). Subscribers should
    /// fall back to a different reverse-playback strategy.
    let backwardPlaybackFailed = PassthroughSubject<Void, Never>()

    private var correctsReflection = false
    private var isInitialized = false
    private var startPaused = false
    private nonisolated(unsafe) var wakeupContext: UnsafeMutableRawPointer?

    // Pending load - stored when load() is called before MPV is initialized
    private var pendingURL: URL?
    private var pendingStartTime: Double = 0
    private var pendingAutostart: Bool = false
    private var shouldLoop = false
    private var isAudioTrackDisabled = false
    private var audioChannelRouting = AudioChannelRouting()
    private(set) var isAudioChannelFilterActive = false
    var isAudioTrackSelectionDisabled: Bool { isAudioTrackDisabled }

    // Start time to seek to after file loads
    private var pendingSeekAfterLoad: Double = 0

    override init() {
        super.init()
    }

    convenience init(correctsReflection: Bool) {
        self.init()
        self.correctsReflection = correctsReflection
    }

    deinit {
        // Safety net — destroy() should have been called already.
        if mpv != nil {
            mpv_set_wakeup_callback(mpv, nil, nil)
            mpv_terminate_destroy(mpv)
            mpv = nil
        }

        if let ctx = wakeupContext {
            Unmanaged<MPVPlayer>.fromOpaque(ctx).release()
            wakeupContext = nil
        }
    }

    /// Tear down the mpv context and break the Unmanaged retain cycle so
    /// this object can be deallocated.  Must be called before dropping the
    /// last external strong reference.
    func destroy() {
        guard mpv != nil else { return }

        // Disable the wakeup callback first so no new readEvents() calls
        // are dispatched while we tear down.
        mpv_set_wakeup_callback(mpv, nil, nil)

        queue.sync {
            guard self.mpv != nil else { return }
            mpv_terminate_destroy(self.mpv)
            self.mpv = nil
        }

        isInitialized = false
        metalLayer = nil

        // Release the Unmanaged self-retain so deinit can run.
        if let ctx = wakeupContext {
            Unmanaged<MPVPlayer>.fromOpaque(ctx).release()
            wakeupContext = nil
        }
    }

    // MARK: - Metal Layer Binding

    func attachDrawable(_ layer: MPVMetalLayer) {
        metalLayer = layer
        setupMPV()

        if let url = pendingURL {
            let startTime = pendingStartTime
            let autostart = pendingAutostart
            pendingURL = nil
            pendingStartTime = 0
            pendingAutostart = false
            load(url: url, startTime: startTime, autostart: autostart)
        }
    }

    private func setupMPV() {
        guard mpv == nil else {
            logger.info("MPV already initialized, skipping setup")
            return
        }

        guard let metalLayer = metalLayer else {
            logger.error("Cannot setup MPV: no Metal layer attached")
            return
        }

        mpv = mpv_create()
        guard mpv != nil else {
            logger.error("Failed to create MPV context")
            errorStage = .initialization
            error = "Failed to create MPV context"
            return
        }

        #if DEBUG
        checkError(mpv_request_log_messages(mpv, "warn"))
        #else
        checkError(mpv_request_log_messages(mpv, "no"))
        #endif

        var wid = unsafeBitCast(metalLayer, to: Int64.self)
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid), context: "wid")
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"), context: "vo")
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"), context: "gpu-api")
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"), context: "gpu-context")
        checkError(mpv_set_option_string(mpv, "hwdec", correctsReflection ? "videotoolbox-copy" : "videotoolbox"), context: "hwdec")
        if correctsReflection {
            // A reflected matrix decomposes into the rotation MPV already
            // applies and a vertical flip in coded-raster coordinates. A video
            // filter fixes the surface, scopes, and screenshots together.
            checkError(mpv_set_option_string(mpv, "vf", "lavfi=[vflip]"), context: "display reflection")
        }

        checkError(mpv_set_option_string(mpv, "framedrop", "decoder+vo"), context: "framedrop")

        // Buffers required for --play-direction=backward (used for reverse
        // playback on the MPV backend). These are caps, not pre-allocations —
        // mpv only uses what it needs to hold one GOP of decoded frames.
        //
        // Decoded-frame footprint: 1080p 10-bit ≈ 6 MB/frame, 4K 10-bit
        // ≈ 25 MB/frame. A 2-second GOP at 24 fps of 4K HDR HEVC is ~1.2 GB
        // of decoded frames, so anything under 2 GiB silently fails on
        // Blu-ray-style content. 4 GiB gives headroom for long-GOP 4K HDR
        // and 4K AV1 without affecting RAM use on simpler files.
        checkError(mpv_set_option_string(mpv, "video-reversal-buffer", "4GiB"), context: "video-reversal-buffer")
        checkError(mpv_set_option_string(mpv, "audio-reversal-buffer", "128MiB"), context: "audio-reversal-buffer")

        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"), context: "target-colorspace-hint")
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"), context: "keep-open")
        checkError(mpv_set_option_string(mpv, "deinterlace", "auto"), context: "deinterlace")
        checkError(mpv_set_option_string(mpv, "screenshot-high-bit-depth", "yes"), context: "screenshot-high-bit-depth")

        checkError(mpv_set_option_string(mpv, "input-default-bindings", "no"), context: "input-default-bindings")
        checkError(mpv_set_option_string(mpv, "input-vo-keyboard", "no"), context: "input-vo-keyboard")
        checkError(mpv_set_option_string(mpv, "load-scripts", "no"), context: "load-scripts")
        checkError(mpv_set_option_string(mpv, "sid", "no"), context: "sid")
        if isAudioTrackDisabled {
            checkError(mpv_set_option_string(mpv, "aid", "no"), context: "aid")
        }

        #if os(macOS)
        checkError(mpv_set_option_string(mpv, "input-media-keys", "no"), context: "input-media-keys")
        #endif

        let initializationStatus = mpv_initialize(mpv)
        guard initializationStatus >= 0 else {
            let message = String(cString: mpv_error_string(initializationStatus))
            logger.error("MPV initialization failed: \(message)")
            mpv_terminate_destroy(mpv)
            mpv = nil
            errorStage = .initialization
            error = "MPV initialization failed: \(message)"
            return
        }

        // These values may have been assigned while load() was still pending,
        // before the drawable existed and mpv had an initialized context.
        setDouble(MPVProperty.volume, volume)
        setFlag(MPVProperty.mute, isMuted)
        applyAudioChannelRouting()
        setLooping(shouldLoop)

        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.seekable, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.eofReached, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.speed, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsDw, MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsDh, MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsRotate, MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsGamma, MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsSigPeak, MPV_FORMAT_DOUBLE)

        wakeupContext = Unmanaged.passRetained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, mpvWakeupCallback, wakeupContext)

        isInitialized = true
        logger.info("MPV initialized successfully")
    }

    // MARK: - Playback Control

    func load(url: URL, startTime: Double = 0, autostart: Bool = false) {
        guard mpv != nil else {
            logger.info("MPV not initialized yet, storing pending load for: \(url.lastPathComponent)")
            pendingURL = url
            pendingStartTime = startTime
            pendingAutostart = autostart
            return
        }

        isFileLoaded = false
        error = nil
        errorStage = .loading

        logger.info("Loading file: \(url.lastPathComponent), startTime: \(startTime), autostart: \(autostart)")

        startPaused = !autostart
        pendingSeekAfterLoad = startTime

        let path = url.isFileURL ? url.path : url.absoluteString

        // Use argv-form to avoid string-parsing pitfalls with paths that contain
        // quotes, backslashes, or whitespace.
        if !command("loadfile", args: [path, "replace"]) {
            errorStage = .loading
            error = "mpv rejected the request to load this file."
            return
        }

        if !autostart {
            setFlag(MPVProperty.pause, true)
        }
    }

    func play() {
        setFlag(MPVProperty.pause, false)
    }

    func pause() {
        startPaused = false
        setFlag(MPVProperty.pause, true)
    }

    func togglePause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func setLooping(_ enabled: Bool) {
        shouldLoop = enabled
        guard mpv != nil else { return }
        command("set", args: ["loop-file", enabled ? "inf" : "no"])
    }

    func stop() {
        command("stop")
        isPlaying = false
        timePos = 0
        videoAspectRatio = nil
        videoSourceSize = nil
    }

    func seek(to time: TimeInterval) {
        var seekTime = time
        if duration > 0 {
            let maxSeekTime = max(0, duration - 0.05)
            seekTime = min(seekTime, maxSeekTime)
        }
        seekTime = max(0, seekTime)

        command("seek", args: [String(seekTime), "absolute"])
    }

    /// Fast, keyframe-aligned seek for interactive timeline scrubbing.
    /// A precise seek is issued when the gesture ends.
    func seekForScrubbing(to time: TimeInterval) {
        var seekTime = time
        if duration > 0 {
            let maxSeekTime = max(0, duration - 0.05)
            seekTime = min(seekTime, maxSeekTime)
        }
        seekTime = max(0, seekTime)

        command("seek", args: [String(seekTime), "absolute+keyframes"])
    }

    func seekRelative(_ time: TimeInterval) {
        command("seek", args: [String(time), "relative"])
    }

    /// Reads mpv's playback clock directly, serialized with event handling and
    /// teardown. The published `timePos` value is intentionally optimized for
    /// UI observation and can be several update intervals behind the decoder.
    nonisolated func playbackTimeSnapshot() -> TimeInterval? {
        queue.sync {
            guard let mpv else { return nil }
            return doublePropertyLocked(MPVProperty.timePos, context: mpv)
        }
    }

    /// Switch playback direction at runtime. Pass "forward" or "backward".
    /// Backward playback decodes frames forward into the reversal buffer and
    /// emits them in reverse, so the decoder never has to handle a backward
    /// seek — fixes "Missing reference picture" failures on long-GOP files.
    /// Requires `video-reversal-buffer` (and `audio-reversal-buffer`) to have
    /// been set during initialization.
    func setPlayDirection(_ direction: String) {
        guard let mpvCtx = mpv else { return }
        let result = direction.withCString { cstr -> Int32 in
            var ptr: UnsafePointer<CChar>? = cstr
            return mpv_set_property(mpvCtx, "play-direction", MPV_FORMAT_STRING, &ptr)
        }
        if result < 0 {
            logger.warning("setPlayDirection(\(direction)) failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    var rate: Float {
        get {
            Float(getDouble(MPVProperty.speed))
        }
        set {
            setDouble(MPVProperty.speed, Double(newValue))
        }
    }

    // MARK: - Audio Tracks

    var audioTrackNames: [String] {
        guard mpv != nil else { return [] }

        var names: [String] = []
        let count = getInt(MPVProperty.trackListCount)
        var audioIndex = 0

        for i in 0..<count {
            let typeKey = "track-list/\(i)/type"
            guard let type = getString(typeKey), type == "audio" else { continue }

            let titleKey = "track-list/\(i)/title"
            let langKey = "track-list/\(i)/lang"
            let codecKey = "track-list/\(i)/codec"
            let channelsKey = "track-list/\(i)/demux-channel-count"
            let sampleRateKey = "track-list/\(i)/demux-samplerate"

            var components: [String] = []
            components.append("#\(audioIndex)")
            audioIndex += 1

            if let lang = getString(langKey), !lang.isEmpty {
                components.append(lang.uppercased())
            }

            if let title = getString(titleKey), !title.isEmpty {
                let lang = getString(langKey) ?? ""
                if title.lowercased() != lang.lowercased() {
                    components.append(title)
                }
            }

            if let codec = getString(codecKey), !codec.isEmpty {
                components.append(codec.uppercased())
            }

            let channels = getInt(channelsKey)
            if channels > 0 {
                let channelDesc = formatChannelCount(channels)
                components.append(channelDesc)
            }

            let sampleRate = getInt(sampleRateKey)
            if sampleRate > 0 {
                components.append("\(sampleRate / 1000) kHz")
            }

            names.append(components.joined(separator: " \u{2022} "))
        }

        return names
    }

    private func formatChannelCount(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels) ch"
        }
    }

    var audioTrackIndexes: [Int32] {
        guard mpv != nil else { return [] }

        var indexes: [Int32] = []
        let count = getInt(MPVProperty.trackListCount)

        for i in 0..<count {
            let typeKey = "track-list/\(i)/type"
            guard let type = getString(typeKey), type == "audio" else { continue }

            let idKey = "track-list/\(i)/id"
            let trackId = getInt(idKey)
            indexes.append(Int32(trackId))
        }

        return indexes
    }

    var currentAudioTrackIndex: Int32 {
        get {
            Int32(getInt(MPVProperty.aid))
        }
        set {
            guard !isAudioTrackDisabled || newValue == -2 else { return }
            setInt(MPVProperty.aid, Int(newValue))
        }
    }

    func disableAudioTrack() {
        // mpv represents the disabled audio selection as track id -2.
        isAudioTrackDisabled = true
        guard mpv != nil else { return }
        currentAudioTrackIndex = -2
    }

    func enableAudioTrackSelection() {
        isAudioTrackDisabled = false
    }

    func setAudioChannelRouting(_ routing: AudioChannelRouting) {
        audioChannelRouting = routing
        applyAudioChannelRouting()
    }

    private func applyAudioChannelRouting() {
        if let filter = audioChannelRouting.mpvAudioFilter {
            if command("af", args: ["add", "@amp-channel-route:\(filter)"]) {
                isAudioChannelFilterActive = true
            }
        } else if isAudioChannelFilterActive,
                  command("af", args: ["remove", "@amp-channel-route"]) {
            isAudioChannelFilterActive = false
        }
    }

    // MARK: - Subtitle Tracks

    var subtitleTrackNames: [String] {
        guard mpv != nil else { return [] }

        var names: [String] = []
        let count = getInt(MPVProperty.trackListCount)
        var subIndex = 0

        for i in 0..<count {
            let typeKey = "track-list/\(i)/type"
            guard let type = getString(typeKey), type == "sub" else { continue }

            let titleKey = "track-list/\(i)/title"
            let langKey = "track-list/\(i)/lang"
            let codecKey = "track-list/\(i)/codec"

            var components: [String] = []
            components.append("#\(subIndex)")
            subIndex += 1

            if let lang = getString(langKey), !lang.isEmpty {
                components.append(lang.uppercased())
            }

            if let title = getString(titleKey), !title.isEmpty {
                let lang = getString(langKey) ?? ""
                if title.lowercased() != lang.lowercased() {
                    components.append(title)
                }
            }

            if let codec = getString(codecKey), !codec.isEmpty {
                components.append(codec.uppercased())
            }

            names.append(components.joined(separator: " \u{2022} "))
        }

        return names
    }

    var subtitleTrackIndexes: [Int32] {
        guard mpv != nil else { return [] }

        var indexes: [Int32] = []
        let count = getInt(MPVProperty.trackListCount)

        for i in 0..<count {
            let typeKey = "track-list/\(i)/type"
            guard let type = getString(typeKey), type == "sub" else { continue }

            let idKey = "track-list/\(i)/id"
            let trackId = getInt(idKey)
            indexes.append(Int32(trackId))
        }

        return indexes
    }

    var currentSubtitleTrackIndex: Int32 {
        get {
            Int32(getInt(MPVProperty.sid))
        }
        set {
            setInt(MPVProperty.sid, Int(newValue))
        }
    }

    var isSubtitleVisible: Bool {
        get {
            getInt(MPVProperty.subVisibility) != 0
        }
        set {
            setFlag(MPVProperty.subVisibility, newValue)
        }
    }

    func disableSubtitles() {
        setInt(MPVProperty.sid, 0)
    }

    // MARK: - Chapters

    var chapters: [(time: Double, title: String)] {
        guard mpv != nil else { return [] }
        var result: [(Double, String)] = []
        let count = getInt(MPVProperty.chapterListCount)
        for i in 0..<count {
            let time = getDouble("chapter-list/\(i)/time")
            let title = getString("chapter-list/\(i)/title") ?? "Chapter \(i + 1)"
            result.append((time, title))
        }
        return result
    }

    // MARK: - Event Handling

    fileprivate nonisolated func readEvents() {
        queue.async { [weak self] in
            guard let self, self.mpv != nil else { return }

            while self.mpv != nil {
                let event = mpv_wait_event(self.mpv, 0)
                guard let pointee = event?.pointee else { break }

                if pointee.event_id == MPV_EVENT_NONE { break }

                switch pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    if let dataPtr = OpaquePointer(pointee.data),
                       let property = UnsafePointer<mpv_event_property>(dataPtr)?.pointee {
                        let propertyName = String(cString: property.name)

                        switch propertyName {
                        case MPVProperty.timePos:
                            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async { self.timePos = value }
                            }
                        case MPVProperty.duration:
                            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async { self.duration = value }
                            }
                        case MPVProperty.pause:
                            if let value = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async { self.isPlaying = value == 0 }
                            }
                        case MPVProperty.pausedForCache:
                            if let value = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async { self.isBusy = value != 0 }
                            }
                        case MPVProperty.seekable:
                            if let value = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async { self.isSeekable = value != 0 }
                            }
                        case MPVProperty.eofReached:
                            if let value = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee, value != 0 {
                                DispatchQueue.main.async {
                                    self.logger.info("EOF reached, pausing at last frame")
                                    self.isPlaying = false
                                }
                            }
                        case MPVProperty.videoParamsDw, MPVProperty.videoParamsDh, MPVProperty.videoParamsRotate:
                            // Read all three together — any of them changing means we
                            // need to recompute display dims with rotation applied.
                            let dw = self.getInt(MPVProperty.videoParamsDw)
                            let dh = self.getInt(MPVProperty.videoParamsDh)
                            let rotate = self.getInt(MPVProperty.videoParamsRotate)
                            scalingLogger.info("mpv video-params: dw=\(dw) dh=\(dh) rotate=\(rotate)")
                            if dw > 0, dh > 0 {
                                let normalized = ((rotate % 360) + 360) % 360
                                let swap = (normalized == 90 || normalized == 270)
                                let dispW = swap ? dh : dw
                                let dispH = swap ? dw : dh
                                DispatchQueue.main.async {
                                    self.videoSourceSize = NSSize(width: dispW, height: dispH)
                                    self.videoAspectRatio = CGFloat(dispW) / CGFloat(dispH)
                                    scalingLogger.info("mpv emitted videoSourceSize=\(dispW)x\(dispH) (ratio=\(Double(dispW) / Double(dispH)))")
                                }
                            }
                        case MPVProperty.videoParamsGamma:
                            if property.format == MPV_FORMAT_STRING,
                               let strPtr = UnsafePointer<UnsafeMutablePointer<CChar>>(OpaquePointer(property.data))?.pointee {
                                let gamma = String(cString: strPtr)
                                DispatchQueue.main.async { self.videoGamma = gamma }
                            }
                        case MPVProperty.videoParamsSigPeak:
                            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee, value > 0 {
                                DispatchQueue.main.async { self.videoSigPeak = value }
                            }
                        default:
                            break
                        }
                    }

                case MPV_EVENT_SHUTDOWN:
                    self.logger.info("MPV shutdown event received")
                    // Don't call mpv_terminate_destroy here — destroy()
                    // handles full cleanup.  Just exit the event loop.
                    return

                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(pointee.data)) {
                        // mpv's log fields are documented as non-null, but defend
                        // against malformed events rather than crashing the event loop.
                        let prefix = msg.pointee.prefix.map { String(cString: $0) } ?? "mpv"
                        let level = msg.pointee.level.map { String(cString: $0) } ?? "?"
                        let text = msg.pointee.text.map { String(cString: $0) } ?? ""
                        print("[\(prefix)] \(level): \(text)", terminator: "")
                        // mpv's backward-playback algorithm prints this exact
                        // string when it gives up. Signal subscribers so they
                        // can fall back to a different reverse strategy.
                        if text.contains("Backward playback is likely stuck") {
                            DispatchQueue.main.async { [weak self] in
                                self?.backwardPlaybackFailed.send()
                            }
                        }
                    }

                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self.logger.info("MPV file loaded")
                        self.isFileLoaded = true
                        if self.pendingSeekAfterLoad > 0 {
                            self.seek(to: self.pendingSeekAfterLoad)
                            self.pendingSeekAfterLoad = 0
                        }
                        if self.startPaused {
                            self.setFlag(MPVProperty.pause, true)
                            self.startPaused = false
                        }
                    }

                case MPV_EVENT_END_FILE:
                    if let dataPtr = OpaquePointer(pointee.data) {
                        let endFile = UnsafePointer<mpv_event_end_file>(dataPtr).pointee
                        if endFile.reason == MPV_END_FILE_REASON_ERROR {
                            let errorMsg = String(cString: mpv_error_string(endFile.error))
                            self.logger.error("MPV end file error: \(errorMsg)")
                            DispatchQueue.main.async {
                                self.errorStage = self.isFileLoaded ? .playback : .loading
                                self.error = errorMsg
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.isPlaying = false
                    }

                case MPV_EVENT_START_FILE:
                    self.logger.info("MPV start file event")

                default:
                    break
                }
            }
        }
    }

    // MARK: - Screenshot

    /// Raw pixel data returned by `screenshot-raw`.
    struct RawScreenshot: Sendable {
        let data: Data
        let width: Int
        let height: Int
        let stride: Int
        let format: String  // e.g. "bgr0", "rgba64"
        /// Item-relative playback-clock estimate bracketed immediately around
        /// `screenshot-raw`. The uncertainty is half of that clock interval.
        let playbackTime: TimeInterval?
        let playbackTimeUncertainty: TimeInterval?
    }

    /// Capture the current decoded video frame as raw BGRA pixels.
    /// Uses `screenshot-raw` via `mpv_command_node` — no libavcodec encoder needed.
    ///
    /// Runs on `queue` so it is serialized against `destroy()`'s
    /// `mpv_terminate_destroy`. Scope capture calls this from a background Task
    /// that `stopCapture()` does not await, so without this serialization a
    /// teardown could free the mpv context mid-command — a use-after-free.
    /// Inside the queue the screenshot either completes before the context is
    /// torn down or observes `mpv == nil` and bails.
    nonisolated func screenshotRaw() -> RawScreenshot? {
        queue.sync { screenshotRawLocked() }
    }

    /// Must run on `queue`. Touches the mpv context directly.
    private nonisolated func screenshotRawLocked() -> RawScreenshot? {
        guard let mpvCtx = mpv else { return nil }
        let timeBeforeCapture = doublePropertyLocked(MPVProperty.timePos, context: mpvCtx)

        let cmdStr = strdup("screenshot-raw")
        let flagStr = strdup("video")
        defer { free(cmdStr); free(flagStr) }

        var argNode0 = mpv_node()
        argNode0.format = MPV_FORMAT_STRING
        argNode0.u.string = cmdStr

        var argNode1 = mpv_node()
        argNode1.format = MPV_FORMAT_STRING
        argNode1.u.string = flagStr

        var argValues = [argNode0, argNode1]
        var result = mpv_node()

        let err = argValues.withUnsafeMutableBufferPointer { buf -> Int32 in
            var list = mpv_node_list()
            list.num = 2
            list.values = buf.baseAddress
            list.keys = nil

            return withUnsafeMutablePointer(to: &list) { listPtr -> Int32 in
                var args = mpv_node()
                args.format = MPV_FORMAT_NODE_ARRAY
                args.u.list = listPtr
                return mpv_command_node(mpvCtx, &args, &result)
            }
        }
        let timeAfterCapture = doublePropertyLocked(MPVProperty.timePos, context: mpvCtx)
        let bracketedTime = bracketedPlaybackTime(
            before: timeBeforeCapture,
            after: timeAfterCapture
        )

        defer { mpv_free_node_contents(&result) }

        guard err == 0,
              result.format == MPV_FORMAT_NODE_MAP,
              let resultList = result.u.list else { return nil }

        let num = Int(resultList.pointee.num)
        var width = 0, height = 0, stride = 0
        var pixelData: Data?
        var format = "bgr0"

        for i in 0..<num {
            guard let keyPtr = resultList.pointee.keys?[i] else { continue }
            let key = String(cString: keyPtr)
            let val = resultList.pointee.values[i]

            switch key {
            case "w": width = Int(val.u.int64)
            case "h": height = Int(val.u.int64)
            case "stride": stride = Int(val.u.int64)
            case "format":
                if val.format == MPV_FORMAT_STRING, let s = val.u.string {
                    format = String(cString: s)
                }
            case "data":
                if let ba = val.u.ba {
                    pixelData = Data(bytes: ba.pointee.data, count: ba.pointee.size)
                }
            default: break
            }
        }

        guard let data = pixelData, width > 0, height > 0, stride > 0 else { return nil }
        return RawScreenshot(
            data: data,
            width: width,
            height: height,
            stride: stride,
            format: format,
            playbackTime: bracketedTime?.time,
            playbackTimeUncertainty: bracketedTime?.uncertainty
        )
    }

    private nonisolated func bracketedPlaybackTime(
        before: TimeInterval?,
        after: TimeInterval?
    ) -> (time: TimeInterval, uncertainty: TimeInterval)? {
        guard let before, let after else { return nil }
        return (
            time: max(0, (before + after) / 2),
            uncertainty: abs(after - before) / 2
        )
    }

    /// Reads a property while already serialized on mpv's queue. Keeping the
    /// timestamp read beside `screenshot-raw` avoids using the slower
    /// main-actor-published clock after pixel extraction has completed.
    private nonisolated func doublePropertyLocked(
        _ name: String,
        context: OpaquePointer
    ) -> Double? {
        var value = Double.zero
        let result = mpv_get_property(context, name, MPV_FORMAT_DOUBLE, &value)
        guard result >= 0, value.isFinite else { return nil }
        return max(0, value)
    }

    // MARK: - MPV Commands & Properties

    private func commandString(_ cmd: String) {
        guard let mpvCtx = mpv else { return }
        let result = mpv_command_string(mpvCtx, cmd)
        if result < 0 {
            logger.warning("MPV command failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    @discardableResult
    private func command(_ name: String, args: [String] = []) -> Bool {
        guard let mpvCtx = mpv else { return false }

        var strArgs: [String?] = [name] + args
        strArgs.append(nil)

        var cargs = strArgs.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }

        let result = mpv_command(mpvCtx, &cargs)
        if result < 0 {
            logger.warning("MPV command '\(name)' failed: \(String(cString: mpv_error_string(result)))")
            return false
        }
        return true
    }

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard mpv != nil else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    }

    private nonisolated func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    private func setInt(_ name: String, _ value: Int) {
        guard mpv != nil else { return }
        var data = Int64(value)
        mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
    }

    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        defer { mpv_free(cstr) }
        return cstr == nil ? nil : String(cString: cstr!)
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpvCtx = mpv else { return }
        var data: Int32 = flag ? 1 : 0
        let result = mpv_set_property(mpvCtx, name, MPV_FORMAT_FLAG, &data)
        if result < 0 {
            logger.warning("setFlag failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    private func checkError(_ status: CInt, context: String = "") {
        if status < 0 {
            let errorMsg = String(cString: mpv_error_string(status))
            if context.isEmpty {
                logger.error("MPV API error: \(errorMsg)")
            } else {
                logger.error("MPV API error [\(context)]: \(errorMsg)")
            }
        }
    }
}
