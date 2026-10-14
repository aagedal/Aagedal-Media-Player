// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine

/// MPV pan is measured in fractions of the entire zoomed picture, independent
/// of the small output surface. This reproduces the still loupe's placement,
/// including black outside the picture when inspecting an edge.
nonisolated struct LoupeVideoViewport: Equatable, Sendable {
    let zoom: Double
    let panX: Double
    let panY: Double

    init?(pictureSize: CGSize, lensSize: CGSize, normalizedPoint: CGPoint,
          magnification: LoupeMagnification) {
        guard let factor = magnification.factor,
              pictureSize.width.isFinite, pictureSize.height.isFinite,
              lensSize.width.isFinite, lensSize.height.isFinite,
              pictureSize.width > 0, pictureSize.height > 0,
              lensSize.width > 0, lensSize.height > 0 else { return nil }
        let fit = min(lensSize.width / pictureSize.width, lensSize.height / pictureSize.height)
        zoom = log2(Double(factor / fit))
        panX = 0.5 - Double(normalizedPoint.x.isFinite ? min(max(normalizedPoint.x, 0), 1) : 0.5)
        panY = 0.5 - Double(normalizedPoint.y.isFinite ? min(max(normalizedPoint.y, 0), 1) : 0.5)
    }
}

nonisolated enum LiveLoupeClock {
    /// Compare loop phase across EOF without treating a one-frame difference
    /// across the wrap as an entire file's worth of drift. A primary clock
    /// bracket that crosses the wrap is ambiguous and is sampled again later.
    static func sample(readPrimary: () -> TimeInterval, readSecondary: () -> TimeInterval,
                       loopDuration: TimeInterval?) -> CompareDriftSample? {
        let duration = loopDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var firstPrimary: TimeInterval?
        var secondary = TimeInterval.nan
        return CompareDriftSample(readPrimary: {
            let time = readPrimary()
            if let duration, let firstPrimary, abs(time - firstPrimary) > duration / 2 { return .nan }
            firstPrimary = time
            return time
        }, readSecondary: {
            secondary = readSecondary()
            return secondary
        }, mapSecondaryTime: { time in
            guard let duration else { return time }
            return time + ((secondary - time) / duration).rounded() * duration
        })
    }
}

/// A silent second player for the live loupe. Its only connection to the main
/// player is transport/clock following; no image readback occurs here.
@MainActor
final class LiveLoupeSession: ObservableObject {
    @Published private(set) var player: MPVPlayer?
    @Published private(set) var isReady = false
    @Published private(set) var error: String?
    private weak var controller: PlayerController?
    private weak var surface: MPVMetalLayer?
    private var observation: AnyCancellable?
    private nonisolated(unsafe) var timer: Timer?
    private var clockTask: Task<Void, Never>?
    private var surfaceReloadTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var isRunning = false
    private var source: Source?
    private var failedSource: Source?
    private var viewport: LoupeVideoViewport?
    private var nearest = true
    private var wasPlaying: Bool?
    private var baseRate: Float?
    private var looping: Bool?
    private var lastCorrection: TimeInterval = -.infinity
    private var needsAlignment = true
    // An MPV handle owns an unmanaged self-retain. Also clean it up if a host
    // disappears without delivering SwiftUI's onDisappear.
    private nonisolated(unsafe) var cleanupPlayer: MPVPlayer?

    private struct Source: Equatable {
        let preparationID: Int
        let backend: ObjectIdentifier
        let url: URL
    }

    deinit {
        timer?.invalidate()
        let player = cleanupPlayer
        Task { @MainActor in player?.destroy() }
    }

    static func supportsPlayback(_ controller: PlayerController) -> Bool {
        controller.useMPV && controller.isReady && controller.isPlaying
            && !controller.isReversing && controller.currentPlaybackSpeed > 0
    }

    func isReady(for controller: PlayerController) -> Bool {
        guard isReady, self.controller === controller, let source,
              let primary = controller.mpvPlayer else { return false }
        return source.preparationID == controller.preparationID
            && source.backend == ObjectIdentifier(primary) && source.url == controller.mediaItem?.url
    }

    func start(controller: PlayerController) {
        if self.controller === controller, isRunning { synchronize(); return }
        let attachedSurface = surface
        stop()
        surface = attachedSurface
        self.controller = controller
        isRunning = true
        observation = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.synchronize() }
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronize()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        synchronize()
    }

    func stop() {
        isRunning = false
        generation &+= 1
        timer?.invalidate()
        timer = nil
        observation = nil
        clockTask?.cancel()
        clockTask = nil
        destroyPlayer()
        source = nil
        failedSource = nil
        surface = nil
        controller = nil
        error = nil
    }

    func configure(viewport: LoupeVideoViewport, nearest: Bool) {
        self.viewport = viewport
        self.nearest = nearest
        player?.configureLiveLoupe(viewport: viewport, nearest: nearest)
    }

    func attachSurface(_ layer: MPVMetalLayer) {
        guard surface !== layer else { return }
        surface = layer
        guard isRunning else { return }
        // wid cannot migrate to a different layer. Recreate only this decoder,
        // leaving the main player and its transport untouched.
        if player != nil { destroyPlayer() }
        synchronize()
    }

    func detachSurface(_ layer: MPVMetalLayer) {
        guard surface === layer else { return }
        surface = nil
        destroyPlayer()
    }

    func surfaceSizeChanged() {
        guard isRunning, player != nil, let surface else { return }
        surfaceReloadTask?.cancel()
        let generation = self.generation
        // The layer can resize while gpu-next retains its previous output
        // rectangle. Coalesce layout changes, then rebuild just the follower
        // against the settled drawable size, as the primary surface does.
        surfaceReloadTask = Task { @MainActor [weak self, weak surface] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, self.isRunning,
                  self.generation == generation, self.surface === surface else { return }
            self.surfaceReloadTask = nil
            self.destroyPlayer()
            self.synchronize()
        }
    }

    private func destroyPlayer() {
        generation &+= 1
        surfaceReloadTask?.cancel()
        surfaceReloadTask = nil
        clockTask?.cancel()
        clockTask = nil
        player?.destroy()
        player = nil
        cleanupPlayer = nil
        isReady = false
        wasPlaying = nil
        baseRate = nil
        looping = nil
        needsAlignment = true
        lastCorrection = -.infinity
    }

    private func synchronize() {
        guard isRunning, let controller else { return }
        let latest: Source?
        if controller.useMPV, controller.isReady, let primary = controller.mpvPlayer,
           let url = controller.mediaItem?.url {
            latest = Source(preparationID: controller.preparationID, backend: ObjectIdentifier(primary), url: url)
        } else { latest = nil }
        if latest != source {
            destroyPlayer()
            source = latest
            failedSource = nil
            error = nil
        }
        guard let source, let primary = controller.mpvPlayer, let surface,
              source != failedSource else { return }
        if player == nil {
            let child = primary.makeLiveLoupePlayer()
            player = child
            cleanupPlayer = child
            if let viewport { child.configureLiveLoupe(viewport: viewport, nearest: nearest) }
            child.setLooping(controller.mediaItem?.loopPlayback ?? false)
            child.attachDrawable(surface)
            child.load(url: source.url, startTime: max(0, controller.currentPlaybackTime), autostart: false)
        }
        guard let child = player else { return }
        if let message = child.error {
            failedSource = source
            destroyPlayer()
            error = message
            return
        }
        guard child.isFileLoaded, child.videoSourceSize != nil else { return }
        let loop = controller.mediaItem?.loopPlayback ?? false
        if looping != loop { child.setLooping(loop); looping = loop }
        if controller.isReversing {
            if wasPlaying == true { child.pause() }
            wasPlaying = false
            isReady = false
            needsAlignment = true
            return
        }
        let playing = Self.supportsPlayback(controller)
        let rate = max(0.01, abs(controller.currentPlaybackSpeed))
        let transportChanged = playing != wasPlaying || rate != baseRate
        if transportChanged {
            needsAlignment = true
            isReady = false
            child.rate = rate
            if playing { child.play() } else { child.pause() }
            wasPlaying = playing
            baseRate = rate
        }
        // EOF or buffering can stop the follower independently of the primary.
        if playing && !child.isPlaying && !child.isBusy { child.play() }
        else if !playing && child.isPlaying { child.pause() }
        guard clockTask == nil else { return }
        let generation = self.generation
        let loopDuration: TimeInterval? = loop ? primary.duration : nil
        let policy = CompareDriftPolicy(primaryFrameRate: controller.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value)
        clockTask = Task { [weak self] in
            let sample = await Task.detached(priority: .userInitiated) {
                LiveLoupeClock.sample(
                    readPrimary: { primary.playbackTimeSnapshot() ?? .nan },
                    readSecondary: { child.playbackTimeSnapshot() ?? .nan },
                    loopDuration: loopDuration)
            }.value
            guard let self, !Task.isCancelled, self.isRunning,
                  self.generation == generation, self.player === child,
                  self.source == source else { return }
            self.clockTask = nil
            guard self.wasPlaying == playing, self.baseRate == rate else {
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
                if sample.effectiveDrift > hardThreshold { self.isReady = false }
            } else if !self.needsAlignment && sample.effectiveDrift <= max(0.05, policy.frameDuration * 2) {
                self.isReady = true
            }
            if playing, !self.needsAlignment, now - self.lastCorrection >= CompareDriftPolicy.correctionCooldown {
                let correction = sample.effectiveDrift > policy.correctionThreshold
                    ? min(max(sample.signedDrift * CompareDriftPolicy.rateCorrectionGain, -0.05), 0.05) : 0
                let nudged = rate * Float(1 - correction)
                if abs(child.rate - nudged) > 0.001 { child.rate = nudged }
            }
        }
    }
}
