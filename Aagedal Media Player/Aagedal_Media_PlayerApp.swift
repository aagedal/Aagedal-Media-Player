// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct Aagedal_Media_PlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings\u{2026}")
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open\u{2026}") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o")

                RecentDocumentsMenu()
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Screenshot") {
                    NotificationCenter.default.post(name: .captureScreenshot, object: nil)
                }
                .keyboardShortcut("s")

                Button("Export Trim\u{2026}") {
                    NotificationCenter.default.post(name: .exportTrim, object: nil)
                }
                .keyboardShortcut("e")
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i")

                Button("Cycle Timecode Display") {
                    NotificationCenter.default.post(name: .cycleTimecodeMode, object: nil)
                }
                .keyboardShortcut("t", modifiers: [])
            }
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

                Button("Reverse") {
                    NotificationCenter.default.post(name: .reverse, object: nil)
                }
                .keyboardShortcut("j", modifiers: [])

                Button("Fast Forward") {
                    NotificationCenter.default.post(name: .fastForward, object: nil)
                }
                .keyboardShortcut("l", modifiers: [])

                Divider()

                Button("Toggle Fullscreen") {
                    NotificationCenter.default.post(name: .toggleFullscreen, object: nil)
                }
                .keyboardShortcut("f")
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
        NotificationCenter.default.post(name: .openFileURL, object: url)
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
