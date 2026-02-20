// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The player area with video display, keyboard handling, and speed indicator overlay.

import SwiftUI
import AppKit
import AVKit

struct PlayerView: View {
    @ObservedObject var controller: PlayerController
    let item: MediaItem

    private var playerAspectRatio: CGFloat {
        if let ratio = item.videoDisplayAspectRatio, ratio.isFinite, ratio > 0 {
            return CGFloat(ratio)
        }
        return 16.0 / 9.0
    }

    var body: some View {
        Group {
            if let player = controller.player {
                // AVPlayer backend
                ZStack {
                    Color.black

                    PlayerContainerView(
                        player: player,
                        controller: controller,
                        keyHandler: handleKeyEvent
                    )
                    .aspectRatio(playerAspectRatio, contentMode: .fit)

                    overlayIndicators
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(controller.playbackTimePublisher) { time in
                    // Time synced via publisher
                }
            } else if controller.useMPV, let mpvPlayer = controller.mpvPlayer {
                // MPV backend
                ZStack {
                    Color.black

                    MPVVideoView(player: mpvPlayer, keyHandler: handleKeyEvent)
                        .aspectRatio(playerAspectRatio, contentMode: .fit)

                    overlayIndicators
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(controller.playbackTimePublisher) { time in
                    // Time synced via publisher
                }
            } else if controller.isPreparing {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(.circular)
                    Text("Preparing playback\u{2026}")
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if let message = controller.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 40))
                    Text("Playback unavailable")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        controller.preparePlayback(startTime: 0)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var overlayIndicators: some View {
        VStack {
            HStack {
                PlaybackSpeedIndicator(
                    speed: controller.currentPlaybackSpeed,
                    isReversing: controller.isReverseSimulating
                )
                Spacer()
            }
            Spacer()
        }
        .padding(16)
    }

    @MainActor
    private func handleKeyEvent(_ characters: String, _ modifiers: NSEvent.ModifierFlags, _ specialKey: NSEvent.SpecialKey?) -> Bool {
        // JKL playback controls
        switch characters.lowercased() {
        case "j":
            controller.startReverseSimulation()
            return true
        case "k":
            controller.togglePlayback()
            return true
        case "l":
            controller.fastForward()
            return true
        case " ":
            controller.togglePlayback()
            return true
        case "t":
            // Cycle timecode display mode is handled by ControlsView
            NotificationCenter.default.post(name: .cycleTimecodeMode, object: nil)
            return true
        case "f":
            controller.toggleFullscreen()
            return true
        default:
            break
        }

        // Arrow keys
        if let specialKey {
            switch specialKey {
            case .leftArrow:
                if modifiers.contains(.shift) {
                    controller.seek(by: -10)
                } else {
                    controller.seekByFrames(-1)
                }
                return true
            case .rightArrow:
                if modifiers.contains(.shift) {
                    controller.seek(by: 10)
                } else {
                    controller.seekByFrames(1)
                }
                return true
            default:
                break
            }
        }

        return false
    }
}

// MARK: - AVPlayer Container

private struct PlayerContainerView: NSViewRepresentable {
    typealias NSViewType = AVPlayerView

    let player: AVPlayer
    let controller: PlayerController
    let keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        configure(playerView)
        context.coordinator.attach(to: playerView, controller: controller)
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(keyHandler: keyHandler)
    }

    private func configure(_ playerView: AVPlayerView) {
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsTimecodes = false
        playerView.videoGravity = .resizeAspect
        playerView.allowsVideoFrameAnalysis = false
        playerView.player = player
    }

    final class Coordinator: NSObject {
        private var monitor: Any?
        private weak var attachedView: AVPlayerView?
        private let keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool

        init(keyHandler: @escaping (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool) {
            self.keyHandler = keyHandler
        }

        @MainActor
        func attach(to playerView: AVPlayerView, controller: PlayerController) {
            playerView.player = controller.player
            controller.playerView = playerView
            attachedView = playerView

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                guard let view = self.attachedView,
                      let window = view.window,
                      window.isKeyWindow else {
                    return event
                }

                guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return event }
                let handled = self.keyHandler(characters, event.modifierFlags, event.specialKey)
                return handled ? nil : event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let cycleTimecodeMode = Notification.Name("cycleTimecodeMode")
}
