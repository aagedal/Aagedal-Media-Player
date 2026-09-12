// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Typed playback discontinuities which must never share a live-meter DSP
/// segment. The player integration publishes these explicitly instead of
/// attempting to infer user actions from ordinary clock movement.
nonisolated enum LiveAudioMeterPlaybackDiscontinuity: Equatable, Sendable {
    case seek
    case frameStep
    case scrub
    case loopWrap
    case geometryReload
    case sourceReplacement
    case audioTrackReplacement
}

/// One atomic observation of the measured player's source clock and transport.
/// `time` is always the measured source's local timeline, including for B in a
/// comparison session; it is not the comparison's shared A timeline.
nonisolated struct LiveAudioMeterPlaybackSnapshot: Equatable, Sendable {
    let time: TimeInterval
    let phase: PlaybackPhase
    let isPlaying: Bool
    let rate: Float
    let preparationID: Int

    var supportsMeasurement: Bool {
        rate.isFinite && abs(rate - 1) <= 0.000_1
    }
}

/// Events emitted by a playback owner and consumed by the future window-owned
/// meter session. A current snapshot is read when subscribing, so the event
/// stream does not need to replay historical clock ticks.
nonisolated enum LiveAudioMeterPlaybackEvent: Equatable, Sendable {
    case clock(LiveAudioMeterPlaybackSnapshot)
    case transport(LiveAudioMeterPlaybackSnapshot)
    case discontinuity(
        LiveAudioMeterPlaybackDiscontinuity,
        snapshot: LiveAudioMeterPlaybackSnapshot
    )
    case scrubbing(LiveAudioMeterPlaybackSnapshot)
    case ended(LiveAudioMeterPlaybackSnapshot)
}

/// Pure decoded-versus-player clock policy. The 250-ms hard limit matches the
/// live-meter contract's maximum queued-ahead work and snapshot-age target.
/// An earlier suspend threshold leaves one 50-ms peak bucket of headroom; the
/// lower resume threshold prevents process stop/start chatter.
nonisolated struct LiveAudioMeterClockPolicy: Equatable, Sendable {
    enum Assessment: Equatable, Sendable {
        case synchronized(drift: TimeInterval)
        case suspendAhead(drift: TimeInterval)
        case resume(drift: TimeInterval)
        case failed(drift: TimeInterval)
        case invalidClock
    }

    static let maximumDrift: TimeInterval = 0.250
    static let suspendAheadThreshold: TimeInterval = 0.200
    static let resumeAheadThreshold: TimeInterval = 0.100

    let sampleRate: Int

    init(sampleRate: Int) {
        self.sampleRate = sampleRate
    }

    func assess(
        decodedEndFrame: Int64,
        playbackTime: TimeInterval,
        isSuspendedAhead: Bool
    ) -> Assessment {
        guard sampleRate > 0, decodedEndFrame >= 0,
              playbackTime.isFinite, playbackTime >= 0 else {
            return .invalidClock
        }
        let rate = Double(sampleRate)
        let playbackFrame = playbackTime * rate
        guard playbackFrame.isFinite else { return .invalidClock }
        let driftFrames = Double(decodedEndFrame) - playbackFrame
        let drift = driftFrames / rate
        guard abs(driftFrames) <= Self.maximumDrift * rate else {
            return .failed(drift: drift)
        }
        if isSuspendedAhead {
            return driftFrames <= Self.resumeAheadThreshold * rate
                ? .resume(drift: drift)
                : .suspendAhead(drift: drift)
        }
        return driftFrames >= Self.suspendAheadThreshold * rate
            ? .suspendAhead(drift: drift)
            : .synchronized(drift: drift)
    }
}
