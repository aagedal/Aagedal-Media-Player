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
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded()
            }
        }
    }

    func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }

    func handlePlaybackEnded() {
        guard let item = mediaItem, item.loopPlayback, let player else { return }
        let target = CMTime(seconds: 0, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
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
                guard let item = self.mediaItem, item.loopPlayback else { return }

                let currentTime = mpv.timePos
                let duration = item.durationSeconds
                let tolerance = 0.05

                if duration > 0, currentTime >= duration - tolerance {
                    let wasPlaying = mpv.isPlaying
                    mpv.seek(to: 0)
                    if wasPlaying {
                        mpv.play()
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

    // MARK: - Player Item Status Observer

    func installPlayerItemStatusObserver(for playerItem: AVPlayerItem, startTime: TimeInterval) {
        removePlayerItemStatusObserver()

        let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "PlayerController")

        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch item.status {
                case .failed:
                    let failureDescription = item.error?.localizedDescription ?? "unknown error"
                    logger.warning("AVPlayer playback failed: \(failureDescription, privacy: .public). Attempting MPV fallback.")

                    if let error = item.error as NSError? {
                        logger.warning("AVPlayer error – domain: \(error.domain, privacy: .public), code: \(error.code, privacy: .public)")
                    }

                    guard let item = self.mediaItem else { return }
                    self.teardown(resetAudioSelection: false)
                    self.setupMPV(url: item.url, startTime: startTime)

                case .readyToPlay:
                    let asset = item.asset

                    Task {
                        do {
                            let videoTracks = try await asset.loadTracks(withMediaType: .video)

                            if !videoTracks.isEmpty {
                                var hasValidVideoFormat = false
                                for track in videoTracks {
                                    let formatDescriptions = try await track.load(.formatDescriptions) as [CMFormatDescription]
                                    if !formatDescriptions.isEmpty {
                                        hasValidVideoFormat = true
                                        break
                                    }
                                }

                                if !hasValidVideoFormat {
                                    logger.warning("AVPlayer ready but video format invalid. Attempting MPV playback.")
                                    guard let item = self.mediaItem else { return }
                                    self.teardown(resetAudioSelection: false)
                                    self.setupMPV(url: item.url, startTime: startTime)
                                    return
                                }

                                for track in videoTracks {
                                    let isDecodable = try await track.load(.isDecodable)
                                    if !isDecodable {
                                        logger.warning("AVPlayer ready but video track not decodable. Attempting MPV playback.")
                                        guard let item = self.mediaItem else { return }
                                        self.teardown(resetAudioSelection: false)
                                        self.setupMPV(url: item.url, startTime: startTime)
                                        return
                                    }
                                }
                            }

                            // Extract early aspect ratio from naturalSize
                            if let firstVideoTrack = videoTracks.first {
                                let naturalSize = try await firstVideoTrack.load(.naturalSize)
                                if naturalSize.width > 0, naturalSize.height > 0 {
                                    self.videoAspectRatio = naturalSize.width / naturalSize.height
                                }
                            }

                            self.isReady = true

                            if let player = self.player {
                                let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
                                await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            }

                            self.applySelectedAudioTrack()

                        } catch {
                            logger.debug("Could not verify video tracks, proceeding with playback")
                            self.isReady = true

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
