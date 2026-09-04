// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Foundation

/// Common transport and lifecycle surface for the app's playback engines.
///
/// The concrete player objects remain exposed for rendering and the few
/// backend-specific capabilities that cannot be expressed uniformly (track
/// discovery, reverse playback, and scope capture). PlayerController uses this
/// abstraction for shared playback, audio, seeking, and teardown behavior.
@MainActor
protocol PlayerBackendAdapter: AnyObject {
    var backend: PlaybackBackend { get }
    var avPlayer: AVPlayer? { get }
    var mpvPlayer: MPVPlayer? { get }
    var isPlaying: Bool { get }
    var isPaused: Bool { get }
    var rate: Float { get set }
    var volume: Double { get set }
    var isMuted: Bool { get set }

    func setAudioChannelRouting(_ routing: AudioChannelRouting)

    func play()
    func pause()
    func seek(to time: TimeInterval)
    func teardown()
}

@MainActor
final class AVFoundationPlayerBackend: PlayerBackendAdapter {
    let player: AVPlayer
    private var hasAudioChannelRouting = false

    let backend: PlaybackBackend = .avFoundation
    var avPlayer: AVPlayer? { player }
    var mpvPlayer: MPVPlayer? { nil }
    var isPlaying: Bool { player.timeControlStatus == .playing }
    var isPaused: Bool { player.rate == 0 }
    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }
    var volume: Double {
        get { Double(player.volume) * 100 }
        set { player.volume = Float(newValue / 100) }
    }
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    init(url: URL, volume: Double, isMuted: Bool) {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        self.volume = volume
        self.isMuted = isMuted
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setAudioChannelRouting(_ routing: AudioChannelRouting) {
        guard !routing.isBypassed || hasAudioChannelRouting else { return }
        AVAudioChannelRouter.apply(routing, to: player.currentItem)
        hasAudioChannelRouting = !routing.isBypassed
    }

    func teardown() {
        player.isMuted = true
        player.rate = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

@MainActor
final class MPVPlayerBackend: PlayerBackendAdapter {
    let player: MPVPlayer

    let backend: PlaybackBackend = .mpv
    var avPlayer: AVPlayer? { nil }
    var mpvPlayer: MPVPlayer? { player }
    var isPlaying: Bool { player.isPlaying }
    var isPaused: Bool { !player.isPlaying }
    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }
    var volume: Double {
        get { player.volume }
        set { player.volume = newValue }
    }
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    init(url: URL, startTime: TimeInterval, volume: Double, isMuted: Bool) {
        player = MPVPlayer()
        self.volume = volume
        self.isMuted = isMuted
        player.load(url: url, startTime: startTime, autostart: false)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        player.seek(to: time)
    }

    func setAudioChannelRouting(_ routing: AudioChannelRouting) {
        player.setAudioChannelRouting(routing)
    }

    func teardown() {
        player.destroy()
    }
}

/// Pure routing rules used before constructing a playback backend.
nonisolated enum PlaybackBackendSelector {
    static func backend(codec: String?, pixelFormat: String?) -> PlaybackBackend {
        if pixelFormat?.lowercased().contains("bayer") == true {
            return .avFoundation
        }

        let normalizedCodec = codec?.lowercased()
        if normalizedCodec?.contains("aprn") == true || normalizedCodec?.contains("aprh") == true {
            return .avFoundation
        }

        return .mpv
    }

    @MainActor
    static func backend(metadata: MediaMetadata?) -> PlaybackBackend? {
        guard let stream = metadata?.primaryVideoStream else { return nil }
        return backend(codec: stream.codec, pixelFormat: stream.pixelFormat)
    }
}
