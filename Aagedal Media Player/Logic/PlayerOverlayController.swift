// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Owns player-control overlay visibility and its AppKit event observers.

import AppKit
import Combine

@MainActor
final class PlayerOverlayController: ObservableObject {
    @Published private(set) var isVisible = true
    @Published private(set) var isWindowHovered = false
    @Published private(set) var isControlsHovered = false
    @Published private(set) var isRightEdgeHovered = false

    private var hideTask: Task<Void, Never>?
    private var mouseMoveMonitor: Any?
    private var keyDownMonitor: Any?
    private var appActiveObserver: NSObjectProtocol?
    private let hideDelay: Duration

    /// Hardware key code used by AppKit for Tab, including Shift-Tab.
    private static let tabKeyCode: UInt16 = 48

    init(hideDelay: Duration = .seconds(3)) {
        self.hideDelay = hideDelay
    }

    func install(
        isMediaLoaded: @escaping @MainActor () -> Bool,
        isPlaying: @escaping @MainActor () -> Bool,
        isEditingTimecode: @escaping @MainActor () -> Bool
    ) {
        removeObservers()

        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self,
                  isMediaLoaded(),
                  self.isWindowHovered,
                  !self.isRightEdgeHovered,
                  let window = NSApp.keyWindow,
                  window.isKeyWindow else {
                return event
            }

            CursorHideNSView.ensureCursorVisible()
            self.reveal()
            self.scheduleHide(
                isPlaying: isPlaying,
                isEditingTimecode: isEditingTimecode
            )
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  isMediaLoaded(),
                  event.keyCode == Self.tabKeyCode,
                  let window = NSApp.keyWindow,
                  window.isKeyWindow else {
                return event
            }

            self.revealForKeyboardNavigation()
            return event
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isRightEdgeHovered = false
                CursorHideNSView.ensureCursorVisible()
                self.cancelScheduledHide()
            }
        }
    }

    func setWindowHovered(_ hovered: Bool, isEditingTimecode: Bool) {
        isWindowHovered = hovered
        if !hovered && !isEditingTimecode {
            hide()
        }
    }

    func setControlsHovered(_ hovered: Bool) {
        isControlsHovered = hovered
        if hovered {
            cancelScheduledHide()
        }
    }

    func setRightEdgeHovered(
        _ hovered: Bool,
        isPlaying: @escaping @MainActor () -> Bool,
        isEditingTimecode: @escaping @MainActor () -> Bool
    ) {
        isRightEdgeHovered = hovered
        if hovered {
            hide()
        } else {
            reveal()
            scheduleHide(
                isPlaying: isPlaying,
                isEditingTimecode: isEditingTimecode
            )
        }
    }

    func reveal() {
        isVisible = true
    }

    /// Keeps auto-hidden controls visible while Full Keyboard Access moves
    /// focus through them. The key event itself is returned to AppKit so normal
    /// Tab and Shift-Tab traversal still occurs.
    func revealForKeyboardNavigation() {
        reveal()
        cancelScheduledHide()
    }

    func hide() {
        isVisible = false
        cancelScheduledHide()
    }

    func scheduleHide(
        isPlaying: @escaping @MainActor () -> Bool,
        isEditingTimecode: @escaping @MainActor () -> Bool
    ) {
        cancelScheduledHide()
        guard !isControlsHovered, !isEditingTimecode(), isPlaying() else { return }

        let hideDelay = hideDelay
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: hideDelay)
            guard !Task.isCancelled, let self else { return }
            if !self.isControlsHovered, !isEditingTimecode(), isPlaying() {
                self.isVisible = false
            }
        }
    }

    func appDidResign(isMediaLoaded: Bool, isEditingTimecode: Bool) {
        guard isMediaLoaded, !isEditingTimecode else { return }
        hide()
    }

    func cancelScheduledHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    func tearDown() {
        cancelScheduledHide()
        removeObservers()
    }

    private func removeObservers() {
        if let mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
            self.mouseMoveMonitor = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
    }
}
