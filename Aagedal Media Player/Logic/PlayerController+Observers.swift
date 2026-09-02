// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Observer management for PlayerController (loop, playback time, player item status).

import Foundation
import AVKit
import OSLog

/// Identifies the exact AVFoundation playback preparation that installed an
/// observer. Removing a KVO or NotificationCenter observer does not retract
/// callbacks already queued onto the main actor, so every queued callback must
/// also prove that its source player and item still belong to the active
/// preparation before publishing state.
struct AVPlaybackObservationIdentity: Equatable, Sendable {
    let preparationID: Int
    let playerID: ObjectIdentifier?
    let playerItemID: ObjectIdentifier?

    @MainActor
    init(preparationID: Int, player: AVPlayer?, playerItem: AVPlayerItem?) {
        self.preparationID = preparationID
        playerID = player.map(ObjectIdentifier.init)
        playerItemID = playerItem.map(ObjectIdentifier.init)
    }

    @MainActor
    func matches(
        preparationID: Int,
        player: AVPlayer?,
        playerItem: AVPlayerItem?
    ) -> Bool {
        self.preparationID == preparationID
            && playerID == player.map(ObjectIdentifier.init)
            && playerItemID == playerItem.map(ObjectIdentifier.init)
    }
}

/// Identifies the exact MPV preparation that installed a publisher bridge.
/// MPV property changes are dispatched to the main queue, so cancelling a
/// subscription during teardown is not sufficient proof that an already
/// queued value belongs to the replacement backend.
struct MPVPlaybackObservationIdentity: Equatable, Sendable {
    let preparationID: Int
    let playerID: ObjectIdentifier?

    init(preparationID: Int, player: MPVPlayer?) {
        self.preparationID = preparationID
        playerID = player.map(ObjectIdentifier.init)
    }

    func matches(preparationID: Int, player: MPVPlayer?) -> Bool {
        self.preparationID == preparationID
            && playerID == player.map(ObjectIdentifier.init)
    }
}

extension PlayerController {

    private func isCurrent(_ identity: AVPlaybackObservationIdentity) -> Bool {
        identity.matches(
            preparationID: preparationID,
            player: player,
            playerItem: player?.currentItem
        )
    }

    // MARK: - Loop Observer

    func installLoopObserver(for item: AVPlayerItem) {
        removeLoopObserver()
        let identity = AVPlaybackObservationIdentity(
            preparationID: preparationID,
            player: player,
            playerItem: item
        )
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(identity) else { return }
                self.handlePlaybackEnded(identity: identity)
            }
        }

        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?
                .localizedDescription
                ?? "AVFoundation could not finish playing this file."
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(identity) else { return }
                self.reportPlaybackFailure(
                    backend: .avFoundation,
                    stage: .playback,
                    message: message
                )
            }
        }
    }

    func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
            self.playbackFailureObserver = nil
        }
    }

    private func handlePlaybackEnded(identity: AVPlaybackObservationIdentity) {
        guard let item = mediaItem, let observedPlayer = player else { return }

        if item.loopPlayback {
            let target = CMTime(seconds: 0, preferredTimescale: 600)
            observedPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak observedPlayer] _ in
                Task { @MainActor [weak self, weak observedPlayer] in
                    guard let self,
                          let observedPlayer,
                          self.isCurrent(identity) else { return }
                    observedPlayer.play()
                }
            }
        } else if currentPlaybackSpeed != 1.0 {
            // Reset speed when fast/slow playback reaches the end
            resetPlaybackSpeed()
        }
    }

    func updatePlayerActionAtEnd() {
        guard let item = mediaItem else { return }
        player?.actionAtItemEnd = item.loopPlayback ? .none : .pause
    }

    // MARK: - MPV Loop Observer

    func installMPVLoopObserver() {
        removeMPVLoopObserver()

        guard useMPV, let observedMPV = mpvPlayer else { return }
        let observedPreparationID = preparationID

        mpvLoopObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self, weak observedMPV] in
                guard let self,
                      let observedMPV,
                      self.preparationID == observedPreparationID,
                      self.mpvPlayer === observedMPV else { return }
                let mpv = observedMPV
                guard let item = self.mediaItem else { return }

                let currentTime = mpv.timePos
                let duration = item.durationSeconds
                let tolerance = 0.05

                if duration > 0, currentTime >= duration - tolerance {
                    if item.loopPlayback {
                        let wasPlaying = mpv.isPlaying
                        mpv.seek(to: 0)
                        if wasPlaying {
                            mpv.play()
                        }
                    } else if self.currentPlaybackSpeed != 1.0 {
                        // Pause and reset speed at end of file
                        mpv.pause()
                        self.resetPlaybackSpeed()
                    }
                }
            }
        }
    }

    func removeMPVLoopObserver() {
        mpvLoopObserverTimer?.invalidate()
        mpvLoopObserverTimer = nil
    }

    // MARK: - Playback Time Observer (UI Updates)

    func installPlaybackTimeObserver(for player: AVPlayer) {
        removePlaybackTimeObserver()

        let identity = AVPlaybackObservationIdentity(
            preparationID: preparationID,
            player: player,
            playerItem: player.currentItem
        )
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        playbackTimeObserverOwner = player
        playbackTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(identity) else { return }
                let currentTime = time.seconds
                if currentTime.isFinite {
                    self.currentPlaybackTime = currentTime
                }
                // Detect native reverse reaching the beginning
                if self.isNativeReverse && (self.player?.rate ?? 0) == 0 {
                    self.stopReverse()
                }
            }
        }
    }

    func removePlaybackTimeObserver() {
        if let playbackTimeObserver {
            let owner = playbackTimeObserverOwner ?? player
            owner?.removeTimeObserver(playbackTimeObserver)
            self.playbackTimeObserver = nil
            self.playbackTimeObserverOwner = nil
        }
    }

    // MARK: - Time Control Status Observer (live play/pause state)

    func installTimeControlStatusObserver(for player: AVPlayer) {
        removeTimeControlStatusObserver()

        let identity = AVPlaybackObservationIdentity(
            preparationID: preparationID,
            player: player,
            playerItem: player.currentItem
        )
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(identity) else { return }
                self.syncIsPlaying()
                self.updateBufferingState(
                    player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                )
            }
        }
    }

    func removeTimeControlStatusObserver() {
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
    }

    // MARK: - Player Item Status Observer

    func installPlayerItemStatusObserver(for playerItem: AVPlayerItem, startTime: TimeInterval) {
        removePlayerItemStatusObserver()

        let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "PlayerController")
        let observedPlayer = player
        let identity = AVPlaybackObservationIdentity(
            preparationID: preparationID,
            player: observedPlayer,
            playerItem: playerItem
        )

        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Bail out if a newer preparePlayback has started since this
                // observer was installed — the player item is stale.
                guard self.isCurrent(identity) else { return }

                switch item.status {
                case .failed:
                    let failureDescription = item.error?.localizedDescription ?? "unknown error"
                    logger.warning("AVPlayer playback failed: \(failureDescription, privacy: .public)")

                    if let error = item.error as NSError? {
                        logger.warning("AVPlayer error – domain: \(error.domain, privacy: .public), code: \(error.code, privacy: .public)")
                    }

                    self.reportPlaybackFailure(
                        backend: .avFoundation,
                        stage: .loading,
                        message: failureDescription
                    )

                case .readyToPlay:
                    let asset = item.asset

                    Task {
                        do {
                            let videoTracks = try await asset.loadTracks(withMediaType: .video)
                            // Re-check after each await — a new file may have been loaded
                            guard self.isCurrent(identity) else { return }
                            guard self.playbackFailure == nil else { return }

                            if !videoTracks.isEmpty {
                                var hasValidVideoFormat = false
                                for track in videoTracks {
                                    let formatDescriptions = try await track.load(.formatDescriptions) as [CMFormatDescription]
                                    guard self.isCurrent(identity) else { return }
                                    if !formatDescriptions.isEmpty {
                                        hasValidVideoFormat = true
                                        break
                                    }
                                }
                                guard self.isCurrent(identity) else { return }

                                if !hasValidVideoFormat {
                                    self.reportPlaybackFailure(
                                        backend: .avFoundation,
                                        stage: .loading,
                                        message: "The file's video format could not be read by AVFoundation."
                                    )
                                    return
                                }

                                for track in videoTracks {
                                    let isDecodable = try await track.load(.isDecodable)
                                    guard self.isCurrent(identity) else { return }
                                    if !isDecodable {
                                        self.reportPlaybackFailure(
                                            backend: .avFoundation,
                                            stage: .loading,
                                            message: "AVFoundation cannot decode this file's video track."
                                        )
                                        return
                                    }
                                }
                            }

                            guard self.isCurrent(identity) else { return }
                            guard self.playbackFailure == nil else { return }

                            // Window aspect/source size come from MetadataService via
                            // updateMetadata() now — no need to derive them from AVAsset
                            // here. (This branch only runs for ProRes RAW since MPV is
                            // the default backend for everything else.)

                            // Populate duration from AVPlayer so the timeline is usable before metadata finishes
                            let avDuration = try await asset.load(.duration)
                            guard self.isCurrent(identity) else { return }
                            guard self.playbackFailure == nil else { return }
                            let seconds = CMTimeGetSeconds(avDuration)
                            if seconds.isFinite, seconds > 0, (self.mediaItem?.durationSeconds ?? 0) == 0 {
                                self.mediaItem?.durationSeconds = seconds
                            }

                            self.markPlaybackReady(
                                isBuffering: observedPlayer?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                            )
                            self.canNativeReverse = item.canPlayReverse
                            self.canNativeSlowReverse = item.canPlaySlowReverse

                            if let observedPlayer {
                                let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
                                await observedPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                                guard self.isCurrent(identity) else { return }
                            }

                            self.applySelectedAudioTrack()

                        } catch {
                            guard self.isCurrent(identity) else { return }
                            guard self.playbackFailure == nil else { return }
                            logger.debug("Could not verify video tracks, proceeding with playback")

                            // Try to get duration even if track verification failed
                            if let dur = try? await asset.load(.duration) {
                                guard self.isCurrent(identity) else { return }
                                let seconds = CMTimeGetSeconds(dur)
                                if seconds.isFinite, seconds > 0, (self.mediaItem?.durationSeconds ?? 0) == 0 {
                                    self.mediaItem?.durationSeconds = seconds
                                }
                            }
                            guard self.isCurrent(identity) else { return }

                            self.markPlaybackReady(
                                isBuffering: observedPlayer?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                            )
                            self.canNativeReverse = item.canPlayReverse
                            self.canNativeSlowReverse = item.canPlaySlowReverse

                            if let observedPlayer {
                                let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
                                await observedPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                                guard self.isCurrent(identity) else { return }
                            }

                            self.applySelectedAudioTrack()
                        }
                    }

                case .unknown:
                    break

                @unknown default:
                    break
                }
            }
        }
    }

    func removePlayerItemStatusObserver() {
        if let playerItemStatusObserver {
            (playerItemStatusObserver as? NSKeyValueObservation)?.invalidate()
            self.playerItemStatusObserver = nil
        }
    }
}
