// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tracks registered windows and routes commands based on single/multi-window mode.

import SwiftUI
import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    struct WeakWindow {
        weak var window: NSWindow?
    }

    private(set) var windows: [UUID: WeakWindow] = [:]
    var pendingFileURL: URL?

    /// Stored by ContentView from its `@Environment(\.openWindow)` so that
    /// non-View code (menus, AppDelegate) can open new WindowGroup windows.
    var openNewWindow: (() -> Void)?

    @AppStorage("allowMultipleWindows") var allowMultipleWindows = false
    @AppStorage("syncPlaybackControls") var syncPlaybackControls = false

    private init() {}

    func register(id: UUID, window: NSWindow) {
        windows[id] = WeakWindow(window: window)
    }

    func unregister(id: UUID) {
        windows.removeValue(forKey: id)
    }

    /// Returns true if this window should respond to key-window-only commands
    /// (file open, inspector, screenshot, export, fullscreen, timecode).
    func isActiveWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        let liveWindows = windows.values.compactMap(\.window)
        if liveWindows.count <= 1 { return true }
        return window.isKeyWindow
    }

    /// Returns true if this window should handle syncable playback commands
    /// (play/pause, reverse, fast forward).
    func shouldHandlePlaybackCommand(window: NSWindow?) -> Bool {
        if syncPlaybackControls { return true }
        return isActiveWindow(window)
    }
}
