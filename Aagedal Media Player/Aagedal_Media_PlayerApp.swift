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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 711, height: 400)
        .commands {
            CommandGroup(replacing: .newItem) {
                if allowMultipleWindows {
                    Button("New Window") {
                        WindowManager.shared.windowsToAllow += 1
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

                Divider()

                Button("Sync Timecode") {
                    NotificationCenter.default.post(name: .syncTimecode, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Copy Timecode") {
                    NotificationCenter.default.post(name: .copyTimecode, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)

                Button("Paste Timecode") {
                    NotificationCenter.default.post(name: .pasteTimecode, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)

                Divider()

                Button("Reload Player") {
                    NotificationCenter.default.post(name: .reloadPlayer, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "openAtSourceResolution": true,
            "clampWindowToScreen": true,
            SettingsView.trimFormatKey: TrimExportFormat.copy.rawValue,
            SettingsView.screenshotJXLQualityKey: 90.0,
            SettingsView.screenshotJPEGQualityKey: 90.0,
            SettingsView.gifFrameRateKey: 15.0,
            SettingsView.gifWidthKey: ExportWidthPreset.w720.rawValue,
            SettingsView.avifWidthKey: ExportWidthPreset.w1080.rawValue,
            SettingsView.h264WidthKey: ExportWidthPreset.original.rawValue,
            SettingsView.h265WidthKey: ExportWidthPreset.original.rawValue,
            SettingsView.avifQualityKey: 28.0,
            SettingsView.avifSpeedKey: 4.0,
            SettingsView.h264QualityKey: 65.0,
            SettingsView.h265QualityKey: 65.0,
        ])
        UpdateChecker.shared.checkIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        let wm = WindowManager.shared
        wm.fileOpenInProgress = true

        if wm.allowMultipleWindows {
            if let openNew = wm.openNewWindow {
                // App is running — route each file individually.
                // Mark spawned so .onAppear on new windows won't double-spawn.
                wm.pendingWindowsSpawned = true
                for url in urls {
                    if let emptyWindow = wm.firstEmptyWindow() {
                        emptyWindow.makeKeyAndOrderFront(nil)
                        NotificationCenter.default.post(
                            name: .openFileURL, object: url,
                            userInfo: ["targetWindow": emptyWindow])
                    } else {
                        wm.windowsToAllow += 1
                        wm.pendingFileURLs.append(url)
                        openNew()
                    }
                }
            } else {
                // App is still launching — store all URLs; the first window
                // will load one and spawn windows for the rest.
                wm.pendingFileURLs = urls
            }
        } else if let window = wm.windows.values.compactMap(\.window).first {
            // Single-window: replace content with the first file
            guard let url = urls.first else { return }
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(
                name: .openFileURL, object: url,
                userInfo: ["targetWindow": window])
        } else {
            // App is still launching — store first URL for initial window
            if let url = urls.first {
                wm.pendingFileURLs = [url]
            }
        }

        // Bring the app to the foreground when opened via file association
        NSApp.activate()
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
    static let seekByFrames = Notification.Name("seekByFrames")
    static let seekBySeconds = Notification.Name("seekBySeconds")
    static let seekToEdge = Notification.Name("seekToEdge")
    static let toggleFullscreen = Notification.Name("toggleFullscreen")
    static let syncTimecode = Notification.Name("syncTimecode")
    static let seekToSyncedTime = Notification.Name("seekToSyncedTime")
    static let copyTimecode = Notification.Name("copyTimecode")
    static let pasteTimecode = Notification.Name("pasteTimecode")
    static let reloadPlayer = Notification.Name("reloadPlayer")
}
