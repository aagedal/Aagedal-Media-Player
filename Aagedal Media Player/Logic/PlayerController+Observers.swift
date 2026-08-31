// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Observer management for PlayerController (loop, playback time, player item status).

import Foundation
import AVKit
import OSLog

extension PlayerController {

    // MARK: - Loop Observer

    func installLoopObserver(for item: AVPlayerItem) {
        removeLoopObserver()
        let myPrepID = preparationID
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded()
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
                guard let self else { return }
                guard self.preparationID == myPrepID else { return }
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

    func handlePlaybackEnded() {
        guard let item = mediaItem, let player else { return }

        if item.loopPlayback {
            let target = CMTime(seconds: 0, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
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

        guard useMPV, mpvPlayer != nil else { return }

        mpvLoopObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let mpv = self.mpvPlayer else { return }
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

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        playbackTimeObserverOwner = player
        playbackTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
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

        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
        let myPrepID = self.preparationID

        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Bail out if a newer preparePlayback has started since this
                // observer was installed — the player item is stale.
                guard self.preparationID == myPrepID else { return }

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
                            guard self.preparationID == myPrepID else { return }
                            guard self.playbackFailure == nil else { return }

                            if !videoTracks.isEmpty {
                                var hasValidVideoFormat = false
                                for track in videoTracks {
                                    let formatDescriptions = try await track.load(.formatDescriptions) as [CMFormatDescription]
                                    if !formatDescriptions.isEmpty {
                                        hasValidVideoFormat = true
                                        break
                                    }
                                }
                                guard self.preparationID == myPrepID else { return }

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
                                    guard self.preparationID == myPrepID else { return }
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

                            guard self.preparationID == myPrepID else { return }
                            guard self.playbackFailure == nil else { return }

                            // Window aspect/source size come from MetadataService via
                            // updateMetadata() now — no need to derive them from AVAsset
                            // here. (This branch only runs for ProRes RAW since MPV is
                            // the default backend for everything else.)

                            // Populate duration from AVPlayer so the timeline is usable before metadata finishes
                            let avDuration = try await asset.load(.duration)
                            guard self.preparationID == myPrepID else { return }
                            guard self.playbackFailure == nil else { return }
                            let seconds = CMTimeGetSeconds(avDuration)
                            if seconds.isFinite, seconds > 0, (self.mediaItem?.durationSeconds ?? 0) == 0 {
                                self.mediaItem?.durationSeconds = seconds
                            }

                            self.markPlaybackReady(
                                isBuffering: self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                            )
                            self.canNativeReverse = item.canPlayReverse
                            self.canNativeSlowReverse = item.canPlaySlowReverse

                            if let player = self.player {
                                let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
                                await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            }

                            self.applySelectedAudioTrack()

                        } catch {
                            guard self.preparationID == myPrepID else { return }
                            guard self.playbackFailure == nil else { return }
                            logger.debug("Could not verify video tracks, proceeding with playback")

                            // Try to get duration even if track verification failed
                            if let dur = try? await asset.load(.duration) {
                                let seconds = CMTimeGetSeconds(dur)
                                if seconds.isFinite, seconds > 0, (self.mediaItem?.durationSeconds ?? 0) == 0 {
                                    self.mediaItem?.durationSeconds = seconds
                                }
                            }

                            self.markPlaybackReady(
                                isBuffering: self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                            )
                            self.canNativeReverse = item.canPlayReverse
                            self.canNativeSlowReverse = item.canPlaySlowReverse

                            if let player = self.player {
                                let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
                                await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
