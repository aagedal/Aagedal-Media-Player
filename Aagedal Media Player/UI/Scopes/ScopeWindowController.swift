// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Manages an NSPanel auxiliary window for video scopes, linked to a player window.

import AppKit
import SwiftUI
import OSLog

@MainActor
final class ScopeWindowController {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "ScopeWindow")

    private var panel: NSPanel?
    private let frameCapture: FrameCapture
    private let filename: String
    private weak var parentWindow: NSWindow?

    /// Observation for parent window closing — auto-closes scope panel.
    private var closeObserver: NSObjectProtocol?

    init(frameCapture: FrameCapture, filename: String, parentWindow: NSWindow?) {
        self.frameCapture = frameCapture
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

        let scopeView = ScopeView(frameCapture: frameCapture)
        let hostingView = NSHostingView(rootView: scopeView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Scopes \u{2014} \(filename)"
        panel.contentView = hostingView
        panel.contentMinSize = NSSize(width: 500, height: 250)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position near parent window
        if let parent = parentWindow {
            let parentFrame = parent.frame
            let x = parentFrame.origin.x + 20
            let y = parentFrame.origin.y - 340
            panel.setFrameOrigin(NSPoint(x: max(x, 0), y: max(y, 0)))
        } else {
            panel.center()
        }

        panel.becomesKeyOnlyIfNeeded = true
        panel.orderFront(nil)
        self.panel = panel

        // Start frame capture
        frameCapture.startCapture()

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

        // Handle scope panel close button
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePanelClose()
            }
        }

        logger.info("Scope window opened for \(self.filename)")
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
        frameCapture.stopCapture()

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }

        panel = nil
        logger.info("Scope window closed for \(self.filename)")
    }

    nonisolated deinit {
        // closeObserver cleanup handled by cleanup() before deallocation
    }
}
