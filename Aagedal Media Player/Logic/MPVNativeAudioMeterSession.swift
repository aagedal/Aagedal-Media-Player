// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

protocol MPVNativeAudioProbeClient: AnyObject, Sendable {
    nonisolated func beginNativeAudioProbe(owner: UUID) -> Bool
    nonisolated func readNativeAudioProbe(owner: UUID, channels: Int, sampleRate: Int) async -> MPVNativeAudioMeter.Reading?
    nonisolated func endNativeAudioProbe(owner: UUID)
}

/// One optional, panel-owned comparison probe. The source meter remains the
/// authority. At most one query is in flight; cancellation invalidates its token
/// before removing this session's filter. No sample/history queue is retained.
@MainActor
final class MPVNativeAudioMeterSession: ObservableObject {
    struct State: Equatable {
        var status: String
        var reading: MPVNativeAudioMeter.Reading?
    }

    @Published private(set) var state: State?
    private let enabled: Bool
    private weak var player: (any MPVNativeAudioProbeClient)?
    private var owner: UUID?
    private var query: Task<Void, Never>?
    private var lastQuery = ContinuousClock.now
    private var attemptedPlayer: ObjectIdentifier?
    private var started = ContinuousClock.now

    init(enabled: Bool = ProcessInfo.processInfo.environment["AAGEDAL_MPV_AUDIO_PROBE"] == "1") {
        self.enabled = enabled
        if enabled { state = State(status: "Play a single MPV audio track to compare filters.") }
    }

    deinit {
        query?.cancel()
        if let owner { player?.endNativeAudioProbe(owner: owner) }
    }

    func reset(_ status: String = "Playback probe reset; source meter remains active.") {
        query?.cancel()
        query = nil
        let oldOwner = owner
        owner = nil
        if let oldOwner { player?.endNativeAudioProbe(owner: oldOwner) }
        player = nil
        attemptedPlayer = nil
        if enabled { state = State(status: status) }
    }

    func update(player next: (any MPVNativeAudioProbeClient)?, format: LiveAudioMeterFormat?, eligible: Bool) {
        guard enabled else { return }
        guard eligible, let next, let format else {
            if owner != nil || attemptedPlayer != nil { reset("Playback probe inactive; source meter remains active.") }
            return
        }
        if let player, player !== next { reset() }
        if owner == nil {
            guard attemptedPlayer != ObjectIdentifier(next) else { return }
            attemptedPlayer = ObjectIdentifier(next)
            let token = UUID()
            guard next.beginNativeAudioProbe(owner: token) else {
                state = State(status: "Native filters unavailable; using the existing source meter.")
                return
            }
            player = next
            owner = token
            started = .now
            state = State(status: "Waiting for native filter metadata…")
        }
        guard query == nil, let token = owner,
              lastQuery.duration(to: .now) >= .milliseconds(100) else { return }
        lastQuery = .now
        query = Task { [weak self, weak next] in
            guard let next else { return }
            let reading = await next.readNativeAudioProbe(
                owner: token, channels: format.channelCount, sampleRate: format.sampleRate
            )
            guard !Task.isCancelled, let self, self.owner == token else { return }
            self.query = nil
            if let reading {
                self.state = State(status: "Native playback filter · approximate comparison", reading: reading)
            } else if self.started.duration(to: .now) > .seconds(2) {
                self.reset("Native metadata unavailable; using the existing source meter.")
                self.attemptedPlayer = ObjectIdentifier(next)
            } else {
                self.state = State(status: "Waiting for native filter metadata…")
            }
        }
    }
}
