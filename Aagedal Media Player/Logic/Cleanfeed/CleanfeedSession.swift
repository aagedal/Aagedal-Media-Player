// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// App-wide coordinator for OS-level CoreMediaIO broadcast cleanfeed output
// (SDI/HDMI via Blackmagic UltraStudio/DeckLink or any other macOS CMIO sink
// device) paired with linked CoreAudio output routing.

import AVFoundation
import Combine
import CoreAudioTypes
import CoreMedia
import CoreVideo
import Foundation
import Metal
import OSLog
import SwiftUI

// MARK: - SMPTE Timecode Builder

nonisolated enum CleanfeedSMPTETime {
    static func make(
        playbackSeconds: Double,
        sourceStartTimecode: String?,
        sourceFrameRate: Double?,
        outputFrameRate: Double
    ) -> SMPTETime? {
        guard playbackSeconds.isFinite, playbackSeconds >= 0 else { return nil }
        let fps = (sourceFrameRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }) ?? outputFrameRate
        let dropFrame = sourceStartTimecode?.contains(";") == true
        let rate = TimecodeRate(frameRate: fps, dropFrame: dropFrame)

        let baseFrames: Int64
        if let startTC = sourceStartTimecode,
           let parsedStart = rate.frameCount(forTimecode: startTC) {
            baseFrames = parsedStart
        } else {
            baseFrames = 0
        }

        let offsetFrames = rate.frameCount(forSeconds: playbackSeconds) ?? 0
        let totalFrames = max(0, baseFrames + offsetFrames)
        let formatted = rate.timecode(forFrameCount: totalFrames)
        let parts = formatted.split(whereSeparator: { $0 == ":" || $0 == ";" })
        guard parts.count == 4,
              let h = Int16(parts[0]),
              let m = Int16(parts[1]),
              let s = Int16(parts[2]),
              let f = Int16(parts[3]) else { return nil }

        let smpteType = smpteTimeType(for: outputFrameRate, dropFrame: rate.isDropFrame)
        return SMPTETime(
            mSubframes: 0,
            mSubframeDivisor: 0,
            mCounter: UInt32(truncatingIfNeeded: totalFrames),
            mType: smpteType,
            mFlags: SMPTETimeFlags([.valid, .running]),
            mHours: h,
            mMinutes: m,
            mSeconds: s,
            mFrames: f
        )
    }

    static func smpteTimeType(for frameRate: Double, dropFrame: Bool) -> SMPTETimeType {
        if abs(frameRate - 23.976) < 0.015 { return .type2398 }
        if abs(frameRate - 24.0) < 0.015 { return .type24 }
        if abs(frameRate - 25.0) < 0.015 { return .type25 }
        if abs(frameRate - 29.97) < 0.015 { return dropFrame ? .type2997Drop : .type2997 }
        if abs(frameRate - 30.0) < 0.015 { return dropFrame ? .type30Drop : .type30 }
        if abs(frameRate - 50.0) < 0.015 { return .type50 }
        if abs(frameRate - 59.94) < 0.015 { return dropFrame ? .type5994Drop : .type5994 }
        if abs(frameRate - 60.0) < 0.015 { return .type60 }
        return .type25
    }
}

// MARK: - Cleanfeed Session Coordinator

@MainActor
final class CleanfeedSession: ObservableObject {
    static let shared = CleanfeedSession()

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "CleanfeedSession")

    // MARK: - Published State

    @Published private(set) var availableDevices: [CMIOOutputDevice] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var isStreaming = false
    @Published private(set) var isColorBarsActive = false
    @Published private(set) var activeDevice: CMIOOutputDevice?
    @Published private(set) var activeSelection: CMIOOutputFormatSelection?
    @Published private(set) var stats = CMIOCleanfeedStats()
    @Published private(set) var errorMessage: String?

    var selectedDeviceUID: String {
        get { UserDefaults.standard.value(for: AppSettings.cleanfeedDeviceUID) }
        set {
            UserDefaults.standard.set(newValue, for: AppSettings.cleanfeedDeviceUID)
            objectWillChange.send()
            reapplyOutputConfigurationIfActive()
        }
    }

    var resolutionMode: CleanfeedResolutionMode {
        get {
            CleanfeedResolutionMode(rawValue: UserDefaults.standard.value(for: AppSettings.cleanfeedResolutionMode))
                ?? .hd1080
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, for: AppSettings.cleanfeedResolutionMode)
            objectWillChange.send()
            reapplyOutputConfigurationIfActive()
        }
    }

    var scanMode: CleanfeedScanMode {
        get {
            CleanfeedScanMode(rawValue: UserDefaults.standard.value(for: AppSettings.cleanfeedScanMode))
                ?? .progressive
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, for: AppSettings.cleanfeedScanMode)
            objectWillChange.send()
            reapplyOutputConfigurationIfActive()
        }
    }

    var frameRateMode: CleanfeedFrameRateMode {
        get {
            CleanfeedFrameRateMode(rawValue: UserDefaults.standard.value(for: AppSettings.cleanfeedFrameRateMode))
                ?? .matchMax30
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, for: AppSettings.cleanfeedFrameRateMode)
            objectWillChange.send()
            reapplyOutputConfigurationIfActive()
        }
    }

    var colorMode: CleanfeedColorMode {
        get {
            CleanfeedColorMode(rawValue: UserDefaults.standard.value(for: AppSettings.cleanfeedColorMode))
                ?? .sdr709
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, for: AppSettings.cleanfeedColorMode)
            objectWillChange.send()
            reapplyOutputConfigurationIfActive()
        }
    }

    var pixelFormatMode: CleanfeedPixelFormatMode {
        get {
            CleanfeedPixelFormatMode(rawValue: UserDefaults.standard.value(for: AppSettings.cleanfeedPixelFormatMode))
                ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, for: AppSettings.cleanfeedPixelFormatMode)
            objectWillChange.send()
            reapplyOutputConfigurationIfActive()
        }
    }

    private func reapplyOutputConfigurationIfActive() {
        if isColorBarsActive {
            startColorBarsTest()
        } else if isEnabled {
            reconfigurePipeline()
        }
    }

    var routeAudioToDevice: Bool {
        get { UserDefaults.standard.value(for: AppSettings.cleanfeedRouteAudio) }
        set {
            UserDefaults.standard.set(newValue, for: AppSettings.cleanfeedRouteAudio)
            objectWillChange.send()
            applyAudioRouting()
        }
    }

    var embedSMPTETimecode: Bool {
        get { UserDefaults.standard.value(for: AppSettings.cleanfeedEmbedTimecode) }
        set {
            UserDefaults.standard.set(newValue, for: AppSettings.cleanfeedEmbedTimecode)
            objectWillChange.send()
        }
    }

    var resolvedTargetDevice: CMIOOutputDevice? {
        if !selectedDeviceUID.isEmpty,
           let exact = availableDevices.first(where: { $0.uid == selectedDeviceUID }) {
            return exact
        }
        return availableDevices.first
    }

    /// Dynamically filtered output options supported by the currently selected
    /// CoreMediaIO device (e.g. never offers 4K or HDR on an HD-only SDR box).
    var capabilities: CMIOOutputCapabilities {
        CMIOOutputCapabilities.evaluate(
            device: resolvedTargetDevice,
            preferredResolution: resolutionMode,
            preferredScan: scanMode,
            preferredFrameRate: frameRateMode,
            preferredColor: colorMode,
            preferredPixelFormat: pixelFormatMode
        )
    }

    var effectiveResolutionMode: CleanfeedResolutionMode {
        capabilities.effectiveResolutionMode
    }

    var effectiveScanMode: CleanfeedScanMode {
        capabilities.effectiveScanMode
    }

    var effectiveFrameRateMode: CleanfeedFrameRateMode {
        capabilities.effectiveFrameRateMode
    }

    var effectiveColorMode: CleanfeedColorMode {
        capabilities.effectiveColorMode
    }

    var effectivePixelFormatMode: CleanfeedPixelFormatMode {
        capabilities.effectivePixelFormatMode
    }

    var hasOutputDevice: Bool {
        !availableDevices.isEmpty
    }

    var statusSummary: String {
        if let errorMessage {
            return errorMessage
        }
        if isColorBarsActive, let device = activeDevice, let selection = activeSelection {
            return "Color Bars → \(device.name) (\(selection.summaryLabel))"
        }
        if isStreaming, let device = activeDevice, let selection = activeSelection {
            return "\(device.name) • \(selection.summaryLabel)"
        }
        if isEnabled {
            if availableDevices.isEmpty {
                return "Waiting for output device"
            }
            return "Ready (no media loaded)"
        }
        return availableDevices.isEmpty ? "No CoreMediaIO output device detected" : "Off"
    }

    // MARK: - Internal State

    private let deviceMonitor = CMIOOutputDeviceMonitor()
    private var monitorCancellable: AnyCancellable?
    private weak var attachedController: PlayerController?
    private weak var audioRoutedController: PlayerController?
    private var controllerCancellable: AnyCancellable?

    private let sink = CMIOCleanfeedSink()
    private var converter: CMIOFrameConverter?

    // Option A MPV follower
    private var followerPlayer: MPVPlayer?
    private var cleanfeedLayer: CleanfeedMetalLayer?
    private var syncTimer: Timer?
    private var clockTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var activeSource: SourceIdentity?
    private var activeEdition: Int?
    private var wasPlaying: Bool?
    private var nominalRate: Float?
    private var baseRate: Float?
    private var looping: Bool?
    private var mirroredDeinterlace: DeinterlaceMode?
    private var mirroredPictureAdjustments: VideoPictureAdjustments?
    private var lastCorrection: TimeInterval = -.infinity
    private var lastPausedSeekTarget: TimeInterval?
    private var needsAlignment = true

    // AVPlayer (ProRes RAW) video output capture
    private var avVideoOutput: AVPlayerItemVideoOutput?
    private weak var avOutputItem: AVPlayerItem?
    private var avCaptureTimer: Timer?
    private var lastAVCapturedTime: CMTime = .invalid

    // Color bars generator
    private var colorBarsTimer: Timer?
    private var colorBarsFrameIndex = 0

    // Latest playback metadata snapshot for nonisolated texture callback timecode
    private struct TimecodeContext: Sendable {
        var playbackSeconds: Double = 0
        var sourceStartTimecode: String?
        var sourceFrameRate: Double?
        var outputFrameRate: Double = 25
        var embedTimecode: Bool = true
    }

    private let timecodeContextLock = OSAllocatedUnfairLock(initialState: TimecodeContext())

    private struct SourceIdentity: Equatable {
        let preparationID: Int
        let backend: PlaybackBackend?
        let backendID: ObjectIdentifier?
        let url: URL
    }

    // MARK: - Init

    private init() {
        availableDevices = deviceMonitor.devices
        monitorCancellable = deviceMonitor.$devices.sink { [weak self] devices in
            self?.handleDevicesChanged(devices)
        }
        sink.onStatsUpdated = { [weak self] updatedStats in
            Task { @MainActor [weak self] in
                self?.stats = updatedStats
            }
        }
    }

    // MARK: - Public Controls

    func refreshDevices() {
        deviceMonitor.refresh()
    }

    func toggleEnabled(for controller: PlayerController? = nil) {
        if let controller {
            attach(controller: controller)
        }
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            stopColorBarsTest()
            isEnabled = true
            errorMessage = nil
            reconfigurePipeline()
        } else {
            isEnabled = false
            errorMessage = nil
            teardownPipeline()
        }
    }

    func toggleColorBarsTest() {
        if isColorBarsActive {
            stopColorBarsTest()
        } else {
            startColorBarsTest()
        }
    }

    func startColorBarsTest() {
        teardownPipeline()
        isEnabled = false
        errorMessage = nil

        guard let device = resolvedTargetDevice else {
            errorMessage = "No CoreMediaIO output device is connected."
            return
        }
        let testSource = CMIOOutputSourceDescriptor(
            width: 1920,
            height: 1080,
            frameRate: 25.0,
            bitDepth: 8,
            colorPrimaries: "bt709",
            colorTransfer: "bt709"
        )
        let caps = CMIOOutputCapabilities.evaluate(
            device: device,
            preferredResolution: resolutionMode,
            preferredScan: scanMode,
            preferredFrameRate: frameRateMode,
            preferredColor: colorMode,
            preferredPixelFormat: pixelFormatMode
        )
        guard let selection = CMIOOutputFormatSelector.select(
            device: device,
            source: testSource,
            resolutionMode: caps.effectiveResolutionMode,
            scanMode: caps.effectiveScanMode,
            frameRateMode: caps.effectiveFrameRateMode,
            colorMode: caps.effectiveColorMode,
            pixelFormatMode: caps.effectivePixelFormatMode
        ) else {
            errorMessage = "No supported output format found on \(device.name)."
            return
        }
        guard let conv = CMIOFrameConverter(
            width: selection.format.width,
            height: selection.format.height,
            pixelFormat: selection.format.pixelFormat,
            colorSpace: selection.colorSpace
        ) else {
            errorMessage = "Failed to initialize frame converter."
            return
        }

        let initialBars = conv.makeColorBarsPixelBuffer(frameIndex: 0) ?? conv.makeBlackPixelBuffer()
        do {
            try sink.start(device: device, selection: selection, initialFrame: initialBars)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        converter = conv
        activeDevice = device
        activeSelection = selection
        isColorBarsActive = true
        isStreaming = true
        colorBarsFrameIndex = 1

        let interval = 1.0 / max(selection.frameRate, 1.0)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitNextColorBarsFrame()
            }
        }
        colorBarsTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopColorBarsTest() {
        guard isColorBarsActive else { return }
        colorBarsTimer?.invalidate()
        colorBarsTimer = nil
        isColorBarsActive = false
        teardownPipeline()
    }

    func attach(controller: PlayerController) {
        if attachedController === controller {
            if isEnabled { synchronize() }
            return
        }

        restoreAudioRouting()
        attachedController = controller
        controllerCancellable = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.synchronize()
            }
        }

        if isEnabled {
            reconfigurePipeline()
        }
    }

    func detach(controller: PlayerController) {
        guard attachedController === controller else { return }
        restoreAudioRouting()
        controllerCancellable = nil
        attachedController = nil
        if isEnabled {
            teardownPipeline()
        }
    }

    func shutdown() {
        stopColorBarsTest()
        isEnabled = false
        restoreAudioRouting()
        teardownPipeline()
        controllerCancellable = nil
        attachedController = nil
    }

    // MARK: - Device Hot-Plug

    private func handleDevicesChanged(_ devices: [CMIOOutputDevice]) {
        availableDevices = devices
        if let active = activeDevice, !devices.contains(where: { $0.uid == active.uid }) {
            logger.warning("Active cleanfeed device disconnected: \(active.name)")
            if isColorBarsActive {
                stopColorBarsTest()
            } else {
                teardownPipeline()
                if isEnabled {
                    errorMessage = "\(active.name) was disconnected."
                }
            }
        } else if isEnabled, !isStreaming, !devices.isEmpty {
            errorMessage = nil
            reconfigurePipeline()
        }
    }

    // MARK: - Pipeline Lifecycle

    private func reconfigurePipeline() {
        guard isEnabled else { return }
        stopColorBarsTest()

        guard let device = resolvedTargetDevice else {
            teardownPipeline()
            errorMessage = "No CoreMediaIO output device is connected."
            return
        }

        guard let controller = attachedController,
              controller.isReady,
              let mediaItem = controller.mediaItem,
              mediaItem.presentationKind != .audioOnly else {
            teardownPipeline()
            return
        }

        let sourceDescriptor = CMIOOutputSourceDescriptor.from(
            metadata: mediaItem.metadata,
            fallbackSize: controller.videoSourceSize
        )
        let caps = CMIOOutputCapabilities.evaluate(
            device: device,
            preferredResolution: resolutionMode,
            preferredScan: scanMode,
            preferredFrameRate: frameRateMode,
            preferredColor: colorMode,
            preferredPixelFormat: pixelFormatMode
        )
        guard let selection = CMIOOutputFormatSelector.select(
            device: device,
            source: sourceDescriptor,
            resolutionMode: caps.effectiveResolutionMode,
            scanMode: caps.effectiveScanMode,
            frameRateMode: caps.effectiveFrameRateMode,
            colorMode: caps.effectiveColorMode,
            pixelFormatMode: caps.effectivePixelFormatMode
        ) else {
            teardownPipeline()
            errorMessage = "No supported output format found on \(device.name)."
            return
        }

        let needsSinkRestart = activeDevice?.uid != device.uid
            || activeSelection != selection
            || !isStreaming

        if needsSinkRestart {
            teardownPipeline()
            guard let conv = CMIOFrameConverter(
                width: selection.format.width,
                height: selection.format.height,
                pixelFormat: selection.format.pixelFormat,
                colorSpace: selection.colorSpace
            ) else {
                errorMessage = "Failed to initialize cleanfeed GPU converter."
                return
            }

            let blackFrame = conv.makeBlackPixelBuffer()
            do {
                try sink.start(device: device, selection: selection, initialFrame: blackFrame)
            } catch {
                errorMessage = error.localizedDescription
                return
            }

            converter = conv
            activeDevice = device
            activeSelection = selection
            isStreaming = true
            errorMessage = nil
        }

        applyAudioRouting()
        startSyncTimer()
        synchronize()
    }

    private func teardownPipeline() {
        generation &+= 1
        colorBarsTimer?.invalidate()
        colorBarsTimer = nil
        syncTimer?.invalidate()
        syncTimer = nil
        clockTask?.cancel()
        clockTask = nil

        destroyMPVFollower()
        detachAVVideoOutput()
        sink.stop()
        restoreAudioRouting()

        converter = nil
        activeDevice = nil
        activeSelection = nil
        activeSource = nil
        activeEdition = nil
        isStreaming = false
        stats = CMIOCleanfeedStats()
    }

    // MARK: - Synchronization (MPV Option A Follower & AVPlayer)

    private func startSyncTimer() {
        guard syncTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronize()
            }
        }
        syncTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func synchronize() {
        guard isEnabled, !isColorBarsActive else { return }
        guard let controller = attachedController else {
            teardownPipeline()
            return
        }

        guard controller.isReady,
              let mediaItem = controller.mediaItem,
              mediaItem.presentationKind != .audioOnly else {
            if isStreaming {
                destroyMPVFollower()
                detachAVVideoOutput()
                activeSource = nil
                activeEdition = nil
                if let black = converter?.makeBlackPixelBuffer() {
                    sink.submitFrame(black, smpteTime: nil)
                }
            }
            return
        }

        // If device/format wasn't started yet (e.g. file just finished preparing), start now.
        if !isStreaming {
            reconfigurePipeline()
            return
        }

        // Check if file format requires renegotiating the output resolution/rate/HDR mode.
        if let device = activeDevice {
            let sourceDescriptor = CMIOOutputSourceDescriptor.from(
                metadata: mediaItem.metadata,
                fallbackSize: controller.videoSourceSize
            )
            let caps = CMIOOutputCapabilities.evaluate(
                device: device,
                preferredResolution: resolutionMode,
                preferredScan: scanMode,
                preferredFrameRate: frameRateMode,
                preferredColor: colorMode,
                preferredPixelFormat: pixelFormatMode
            )
            if let desiredSelection = CMIOOutputFormatSelector.select(
                device: device,
                source: sourceDescriptor,
                resolutionMode: caps.effectiveResolutionMode,
                scanMode: caps.effectiveScanMode,
                frameRateMode: caps.effectiveFrameRateMode,
                colorMode: caps.effectiveColorMode,
                pixelFormatMode: caps.effectivePixelFormatMode
            ), desiredSelection != activeSelection {
                reconfigurePipeline()
                return
            }
        }

        // Update timecode snapshot for incoming frames.
        let outputFPS = activeSelection?.frameRate ?? 25.0
        let playbackTime = controller.currentPlaybackTime
        let sourceTC = mediaItem.metadata?.timecode
        let sourceFPS = mediaItem.metadata?.primaryVideoStream?.frameRate?.value
        let shouldEmbedTC = embedSMPTETimecode
        timecodeContextLock.withLock {
            $0.playbackSeconds = playbackTime
            $0.sourceStartTimecode = sourceTC
            $0.sourceFrameRate = sourceFPS
            $0.outputFrameRate = outputFPS
            $0.embedTimecode = shouldEmbedTC
        }

        let backendID: ObjectIdentifier? = controller.useMPV
            ? controller.mpvPlayer.map(ObjectIdentifier.init)
            : controller.player.map(ObjectIdentifier.init)
        let latestSource = SourceIdentity(
            preparationID: controller.preparationID,
            backend: controller.playbackBackend,
            backendID: backendID,
            url: mediaItem.url
        )

        if latestSource != activeSource {
            destroyMPVFollower()
            detachAVVideoOutput()
            activeSource = latestSource
            activeEdition = nil
            applyAudioRouting()
        }

        if controller.useMPV {
            synchronizeMPVFollower(controller: controller, url: mediaItem.url)
        } else {
            synchronizeAVPlayer(controller: controller)
        }
    }

    // MARK: - Option A: Dedicated MPV Broadcast Follower

    private func synchronizeMPVFollower(controller: PlayerController, url: URL) {
        guard let primary = controller.mpvPlayer,
              let selection = activeSelection,
              let converter else { return }

        if let currentEdition = controller.currentEditionID, currentEdition != activeEdition {
            activeEdition = currentEdition
            if followerPlayer != nil {
                destroyMPVFollower()
            }
        }

        if followerPlayer == nil {
            let layer = CleanfeedMetalLayer()
            let outputSize = CGSize(width: selection.format.width, height: selection.format.height)
            layer.frame = CGRect(origin: .zero, size: outputSize)
            layer.drawableSize = outputSize

            let sinkRef = sink
            let tcLock = timecodeContextLock
            layer.onDrawablePresented = { drawable, isLinearEDR in
                let tc = tcLock.withLock { ctx -> SMPTETime? in
                    guard ctx.embedTimecode else { return nil }
                    return CleanfeedSMPTETime.make(
                        playbackSeconds: ctx.playbackSeconds,
                        sourceStartTimecode: ctx.sourceStartTimecode,
                        sourceFrameRate: ctx.sourceFrameRate,
                        outputFrameRate: ctx.outputFrameRate
                    )
                }
                converter.convertTexture(
                    drawable.texture,
                    sourceIsLinearEDR: isLinearEDR,
                    retainedToken: drawable
                ) { pixelBuffer in
                    guard let pixelBuffer else { return }
                    sinkRef.submitFrame(pixelBuffer, smpteTime: tc)
                }
            }
            cleanfeedLayer = layer

            let effectiveDeinterlace = cleanfeedDeinterlaceMode(for: controller, outputProgressive: selection.format.isProgressive)
            let child = primary.makeCleanfeedPlayer(colorSpace: selection.colorSpace)
            child.setLooping(controller.mediaItem?.loopPlayback ?? false)
            child.setDeinterlace(effectiveDeinterlace)
            child.setPictureAdjustments(controller.pictureAdjustments)
            mirroredDeinterlace = effectiveDeinterlace
            mirroredPictureAdjustments = controller.pictureAdjustments

            followerPlayer = child
            child.attachDrawable(layer)
            child.load(
                url: url,
                startTime: max(0, controller.currentPlaybackTime),
                autostart: false,
                edition: activeEdition
            )
            return
        }

        guard let child = followerPlayer else { return }
        if let childError = child.error {
            logger.error("Cleanfeed MPV follower error: \(childError)")
            errorMessage = "Cleanfeed decoder error: \(childError)"
            destroyMPVFollower()
            return
        }
        guard child.isFileLoaded else { return }

        // Mirror live presentation settings (deinterlace & picture adjustments).
        let desiredDeinterlace = cleanfeedDeinterlaceMode(for: controller, outputProgressive: selection.format.isProgressive)
        if mirroredDeinterlace != desiredDeinterlace {
            child.setDeinterlace(desiredDeinterlace)
            mirroredDeinterlace = desiredDeinterlace
        }
        if mirroredPictureAdjustments != controller.pictureAdjustments {
            child.setPictureAdjustments(controller.pictureAdjustments)
            mirroredPictureAdjustments = controller.pictureAdjustments
        }

        let loop = controller.mediaItem?.loopPlayback ?? false
        if looping != loop {
            child.setLooping(loop)
            looping = loop
        }

        // Reverse playback: follow by seeking to primary position cleanly.
        if controller.isReversing {
            if wasPlaying == true { child.pause() }
            wasPlaying = false
            needsAlignment = true
            let primaryTime = max(0, controller.currentPlaybackTime)
            if lastPausedSeekTarget.map({ abs($0 - primaryTime) > 0.01 }) ?? true {
                child.seek(to: primaryTime)
                lastPausedSeekTarget = primaryTime
            }
            return
        }

        let playing = controller.isPlaying && controller.currentPlaybackSpeed > 0
        let nominal = max(0.01, abs(controller.currentPlaybackSpeed))
        let rate = primary.rate
        let transportChanged = playing != wasPlaying || nominal != nominalRate

        if transportChanged {
            needsAlignment = true
            child.rate = rate
            if playing {
                child.play()
                lastPausedSeekTarget = nil
            } else {
                child.pause()
            }
            wasPlaying = playing
            nominalRate = nominal
        } else if rate != baseRate {
            child.rate = rate
        }
        baseRate = rate

        if playing && !child.isPlaying && !child.isBusy {
            child.play()
        } else if !playing && child.isPlaying {
            child.pause()
        }

        // When paused, immediately mirror scrubbing or frame-stepped positions.
        if !playing {
            let primaryTime = max(0, controller.currentPlaybackTime)
            let frameStep = 1.0 / max(controller.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value ?? 25.0, 1.0)
            if lastPausedSeekTarget.map({ abs($0 - primaryTime) > frameStep * 0.35 }) ?? true {
                child.seek(to: primaryTime)
                lastPausedSeekTarget = primaryTime
                needsAlignment = false
                return
            }
        }

        // Clock-drift correction during continuous playback (mirrors LiveLoupeSession).
        guard clockTask == nil else { return }
        let currentGen = generation
        let loopDuration: TimeInterval? = loop ? primary.duration : nil
        let policy = CompareDriftPolicy(
            primaryFrameRate: controller.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
        )
        let currentSource = activeSource

        clockTask = Task { [weak self] in
            let sample = await Task.detached(priority: .userInitiated) {
                LiveLoupeClock.sample(
                    readPrimary: { primary.playbackTimeSnapshot() ?? .nan },
                    readSecondary: { child.playbackTimeSnapshot() ?? .nan },
                    loopDuration: loopDuration
                )
            }.value
            guard let self,
                  !Task.isCancelled,
                  self.isEnabled,
                  self.generation == currentGen,
                  self.followerPlayer === child,
                  self.activeSource == currentSource else { return }
            self.clockTask = nil
            guard self.wasPlaying == playing, self.baseRate == rate, primary.rate == rate else {
                self.synchronize()
                return
            }
            guard let sample else { return }

            let now = ProcessInfo.processInfo.systemUptime
            let canCorrect = now - self.lastCorrection >= CompareDriftPolicy.correctionCooldown
            let hardThreshold = max(0.25, policy.frameDuration * 8)

            if canCorrect && (self.needsAlignment || sample.effectiveDrift > hardThreshold
                || (!playing && sample.effectiveDrift > policy.correctionThreshold)) {
                child.seek(to: max(0, sample.primaryTime))
                child.rate = rate
                if playing { child.play() }
                self.lastCorrection = now
                self.needsAlignment = false
            } else if playing, !self.needsAlignment, canCorrect {
                let correction = sample.effectiveDrift > policy.correctionThreshold
                    ? min(max(sample.signedDrift * CompareDriftPolicy.rateCorrectionGain, -0.05), 0.05)
                    : 0
                let nudged = rate * Float(1 - correction)
                if abs(child.rate - nudged) > 0.001 {
                    child.rate = nudged
                }
            }
        }
    }

    /// Preserves native interlaced fields when outputting interlaced (e.g. 1080i50)
    /// from an interlaced source unless the user explicitly forced deinterlacing.
    private func cleanfeedDeinterlaceMode(
        for controller: PlayerController,
        outputProgressive: Bool
    ) -> DeinterlaceMode {
        if !outputProgressive,
           controller.deinterlaceMode == .auto,
           controller.mediaItem?.metadata?.videoStreams.first?.isInterlaced == true {
            return .off
        }
        return controller.deinterlaceMode
    }

    private func destroyMPVFollower() {
        generation &+= 1
        clockTask?.cancel()
        clockTask = nil
        cleanfeedLayer?.onDrawablePresented = nil
        followerPlayer?.destroy()
        followerPlayer = nil
        cleanfeedLayer = nil
        wasPlaying = nil
        nominalRate = nil
        baseRate = nil
        looping = nil
        mirroredDeinterlace = nil
        mirroredPictureAdjustments = nil
        lastCorrection = -.infinity
        lastPausedSeekTarget = nil
        needsAlignment = true
    }

    // MARK: - AVPlayer (ProRes RAW) Path

    private func synchronizeAVPlayer(controller: PlayerController) {
        guard let avPlayer = controller.player,
              let item = avPlayer.currentItem,
              let selection = activeSelection else {
            detachAVVideoOutput()
            return
        }

        if avOutputItem !== item || avVideoOutput == nil {
            detachAVVideoOutput()
            let pixelFormat: OSType = selection.colorSpace.isHDR
                ? kCVPixelFormatType_64RGBAHalf
                : kCVPixelFormatType_32BGRA
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
            ])
            output.suppressesPlayerRendering = false
            item.add(output)
            avVideoOutput = output
            avOutputItem = item
            lastAVCapturedTime = .invalid

            let interval = 1.0 / max(selection.frameRate, 24.0)
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pullAVPlayerFrame()
                }
            }
            avCaptureTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            pullAVPlayerFrame(force: true)
        }
    }

    private func pullAVPlayerFrame(force: Bool = false) {
        guard isEnabled,
              !isColorBarsActive,
              let output = avVideoOutput,
              let converter else { return }

        let hostTime = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: hostTime)
        guard itemTime.isValid else { return }

        let shouldPull = force
            || output.hasNewPixelBuffer(forItemTime: itemTime)
            || (!lastAVCapturedTime.isValid)
            || (abs(CMTimeGetSeconds(CMTimeSubtract(itemTime, lastAVCapturedTime))) > 0.001)
        guard shouldPull else { return }

        var displayTime = CMTime.invalid
        guard let sourceBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime),
              let converted = converter.convertPixelBuffer(sourceBuffer) else { return }

        let resolvedSeconds: Double? = displayTime.isValid ? CMTimeGetSeconds(displayTime) : nil
        lastAVCapturedTime = displayTime.isValid ? displayTime : itemTime
        let smpte: SMPTETime? = timecodeContextLock.withLock { ctx in
            guard ctx.embedTimecode else { return nil }
            let seconds = resolvedSeconds ?? ctx.playbackSeconds
            return CleanfeedSMPTETime.make(
                playbackSeconds: max(0, seconds),
                sourceStartTimecode: ctx.sourceStartTimecode,
                sourceFrameRate: ctx.sourceFrameRate,
                outputFrameRate: ctx.outputFrameRate
            )
        }
        sink.submitFrame(converted, smpteTime: smpte)
    }

    private func detachAVVideoOutput() {
        avCaptureTimer?.invalidate()
        avCaptureTimer = nil
        if let output = avVideoOutput, let item = avOutputItem {
            item.remove(output)
        }
        avVideoOutput = nil
        avOutputItem = nil
        lastAVCapturedTime = .invalid
    }

    // MARK: - Audio Routing

    private func applyAudioRouting() {
        guard let controller = attachedController else {
            restoreAudioRouting()
            return
        }
        if audioRoutedController !== controller {
            restoreAudioRouting()
        }

        if isEnabled,
           isStreaming,
           routeAudioToDevice,
           let audioUID = activeDevice?.linkedCoreAudioDeviceUID {
            controller.setAudioOutputDevice(coreAudioUID: audioUID)
            audioRoutedController = controller
        } else {
            controller.setAudioOutputDevice(coreAudioUID: nil)
            if audioRoutedController === controller {
                audioRoutedController = nil
            }
        }
    }

    private func restoreAudioRouting() {
        audioRoutedController?.setAudioOutputDevice(coreAudioUID: nil)
        audioRoutedController = nil
    }

    // MARK: - Color Bars Helper

    private func emitNextColorBarsFrame() {
        guard isColorBarsActive, let converter, let selection = activeSelection else { return }
        guard let pb = converter.makeColorBarsPixelBuffer(frameIndex: colorBarsFrameIndex) else { return }
        let seconds = Double(colorBarsFrameIndex) / max(selection.frameRate, 1.0)
        let tc = embedSMPTETimecode
            ? CleanfeedSMPTETime.make(
                playbackSeconds: seconds,
                sourceStartTimecode: "01:00:00:00",
                sourceFrameRate: selection.frameRate,
                outputFrameRate: selection.frameRate
            )
            : nil
        sink.submitFrame(pb, smpteTime: tc)
        colorBarsFrameIndex += 1
    }
}
