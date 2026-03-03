// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Right-edge zone that instantly hides the cursor and overlay when the mouse
// enters, giving a clean full-screen-like experience without going fullscreen.

import SwiftUI
import AppKit

struct CursorHideZone: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> CursorHideNSView {
        let view = CursorHideNSView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: CursorHideNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }
}

final class CursorHideNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    /// Centralized flag ensuring hide/unhide calls stay balanced (at most one outstanding hide).
    private static var isCursorHiddenByUs = false

    /// Force cursor visible if we hid it. Safe to call at any time.
    static func ensureCursorVisible() {
        if isCursorHiddenByUs {
            NSCursor.unhide()
            isCursorHiddenByUs = false
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        if !Self.isCursorHiddenByUs {
            NSCursor.hide()
            Self.isCursorHiddenByUs = true
        }
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        Self.ensureCursorVisible()
        onHoverChanged?(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willEnterFullScreenNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willExitFullScreenNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        if let window {
            updateTrackingAreas()
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillTransition),
                                                   name: NSWindow.willEnterFullScreenNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillTransition),
                                                   name: NSWindow.willExitFullScreenNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillTransition),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
    }

    @objc private func windowWillTransition(_ notification: Notification) {
        if isHovering {
            isHovering = false
            Self.ensureCursorVisible()
            onHoverChanged?(false)
        }
    }

    override func removeFromSuperview() {
        if isHovering {
            isHovering = false
            Self.ensureCursorVisible()
        }
        NotificationCenter.default.removeObserver(self)
        super.removeFromSuperview()
    }

    deinit {
        let wasHovering = isHovering
        if wasHovering {
            if Thread.isMainThread {
                Self.ensureCursorVisible()
            } else {
                DispatchQueue.main.async {
                    CursorHideNSView.ensureCursorVisible()
                }
            }
        }
        NotificationCenter.default.removeObserver(self)
    }
}
