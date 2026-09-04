// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Routes typed app commands to the appropriate player window.

import AppKit
import SwiftUI

// MARK: - Notification Handlers (split out to help Swift type-checker)

struct NotificationHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    let nsWindow: NSWindow?
    @Binding var isEditingTimecode: Bool
    @Binding var showInspector: Bool
    @Binding var scopeWindowController: ScopeWindowController?
    @Binding var showScopeOverlay: Bool
    @Binding var audioWaveformWindowController: AudioWaveformWindowController?
    @Binding var showAudioWaveformOverlay: Bool
    @ObservedObject var audioWaveformGenerator: AudioWaveformGenerator
    @Binding var timecodeMode: TimecodeDisplayMode
    @ObservedObject var overlayController: PlayerOverlayController
    let isMediaLoaded: Bool
    let openFilePanel: () -> Void
    let openFile: (URL) -> Void
    let openPreviousFile: () -> Void
    let openNextFile: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(FileAndWindowHandlers(
                controller: controller,
                compareSession: compareSession,
                nsWindow: nsWindow,
                showInspector: $showInspector,
                scopeWindowController: $scopeWindowController,
                showScopeOverlay: $showScopeOverlay,
                audioWaveformWindowController: $audioWaveformWindowController,
                showAudioWaveformOverlay: $showAudioWaveformOverlay,
                audioWaveformGenerator: audioWaveformGenerator,
                openFilePanel: openFilePanel, openFile: openFile,
                openPreviousFile: openPreviousFile, openNextFile: openNextFile
            ))
            .modifier(PlaybackHandlers(
                controller: controller,
                compareSession: compareSession,
                nsWindow: nsWindow
            ))
            .modifier(TimecodeAndSyncHandlers(
                controller: controller, nsWindow: nsWindow,
                compareSession: compareSession,
                isEditingTimecode: $isEditingTimecode,
                timecodeMode: $timecodeMode,
                overlayController: overlayController,
                isMediaLoaded: isMediaLoaded
            ))
    }
}

// MARK: - File & Window Handlers

private struct FileAndWindowHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    let nsWindow: NSWindow?
    @Binding var showInspector: Bool
    @Binding var scopeWindowController: ScopeWindowController?
    @Binding var showScopeOverlay: Bool
    @Binding var audioWaveformWindowController: AudioWaveformWindowController?
    @Binding var showAudioWaveformOverlay: Bool
    @ObservedObject var audioWaveformGenerator: AudioWaveformGenerator
    let openFilePanel: () -> Void
    let openFile: (URL) -> Void
    let openPreviousFile: () -> Void
    let openNextFile: () -> Void
    @AppStorage(AppSettings.scopeDisplayMode.key)
    private var scopeDisplayMode = AppSettings.scopeDisplayMode.defaultValue
    @AppStorage(AppSettings.audioWaveformDisplayMode.key)
    private var audioWaveformDisplayMode = AppSettings.audioWaveformDisplayMode.defaultValue

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .openFilePicker = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                openFilePanel()
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case let .openFile(url, targetWindow) = command else { return }
                if let targetWindow {
                    guard targetWindow === nsWindow else { return }
                } else {
                    guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                }
                openFile(url)
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .openPreviousFile = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                openPreviousFile()
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .openNextFile = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                openNextFile()
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .toggleInspector = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                showInspector.toggle()
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .captureScreenshot = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.captureComparisonStill(primary: controller)
                } else {
                    controller.captureScreenshot()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .exportTrim = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                controller.exportTrim()
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .toggleFullscreen = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                controller.toggleFullscreen()
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .toggleScopes = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                let isOverlayMode = scopeDisplayMode == ScopeDisplayMode.overlay.rawValue

                if isOverlayMode {
                    // Close any existing window
                    scopeWindowController?.close()
                    scopeWindowController = nil

                    // Toggle overlay
                    showScopeOverlay.toggle()
                    if showScopeOverlay {
                        startScopeCaptures()
                    } else {
                        // Only stop capture if the scope window isn't also open
                        if scopeWindowController == nil {
                            stopScopeCaptures()
                        }
                    }
                } else {
                    // Close overlay if open
                    if showScopeOverlay {
                        showScopeOverlay = false
                        // Only stop capture if transitioning to window mode
                    }

                    // Toggle window
                    if let existing = scopeWindowController {
                        existing.toggle()
                        if !existing.isVisible {
                            scopeWindowController = nil
                        }
                    } else {
                        let filename = controller.mediaItem?.name ?? "Untitled"
                        let sc = ScopeWindowController(
                            primaryController: controller,
                            compareSession: compareSession,
                            filename: filename,
                            parentWindow: nsWindow
                        )
                        scopeWindowController = sc
                        sc.show()
                    }
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .toggleAudioWaveform = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                let isOverlayMode = audioWaveformDisplayMode == AudioWaveformDisplayMode.overlay.rawValue

                if isOverlayMode {
                    // Close any existing window
                    audioWaveformWindowController?.close()
                    audioWaveformWindowController = nil

                    // Toggle overlay
                    showAudioWaveformOverlay.toggle()
                    if showAudioWaveformOverlay {
                        triggerOverlayWaveformGeneration()
                    } else if !keepsAutomaticAudioOnlyWaveform {
                        audioWaveformGenerator.cancel()
                    }
                } else {
                    // Close overlay if open
                    showAudioWaveformOverlay = false
                    if !keepsAutomaticAudioOnlyWaveform {
                        audioWaveformGenerator.cancel()
                    }

                    // Toggle window
                    if let existing = audioWaveformWindowController {
                        existing.toggle()
                        if !existing.isVisible {
                            audioWaveformWindowController = nil
                        }
                    } else {
                        let filename = controller.mediaItem?.name ?? "Untitled"
                        let wc = AudioWaveformWindowController(
                            controller: controller,
                            filename: filename,
                            parentWindow: nsWindow
                        )
                        audioWaveformWindowController = wc
                        wc.show()
                    }
                }
            }
    }

    private var keepsAutomaticAudioOnlyWaveform: Bool {
        controller.mediaItem?.presentationKind == .audioOnly
            && UserDefaults.standard.value(for: AppSettings.automaticAudioOnlyWaveform)
    }

    private func startScopeCaptures() {
        controller.frameCapture.startCapture()
        if compareSession.isActive {
            compareSession.secondaryController.frameCapture.startCapture()
        }
    }

    private func stopScopeCaptures() {
        controller.frameCapture.stopCapture()
        compareSession.secondaryController.frameCapture.stopCapture()
    }

    private func triggerOverlayWaveformGeneration() {
        guard let item = controller.mediaItem,
              let metadata = item.metadata else { return }

        if controller.showAllMonoWaveforms && controller.isMultiMonoFile {
            let streams: [(index: Int, label: String)] = metadata.audioStreams.enumerated().map { offset, stream in
                let label: String
                if let title = stream.title, !title.isEmpty {
                    label = title
                } else if let option = controller.audioTrackOptions.first(where: { $0.streamIndex == offset }) {
                    label = option.title
                } else {
                    label = "Track \(offset + 1)"
                }
                return (index: offset, label: label)
            }
            guard !streams.isEmpty else { return }
            audioWaveformGenerator.generateAllMonoStreams(url: item.url, streams: streams, duration: item.durationSeconds)
            return
        }

        let trackIdx = controller.selectedAudioTrackOrderIndex
        guard trackIdx < controller.audioTrackOptions.count else { return }

        let option = controller.audioTrackOptions[trackIdx]
        let streamIndex = option.streamIndex
        let audioStreams = metadata.audioStreams
        guard streamIndex < audioStreams.count else { return }

        let stream = audioStreams[streamIndex]
        let channels = stream.channels ?? 2

        audioWaveformGenerator.generate(
            url: item.url,
            streamIndex: streamIndex,
            channels: channels,
            channelLayout: stream.channelLayout,
            duration: item.durationSeconds
        )
    }
}

// MARK: - Playback Handlers

private struct PlaybackHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    let nsWindow: NSWindow?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .togglePlayback = command else { return }
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.togglePlayback(primary: controller)
                } else {
                    controller.togglePlayback()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .toggleMute = command else { return }
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.toggleMonitoringMute(primary: controller)
                } else {
                    controller.toggleMute()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case let .adjustVolume(delta) = command,
                      WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.adjustMonitoringVolume(by: delta, primary: controller)
                } else {
                    controller.adjustVolume(by: delta)
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .reverse = command else { return }
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.reverse(primary: controller)
                } else {
                    controller.startReverse()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .fastForward = command else { return }
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.fastForward(primary: controller)
                } else {
                    controller.fastForward()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .slowForward = command else { return }
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.slowForward(primary: controller)
                } else {
                    controller.slowForward()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .slowReverse = command else { return }
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.slowReverse(primary: controller)
                } else {
                    controller.slowReverse()
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case let .seekByFrames(count) = command,
                      WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.seekByFrames(primary: controller, frameCount: count)
                } else {
                    controller.seekByFrames(count)
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case let .seekBySeconds(seconds) = command,
                      WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.seek(primary: controller, by: seconds)
                } else {
                    controller.seek(by: seconds)
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case let .seekToEdge(edge) = command,
                      WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                switch edge {
                case .start:
                    if compareSession.isActive {
                        compareSession.seek(primary: controller, to: 0)
                    } else {
                        controller.seekTo(0)
                    }
                case .end:
                    let duration = controller.mediaItem?.durationSeconds ?? 0
                    if compareSession.isActive {
                        compareSession.seek(primary: controller, to: max(0, duration))
                    } else {
                        controller.seekTo(max(0, duration))
                    }
                }
            }
    }
}

// MARK: - Timecode, Sync & Clipboard Handlers

private struct TimecodeAndSyncHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    let nsWindow: NSWindow?
    @ObservedObject var compareSession: CompareSessionController
    @Binding var isEditingTimecode: Bool
    @Binding var timecodeMode: TimecodeDisplayMode
    @ObservedObject var overlayController: PlayerOverlayController
    let isMediaLoaded: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .cycleTimecodeMode = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow), !isEditingTimecode else { return }
                let hasSourceTC = controller.mediaItem.flatMap { TimecodeFormatter.effectiveStartTimecode(for: $0) } != nil
                timecodeMode.toggle(hasSourceTimecode: hasSourceTC)
            }
            // Sync timecode — active window reads its time and broadcasts
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .syncTimecode = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                let relTime = controller.currentPlaybackTime
                let startSeconds = controller.mediaItem.flatMap {
                    TimecodeFormatter.startTimecodeInSeconds(for: $0)
                }
                NotificationCenter.default.post(.seekToSyncedTime(.init(
                    relativeSeconds: relTime,
                    sourceSeconds: startSeconds.map { relTime + $0 }
                )))
            }
            // Sync timecode — non-active windows seek to the broadcast time
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case let .seekToSyncedTime(time) = command else { return }
                guard !WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                let seekPosition: TimeInterval
                if let srcTime = time.sourceSeconds,
                   let item = controller.mediaItem,
                   let receiverStartSeconds = TimecodeFormatter.startTimecodeInSeconds(for: item) {
                    seekPosition = max(0, srcTime - receiverStartSeconds)
                } else {
                    seekPosition = time.relativeSeconds
                }
                if compareSession.isActive {
                    compareSession.seek(primary: controller, to: seekPosition)
                } else {
                    controller.seekTo(seekPosition)
                }
            }
            // Copy timecode — copies the current timecode display to the clipboard
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .copyTimecode = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                guard let item = controller.mediaItem else { return }
                let tc = TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: controller.currentPlaybackTime,
                    item: item,
                    mode: timecodeMode,
                    includePrefix: false
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tc, forType: .string)
            }
            // Paste timecode — reads a timecode from clipboard and seeks to it
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .pasteTimecode = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                guard let item = controller.mediaItem,
                      let clipboardString = NSPasteboard.general.string(forType: .string),
                      let seekTime = TimecodeFormatter.parseAbsoluteTimecodeToSeconds(
                          clipboardString, item: item, mode: timecodeMode
                      ) else { return }
                let duration = max(item.durationSeconds, 0)
                let target = max(0, min(seekTime, duration))
                if compareSession.isActive {
                    compareSession.seek(primary: controller, to: target)
                } else {
                    controller.seekTo(target)
                }
            }
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .reloadPlayer = command else { return }
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                compareSession.reload(primary: controller)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                overlayController.appDidResign(
                    isMediaLoaded: isMediaLoaded,
                    isControlInteractionActive: isEditingTimecode
                )
            }
    }
}
