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
    private var windowsWithMedia: Set<UUID> = []

    /// URLs queued for new windows that haven't appeared yet.
    /// Each new window's `.task` pops one URL from this array.
    var pendingFileURLs: [URL] = []

    /// Counter of explicitly requested windows that are allowed to appear.
    /// Decremented as windows are accepted in onWindowAvailable.
    /// Prevents SwiftUI's URL routing from spawning unwanted windows.
    var windowsToAllow = 0

    /// Set after the first window spawns additional windows for a multi-file
    /// Finder open on launch. Prevents duplicate spawning from later windows.
    var pendingWindowsSpawned = false

    /// Stored by ContentView from its `@Environment(\.openWindow)` so that
    /// non-View code (menus, AppDelegate) can open new WindowGroup windows.
    var openNewWindow: (() -> Void)?

    /// Always read live from UserDefaults so the value is never stale
    /// after the user toggles the setting (AppStorage on non-View classes
    /// can cache the initial value).
    var allowMultipleWindows: Bool {
        UserDefaults.standard.bool(forKey: "allowMultipleWindows")
    }
    var syncPlaybackControls: Bool {
        UserDefaults.standard.bool(forKey: "syncPlaybackControls")
    }

    private init() {}

    /// True once at least one window has been registered and is still alive.
    var hasWindows: Bool {
        windows.values.contains { $0.window != nil }
    }

    func register(id: UUID, window: NSWindow) {
        windows[id] = WeakWindow(window: window)
    }

    func unregister(id: UUID) {
        windows.removeValue(forKey: id)
        windowsWithMedia.remove(id)
    }

    func markHasMedia(id: UUID) {
        windowsWithMedia.insert(id)
    }

    /// Returns the NSWindow of the first registered window that has no media loaded.
    func firstEmptyWindow() -> NSWindow? {
        for (id, weakWindow) in windows {
            if let window = weakWindow.window, !windowsWithMedia.contains(id) {
                return window
            }
        }
        return nil
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
