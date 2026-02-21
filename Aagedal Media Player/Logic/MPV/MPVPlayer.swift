// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Combine
import AppKit
import Libmpv
import OSLog

/// MPV Player - NOT an actor to allow background thread access for event handling
/// All @Published property updates are dispatched to main thread
/// Marked @unchecked Sendable because we handle thread safety manually with DispatchQueue
final class MPVPlayer: NSObject, ObservableObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "MPVPlayer")

    // MPV context
    private var mpv: OpaquePointer?
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
    @Published var error: String?

    private var isInitialized = false
    private var startPaused = false
    private var wakeupContext: UnsafeMutableRawPointer?

    // Pending load - stored when load() is called before MPV is initialized
    private var pendingURL: URL?
    private var pendingStartTime: Double = 0
    private var pendingAutostart: Bool = false

    // Start time to seek to after file loads
    private var pendingSeekAfterLoad: Double = 0

    override init() {
        super.init()
    }

    deinit {
        if mpv != nil {
            mpv_set_wakeup_callback(mpv, nil, nil)

            queue.sync {
                if self.mpv != nil {
                    mpv_terminate_destroy(self.mpv)
                    self.mpv = nil
                }
            }
        }

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
            error = "Failed to create MPV context"
            return
        }

        #if DEBUG
        checkError(mpv_request_log_messages(mpv, "warn"))
        #else
        checkError(mpv_request_log_messages(mpv, "no"))
        #endif

        var wid = unsafeBitCast(metalLayer, to: Int64.self)
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid))
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))

        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "deinterlace", "auto"))

        checkError(mpv_set_option_string(mpv, "ytdl", "no"))
        checkError(mpv_set_option_string(mpv, "input-default-bindings", "no"))
        checkError(mpv_set_option_string(mpv, "input-vo-keyboard", "no"))
        checkError(mpv_set_option_string(mpv, "load-scripts", "no"))
        checkError(mpv_set_option_string(mpv, "sid", "no"))

        #if os(macOS)
        checkError(mpv_set_option_string(mpv, "input-media-keys", "no"))
        #endif

        checkError(mpv_initialize(mpv))

        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.seekable, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.eofReached, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.speed, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsAspect, MPV_FORMAT_DOUBLE)

        wakeupContext = Unmanaged.passRetained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let client = ctx else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(client).takeUnretainedValue()
            player.readEvents()
        }, wakeupContext)

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

        logger.info("Loading file: \(url.lastPathComponent), startTime: \(startTime), autostart: \(autostart)")

        startPaused = !autostart
        pendingSeekAfterLoad = startTime

        let path = url.isFileURL ? url.path : url.absoluteString
        let cmd = "loadfile \"\(path.replacingOccurrences(of: "\"", with: "\\\""))\" replace"

        commandString(cmd)

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

    func stop() {
        command("stop")
        isPlaying = false
        timePos = 0
        videoAspectRatio = nil
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

    func seekRelative(_ time: TimeInterval) {
        command("seek", args: [String(time), "relative"])
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
            setInt(MPVProperty.aid, Int(newValue))
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

    // MARK: - Event Handling

    private func readEvents() {
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
                        case MPVProperty.videoParamsAspect:
                            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee, value > 0 {
                                DispatchQueue.main.async {
                                    self.videoAspectRatio = CGFloat(value)
                                }
                            }
                        default:
                            break
                        }
                    }

                case MPV_EVENT_SHUTDOWN:
                    self.logger.info("MPV shutdown event")
                    if self.mpv != nil {
                        mpv_terminate_destroy(self.mpv)
                        self.mpv = nil
                    }

                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(pointee.data)) {
                        let prefix = String(cString: msg.pointee.prefix!)
                        let level = String(cString: msg.pointee.level!)
                        let text = String(cString: msg.pointee.text!)
                        print("[\(prefix)] \(level): \(text)", terminator: "")
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

    // MARK: - MPV Commands & Properties

    private func commandString(_ cmd: String) {
        guard let mpvCtx = mpv else { return }
        let result = mpv_command_string(mpvCtx, cmd)
        if result < 0 {
            logger.warning("MPV command failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    private func command(_ name: String, args: [String] = []) {
        guard let mpvCtx = mpv else { return }

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
        }
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

    private func getInt(_ name: String) -> Int {
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

    private func checkError(_ status: CInt) {
        if status < 0 {
            let errorMsg = String(cString: mpv_error_string(status))
            logger.error("MPV API error: \(errorMsg)")
        }
    }
}
