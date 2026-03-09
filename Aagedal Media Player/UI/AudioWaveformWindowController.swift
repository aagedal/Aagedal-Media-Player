// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Manages an NSPanel auxiliary window for audio waveform display, linked to a player window.

import AppKit
import SwiftUI
import OSLog

@MainActor
final class AudioWaveformWindowController {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "AudioWaveformWindow")

    private var panel: NSPanel?
    private let generator: AudioWaveformGenerator
    private let controller: PlayerController
    private let filename: String
    private weak var parentWindow: NSWindow?

    private var closeObserver: NSObjectProtocol?

    init(controller: PlayerController, filename: String, parentWindow: NSWindow?) {
        self.controller = controller
        self.generator = AudioWaveformGenerator()
        self.filename = filename
        self.parentWindow = parentWindow
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show() {
        if let existing = panel {
            existing.orderFront(nil)
            return
        }

        let duration = controller.mediaItem?.durationSeconds ?? 0
        let waveformView = AudioWaveformView(
            generator: generator,
            controller: controller,
            duration: duration
        )
        let hostingView = NSHostingView(rootView: waveformView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 200),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Audio Waveform \u{2014} \(filename)"
        panel.contentView = hostingView
        panel.contentMinSize = NSSize(width: 400, height: 120)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position below parent window
        if let parent = parentWindow {
            let parentFrame = parent.frame
            let x = parentFrame.origin.x + 20
            let y = parentFrame.origin.y - 220
            panel.setFrameOrigin(NSPoint(x: max(x, 0), y: max(y, 0)))
        } else {
            panel.center()
        }

        panel.becomesKeyOnlyIfNeeded = true
        panel.orderFront(nil)
        self.panel = panel

        // Trigger waveform generation now that the view is open
        // Use a brief delay to allow SwiftUI to set up the view
        Task { @MainActor in
            // Read AudioWaveformView's triggerGeneration through the generator
            guard let item = controller.mediaItem,
                  let metadata = item.metadata else { return }

            let trackIdx = controller.selectedAudioTrackOrderIndex
            guard trackIdx < controller.audioTrackOptions.count else { return }

            let option = controller.audioTrackOptions[trackIdx]
            let streamIndex = option.streamIndex
            let audioStreams = metadata.audioStreams
            guard streamIndex < audioStreams.count else { return }

            let stream = audioStreams[streamIndex]
            let channels = stream.channels ?? 2

            generator.generate(
                url: item.url,
                streamIndex: streamIndex,
                channels: channels,
                channelLayout: stream.channelLayout,
                duration: item.durationSeconds
            )
        }

        // Auto-close when parent window closes
        if let parent = parentWindow {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.close()
                }
            }
        }

        // Handle panel close button
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePanelClose()
            }
        }

        logger.info("Audio waveform window opened for \(self.filename)")
    }

    func close() {
        panel?.close()
        cleanup()
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    private func handlePanelClose() {
        cleanup()
    }

    private func cleanup() {
        generator.cancel()

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }

        panel = nil
        logger.info("Audio waveform window closed for \(self.filename)")
    }

    nonisolated deinit {
        // closeObserver cleanup handled by cleanup() before deallocation
    }
}
