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
    private var filename: String
    private weak var parentWindow: NSWindow?
    private let deferredGenerationTask = DeferredMainActorTask()

    private var closeObserver: NSObjectProtocol?

    /// Observation for the waveform panel's own willClose — runs cleanup() when the user dismisses it.
    private var panelObserver: NSObjectProtocol?

    init(controller: PlayerController, filename: String, parentWindow: NSWindow?) {
        self.controller = controller
        self.generator = AudioWaveformGenerator()
        self.filename = filename
        self.parentWindow = parentWindow
    }

    private func updateTitle(_ name: String) {
        filename = name
        panel?.title = "Audio Waveform \u{2014} \(name)"
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show() {
        if let existing = panel {
            existing.orderFront(nil)
            return
        }

        let waveformView = AudioWaveformView(
            generator: generator,
            controller: controller,
            onMediaChange: { [weak self] name in
                self?.updateTitle(name)
            }
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

        // Defer generation until SwiftUI has installed the hosted view. The
        // task is panel-owned so an immediate close cannot start new ffmpeg
        // work after cleanup has already run.
        deferredGenerationTask.schedule { [weak self] in
            self?.generateInitialWaveform()
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
        panelObserver = NotificationCenter.default.addObserver(
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
        deferredGenerationTask.cancel()
        generator.cancel()

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        if let observer = panelObserver {
            NotificationCenter.default.removeObserver(observer)
            panelObserver = nil
        }

        panel = nil
        logger.info("Audio waveform window closed for \(self.filename)")
    }

    private func generateInitialWaveform() {
        guard panel != nil,
              let item = controller.mediaItem,
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
            if !streams.isEmpty {
                generator.generateAllMonoStreams(
                    url: item.url,
                    streams: streams,
                    duration: item.durationSeconds
                )
            }
            return
        }

        let trackIdx = controller.selectedAudioTrackOrderIndex
        guard trackIdx < controller.audioTrackOptions.count else { return }

        let option = controller.audioTrackOptions[trackIdx]
        let streamIndex = option.streamIndex
        let audioStreams = metadata.audioStreams
        guard streamIndex < audioStreams.count else { return }

        let stream = audioStreams[streamIndex]
        generator.generate(
            url: item.url,
            streamIndex: streamIndex,
            channels: stream.channels ?? 2,
            channelLayout: stream.channelLayout,
            duration: item.durationSeconds
        )
    }

    nonisolated deinit {
        // closeObserver cleanup handled by cleanup() before deallocation
    }
}
