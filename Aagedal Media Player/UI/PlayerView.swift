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
    @ObservedObject var audioWaveformGenerator: AudioWaveformGenerator
    let item: MediaItem
    let showsAudioWaveform: Bool
    @Binding var isEditingTimecode: Bool
    @Binding var isTimelineFocused: Bool
    let isOverlayControlFocused: Bool
    @Binding var timecodeActivationTrigger: String?
    @AppStorage(AppSettings.automaticAudioOnlyWaveform.key)
    private var automaticAudioOnlyWaveform = AppSettings.automaticAudioOnlyWaveform.defaultValue

    /// Aspect ratio for the player view's `.aspectRatio(_:contentMode:)` modifier.
    ///
    /// Source priority:
    /// 1. `controller.videoAspectRatio` — backend-reported (MPV's video-params
    ///    or AVAsset preferredTransform), authoritative once playback starts.
    /// 2. `item.videoDisplayAspectRatio` — metadata-derived, survives teardown.
    /// 3. 16:9 default — only when nothing else is known (very first frame
    ///    before metadata or backend reports anything).
    ///
    /// The metadata fallback matters during reload/swap: `teardown()` resets
    /// `controller.videoAspectRatio` to nil and `.id(preparationID)` rebuilds
    /// the MPVVideoView in that nil window, which would otherwise bake in the
    /// 16/9 default. SwiftUI's AspectRatioLayout caches that decision against
    /// the wrapped NSView, so the real value arriving on the next render
    /// doesn't always reflow the Metal layer — leaving a 16:9 frame
    /// pillarboxing a portrait video inside a portrait window.
    private var playerAspectRatio: CGFloat {
        if let backendRatio = controller.videoAspectRatio,
           backendRatio.isFinite, backendRatio > 0 {
            return backendRatio
        }
        if let metadataRatio = item.videoDisplayAspectRatio,
           metadataRatio.isFinite, metadataRatio > 0 {
            return CGFloat(metadataRatio)
        }
        return 16.0 / 9.0
    }

    var body: some View {
        ZStack {
            Color.black

            if let player = controller.player {
                // AVPlayer backend — .id() forces view recreation when the
                // player changes, ensuring the old AVPlayerView is fully
                // destroyed and cannot leak audio from a previous file.
                PlayerContainerView(
                    player: player,
                    controller: controller,
                    isEditingTimecode: $isEditingTimecode,
                    keyHandler: handleKeyEvent
                )
                .aspectRatio(playerAspectRatio, contentMode: .fit)
                .id(controller.preparationID)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(controller.playbackTimePublisher) { time in
                    // Time synced via publisher
                }
            } else if controller.useMPV, let mpvPlayer = controller.mpvPlayer {
                // MPV backend — .id() forces view recreation on each new load
                MPVVideoView(player: mpvPlayer, keyHandler: handleKeyEvent)
                    .aspectRatio(playerAspectRatio, contentMode: .fit)
                    .id(controller.preparationID)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onReceive(controller.playbackTimePublisher) { time in
                        // Time synced via publisher
                    }
            }

            if item.presentationKind == .audioOnly {
                AudioOnlyPresentationView(
                    generator: audioWaveformGenerator,
                    controller: controller,
                    item: item,
                    showsWaveform: automaticAudioOnlyWaveform || showsAudioWaveform
                )
            }

            if controller.player != nil || controller.mpvPlayer != nil {
                overlayIndicators
            }

            playbackStateOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private var playbackStateOverlay: some View {
        switch controller.playbackPhase {
        case .idle, .ready:
            EmptyView()

        case .preparing:
            stateProgressOverlay(label: "Preparing playback…")

        case .buffering:
            stateProgressOverlay(label: "Buffering…")

        case .failed(let failure):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 40))
                Text("Playback unavailable")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(failure.message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack {
                    Button("Retry") {
                        controller.preparePlayback(startTime: controller.currentPlaybackTime)
                    }
                    .buttonStyle(.borderedProminent)

                    if failure.mediaURL?.isFileURL == true {
                        Button("Reveal File") {
                            revealFailedFile(failure)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Copy Diagnostics") {
                        copyDiagnostics(failure)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.92))
        }
    }

    private func stateProgressOverlay(label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().progressViewStyle(.circular)
            Text(label)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(18)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
    }

    private func revealFailedFile(_ failure: PlaybackFailure) {
        guard let url = failure.mediaURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyDiagnostics(_ failure: PlaybackFailure) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failure.diagnosticText, forType: .string)
    }

    @ViewBuilder
    private var overlayIndicators: some View {
        VStack {
            HStack {
                PlaybackSpeedIndicator(
                    speed: controller.currentPlaybackSpeed,
                    isReversing: controller.isReversing
                )
                Spacer()
            }
            Spacer()
        }
        .padding(16)
    }

    private static let timecodeCharacters = Set("0123456789+-.:;")

    @MainActor
    private func handleKeyEvent(_ characters: String, _ modifiers: NSEvent.ModifierFlags, _ specialKey: NSEvent.SpecialKey?) -> Bool {
        // Don't intercept keys when editing timecode
        if isEditingTimecode {
            return false
        }

        // A local AppKit monitor sees key events before SwiftUI does. Let
        // arrow keys continue to the focused timeline so its keyboard and
        // Full Keyboard Access behavior is not shadowed by player shortcuts.
        if isTimelineFocused,
           specialKey == .leftArrow || specialKey == .rightArrow {
            return false
        }

        let lower = characters.lowercased()

        // I/O trim points (must be checked before timecode activation)
        if lower == "i" {
            if modifiers.contains(.option) {
                controller.clearTrimIn()
            } else if modifiers.contains(.shift) {
                if let inPoint = controller.trimIn { controller.seekTo(inPoint) }
            } else if !modifiers.contains(.command) && !modifiers.contains(.control) {
                controller.setTrimIn()
            } else {
                return false
            }
            return true
        }

        if lower == "o" {
            if modifiers.contains(.option) {
                controller.clearTrimOut()
            } else if modifiers.contains(.shift) {
                if let outPoint = controller.trimOut { controller.seekTo(outPoint) }
            } else if !modifiers.contains(.command) && !modifiers.contains(.control) {
                controller.setTrimOut()
            } else {
                return false
            }
            return true
        }

        // Option+X — Clear all trim points
        if lower == "x" && modifiers.contains(.option) {
            controller.clearTrimPoints()
            return true
        }

        // Let Full Keyboard Access deliver Space to a focused overlay control.
        // Otherwise Space remains the global play/pause shortcut.
        if characters == " " {
            if isOverlayControlFocused {
                return false
            }
            NotificationCenter.default.post(.togglePlayback)
            return true
        }

        // JKL playback controls — handled here (before performKeyEquivalent)
        // so AVPlayerView's built-in JKL shuttle doesn't intercept them.
        // Routed through notifications for multi-window sync.
        if lower == "j" {
            if modifiers.contains(.option) {
                NotificationCenter.default.post(.slowReverse)
            } else {
                NotificationCenter.default.post(.reverse)
            }
            return true
        }
        if lower == "k" {
            NotificationCenter.default.post(.togglePlayback)
            return true
        }
        if lower == "l" {
            if modifiers.contains(.option) {
                NotificationCenter.default.post(.slowForward)
            } else {
                NotificationCenter.default.post(.fastForward)
            }
            return true
        }

        // Arrow keys — routed through notifications for multi-window sync,
        // Option+Arrow bypasses sync and only affects the current window.
        if let specialKey {
            let optionHeld = modifiers.contains(.option)
            if modifiers.contains(.control) {
                switch specialKey {
                case .upArrow:
                    controller.adjustVolume(by: 5)
                    return true
                case .downArrow:
                    controller.adjustVolume(by: -5)
                    return true
                default:
                    break
                }
            }
            switch specialKey {
            case .leftArrow:
                if modifiers.contains(.shift) {
                    if optionHeld { controller.seek(by: -10) }
                    else { NotificationCenter.default.post(.seekBySeconds(-10)) }
                } else {
                    if optionHeld { controller.seekByFrames(-1) }
                    else { NotificationCenter.default.post(.seekByFrames(-1)) }
                }
                return true
            case .rightArrow:
                if modifiers.contains(.shift) {
                    if optionHeld { controller.seek(by: 10) }
                    else { NotificationCenter.default.post(.seekBySeconds(10)) }
                } else {
                    if optionHeld { controller.seekByFrames(1) }
                    else { NotificationCenter.default.post(.seekByFrames(1)) }
                }
                return true
            case .upArrow:
                if modifiers.contains(.command) {
                    if optionHeld { controller.seekTo(0) }
                    else { NotificationCenter.default.post(.seekToEdge(.start)) }
                } else {
                    if optionHeld { controller.seekByFrames(-10) }
                    else { NotificationCenter.default.post(.seekByFrames(-10)) }
                }
                return true
            case .downArrow:
                if modifiers.contains(.command) {
                    if optionHeld { controller.seekTo(max(0, controller.mediaItem?.durationSeconds ?? 0)) }
                    else { NotificationCenter.default.post(.seekToEdge(.end)) }
                } else {
                    if optionHeld { controller.seekByFrames(10) }
                    else { NotificationCenter.default.post(.seekByFrames(10)) }
                }
                return true
            default:
                break
            }
        }

        // Activate timecode input on numeric/timecode characters (no modifiers)
        let significantModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if modifiers.intersection(significantModifiers).isEmpty,
           let char = characters.first,
           Self.timecodeCharacters.contains(char) {
            timecodeActivationTrigger = String(char)
            return true
        }

        return false
    }
}

// MARK: - AVPlayer Container

private struct PlayerContainerView: NSViewRepresentable {
    typealias NSViewType = AVPlayerView

    let player: AVPlayer
    let controller: PlayerController
    @Binding var isEditingTimecode: Bool
    let keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        configure(playerView)
        context.coordinator.attach(to: playerView, controller: controller)
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        context.coordinator.keyHandler = keyHandler
        context.coordinator.isEditingTimecode = isEditingTimecode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(keyHandler: keyHandler, isEditingTimecode: isEditingTimecode)
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
        private nonisolated(unsafe) var monitor: Any?
        private weak var attachedView: AVPlayerView?
        var keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool
        var isEditingTimecode: Bool

        init(keyHandler: @escaping (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool, isEditingTimecode: Bool) {
            self.keyHandler = keyHandler
            self.isEditingTimecode = isEditingTimecode
        }

        @MainActor
        func attach(to playerView: AVPlayerView, controller: PlayerController) {
            playerView.player = controller.player
            controller.playerView = playerView
            attachedView = playerView

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // When editing timecode, let events pass through to the TextField
                if self.isEditingTimecode {
                    return event
                }

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
