// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import OSLog
import SwiftUI

private struct LiveAudioMeterContainerView: View {
    @ObservedObject var session: LiveAudioMeterSession
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    @ObservedObject var windowCoordinator: PlayerWindowCoordinator
    let close: @MainActor @Sendable () -> Void

    var body: some View {
        LiveAudioMeterView(
            state: session.viewState,
            preferences: session.preferences,
            actions: .init(
                selectSource: session.selectSource,
                selectPreset: session.selectPreset,
                setCustomLoudnessTarget: session.setCustomLoudnessTarget,
                setCustomTruePeakCeiling: session.setCustomTruePeakCeiling,
                clearMaxima: session.clearMaxima,
                resetMeters: session.reset,
                retry: session.retry,
                close: close
            )
        )
        .focusedSceneValue(\.isMediaLoaded, primaryController.mediaItem != nil)
        .focusedSceneValue(\.isCompareModeActive, compareSession.isActive)
        .focusedSceneValue(\.canOpenPreviousFile, windowCoordinator.canOpenPreviousFile)
        .focusedSceneValue(\.canOpenNextFile, windowCoordinator.canOpenNextFile)
    }
}

/// Activating auxiliary panel for one player window's source-PCM meters.
/// Unlike the nonactivating scope panel, this panel must become key so its
/// pickers, custom-reference fields, and keyboard actions are reachable.
@MainActor
final class LiveAudioMeterWindowController {
    private let logger = Logger(
        subsystem: "com.aagedal.MediaPlayer", category: "LiveAudioMeterWindow"
    )
    private let session: LiveAudioMeterSession
    private let primaryController: PlayerController
    private let compareSession: CompareSessionController
    private let windowCoordinator: PlayerWindowCoordinator
    private weak var parentWindow: NSWindow?
    private var panel: NSPanel?
    private var parentCloseObserver: NSObjectProtocol?
    private var panelCloseObserver: NSObjectProtocol?
    private var didCleanUp = false
    private var onClose: (() -> Void)?

    convenience init(
        primaryController: PlayerController,
        compareSession: CompareSessionController,
        windowCoordinator: PlayerWindowCoordinator,
        parentWindow: NSWindow?,
        onClose: @escaping () -> Void
    ) {
        self.init(
            primaryController: primaryController,
            compareSession: compareSession,
            windowCoordinator: windowCoordinator,
            parentWindow: parentWindow,
            session: LiveAudioMeterSession(
                primary: primaryController, comparison: compareSession
            ),
            onClose: onClose
        )
    }

    /// Dependency seam for lifecycle tests. The production initializer above
    /// still creates exactly one window-owned session.
    init(
        primaryController: PlayerController,
        compareSession: CompareSessionController,
        windowCoordinator: PlayerWindowCoordinator,
        parentWindow: NSWindow?,
        session: LiveAudioMeterSession,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.primaryController = primaryController
        self.compareSession = compareSession
        self.windowCoordinator = windowCoordinator
        self.parentWindow = parentWindow
        self.onClose = onClose
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let meterView = LiveAudioMeterContainerView(
            session: session,
            primaryController: primaryController,
            compareSession: compareSession,
            windowCoordinator: windowCoordinator,
            close: { [weak self] in self?.close() }
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Live Audio Meter"
        panel.contentView = NSHostingView(rootView: meterView)
        panel.contentMinSize = NSSize(width: 620, height: 460)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let parentWindow {
            parentWindow.addChildWindow(panel, ordered: .above)
            let origin = NSPoint(
                x: max(parentWindow.frame.minX + 20, 0),
                y: max(parentWindow.frame.minY - panel.frame.height - 20, 0)
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        self.panel = panel
        observeClose(of: panel)
        session.start()
        panel.makeKeyAndOrderFront(nil)
        logger.info("Live audio meter opened")
    }

    func close() {
        panel?.close()
        cleanup()
    }

    private func observeClose(of panel: NSPanel) {
        if let parentWindow {
            parentCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        panelCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cleanup() }
        }
    }

    private func cleanup() {
        guard !didCleanUp else { return }
        didCleanUp = true
        session.close()
        if let panel, panel.parent === parentWindow {
            parentWindow?.removeChildWindow(panel)
        }
        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
            self.parentCloseObserver = nil
        }
        if let panelCloseObserver {
            NotificationCenter.default.removeObserver(panelCloseObserver)
            self.panelCloseObserver = nil
        }
        panel = nil
        let callback = onClose
        onClose = nil
        callback?()
        logger.info("Live audio meter closed")
    }
}
