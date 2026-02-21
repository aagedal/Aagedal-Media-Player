// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct IsMediaLoadedKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var isMediaLoaded: Bool? {
        get { self[IsMediaLoadedKey.self] }
        set { self[IsMediaLoadedKey.self] = newValue }
    }
}

@main
struct Aagedal_Media_PlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.isMediaLoaded) private var isMediaLoaded
    @AppStorage("allowMultipleWindows") private var allowMultipleWindows = false

    private var mediaLoaded: Bool { isMediaLoaded ?? false }

    var body: some Scene {
        WindowGroup(id: "player") {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                if allowMultipleWindows {
                    Button("New Window") {
                        WindowManager.shared.openNewWindow?()
                    }
                    .keyboardShortcut("n")
                }

                Button("Open\u{2026}") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o")

                Button("Close Window") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w")

                Divider()

                RecentDocumentsMenu()
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Screenshot") {
                    NotificationCenter.default.post(name: .captureScreenshot, object: nil)
                }
                .keyboardShortcut("s")
                .disabled(!mediaLoaded)

                Button("Export Trim\u{2026}") {
                    NotificationCenter.default.post(name: .exportTrim, object: nil)
                }
                .keyboardShortcut("e")
                .disabled(!mediaLoaded)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i")
                .disabled(!mediaLoaded)

                Button("Cycle Timecode Display") {
                    NotificationCenter.default.post(name: .cycleTimecodeMode, object: nil)
                }
                .keyboardShortcut("t", modifiers: [])
                .disabled(!mediaLoaded)
            }
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!mediaLoaded)

                Divider()

                Button("Reverse") {
                    NotificationCenter.default.post(name: .reverse, object: nil)
                }
                .keyboardShortcut("j", modifiers: [])
                .disabled(!mediaLoaded)

                Button("Fast Forward") {
                    NotificationCenter.default.post(name: .fastForward, object: nil)
                }
                .keyboardShortcut("l", modifiers: [])
                .disabled(!mediaLoaded)

                Divider()

                Button("Toggle Fullscreen") {
                    NotificationCenter.default.post(name: .toggleFullscreen, object: nil)
                }
                .keyboardShortcut("f")
                .disabled(!mediaLoaded)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Recent Documents Menu

/// Provides an "Open Recent" submenu using NSDocumentController's recent document URLs.
struct RecentDocumentsMenu: View {
    @State private var recentURLs: [URL] = []

    var body: some View {
        Menu("Open Recent") {
            ForEach(recentURLs, id: \.self) { url in
                Button(url.lastPathComponent) {
                    NotificationCenter.default.post(name: .openFileURL, object: url)
                }
            }

            if !recentURLs.isEmpty {
                Divider()
            }

            Button("Clear Menu") {
                NSDocumentController.shared.clearRecentDocuments(nil)
                recentURLs = []
            }
            .disabled(recentURLs.isEmpty)
        }
        .onAppear {
            recentURLs = NSDocumentController.shared.recentDocumentURLs
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recentURLs = NSDocumentController.shared.recentDocumentURLs
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { _ in
            // Refresh after a file is opened
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                recentURLs = NSDocumentController.shared.recentDocumentURLs
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }

        if WindowManager.shared.allowMultipleWindows {
            // Multi-window: open file in a new window
            WindowManager.shared.pendingFileURL = url
            WindowManager.shared.openNewWindow?()
        } else {
            // Single-window: replace content in the key window
            NotificationCenter.default.post(name: .openFileURL, object: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
    static let openFileURL = Notification.Name("openFileURL")
    static let toggleInspector = Notification.Name("toggleInspector")
    static let captureScreenshot = Notification.Name("captureScreenshot")
    static let exportTrim = Notification.Name("exportTrim")
    static let cycleTimecodeMode = Notification.Name("cycleTimecodeMode")
    static let togglePlayback = Notification.Name("togglePlayback")
    static let reverse = Notification.Name("reverse")
    static let fastForward = Notification.Name("fastForward")
    static let toggleFullscreen = Notification.Name("toggleFullscreen")
}
