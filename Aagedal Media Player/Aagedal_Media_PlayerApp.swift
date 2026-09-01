// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Sparkle
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
    @AppStorage(AppSettings.allowMultipleWindows.key)
    private var allowMultipleWindows = AppSettings.allowMultipleWindows.defaultValue

    /// Construct Sparkle eagerly so the updater attaches to the run loop
    /// before the first window appears. Inert for Homebrew installs and when
    /// SUFeedURL is unset — see `SparkleUpdater.isActive`.
    private let sparkleUpdater = SparkleUpdater.shared

    private var mediaLoaded: Bool { isMediaLoaded ?? false }

    var body: some Scene {
        WindowGroup(id: "player") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 711, height: 400)
        .commands {
            if sparkleUpdater.isActive {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates\u{2026}") {
                        sparkleUpdater.controller.checkForUpdates(nil)
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                if allowMultipleWindows {
                    Button("New Window") {
                        WindowManager.shared.windowsToAllow += 1
                        WindowManager.shared.openNewWindow?()
                    }
                    .keyboardShortcut("n")
                }

                Button("Open\u{2026}") {
                    NotificationCenter.default.post(.openFilePicker)
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
                    NotificationCenter.default.post(.captureScreenshot)
                }
                .keyboardShortcut("s")
                .disabled(!mediaLoaded)

                Button("Export Trim\u{2026}") {
                    NotificationCenter.default.post(.exportTrim)
                }
                .keyboardShortcut("e")
                .disabled(!mediaLoaded)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Inspector") {
                    NotificationCenter.default.post(.toggleInspector)
                }
                .keyboardShortcut("i")
                .disabled(!mediaLoaded)

                Button("Cycle Timecode Display") {
                    NotificationCenter.default.post(.cycleTimecodeMode)
                }
                .keyboardShortcut("t", modifiers: [])
                .disabled(!mediaLoaded)

                Divider()

                Button("Video Scopes") {
                    NotificationCenter.default.post(.toggleScopes)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)

                Button("Toggle Parade") {
                    NotificationCenter.default.post(.toggleScopeParade)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)

                Button("Audio Waveform") {
                    NotificationCenter.default.post(.toggleAudioWaveform)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)
            }
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(.togglePlayback)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!mediaLoaded)

                Button("Mute / Unmute") {
                    NotificationCenter.default.post(.toggleMute)
                }
                .keyboardShortcut("m", modifiers: [])
                .disabled(!mediaLoaded)

                Button("Increase Volume") {
                    NotificationCenter.default.post(.adjustVolume(by: 5))
                }
                .keyboardShortcut(.upArrow, modifiers: [.control])
                .disabled(!mediaLoaded)

                Button("Decrease Volume") {
                    NotificationCenter.default.post(.adjustVolume(by: -5))
                }
                .keyboardShortcut(.downArrow, modifiers: [.control])
                .disabled(!mediaLoaded)

                Divider()

                Button("Reverse") {
                    NotificationCenter.default.post(.reverse)
                }
                .keyboardShortcut("j", modifiers: [])
                .disabled(!mediaLoaded)

                Button("Fast Forward") {
                    NotificationCenter.default.post(.fastForward)
                }
                .keyboardShortcut("l", modifiers: [])
                .disabled(!mediaLoaded)

                Divider()

                Button("Slow Forward") {
                    NotificationCenter.default.post(.slowForward)
                }
                .keyboardShortcut("l", modifiers: [.option])
                .disabled(!mediaLoaded)

                Button("Slow Reverse") {
                    NotificationCenter.default.post(.slowReverse)
                }
                .keyboardShortcut("j", modifiers: [.option])
                .disabled(!mediaLoaded)

                Divider()

                Button("Toggle Fullscreen") {
                    NotificationCenter.default.post(.toggleFullscreen)
                }
                .keyboardShortcut("f")
                .disabled(!mediaLoaded)

                Divider()

                Button("Sync Timecode") {
                    NotificationCenter.default.post(.syncTimecode)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Copy Timecode") {
                    NotificationCenter.default.post(.copyTimecode)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)

                Button("Paste Timecode") {
                    NotificationCenter.default.post(.pasteTimecode)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!mediaLoaded)

                Divider()

                Button("Reload Player") {
                    NotificationCenter.default.post(.reloadPlayer)
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
                    NotificationCenter.default.post(.openFile(url))
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
        .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
            guard case .openFile = notification.appCommand else { return }
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
        AppSettings.registerDefaults()
        UpdateChecker.shared.checkIfNeeded()
        SparkleUpdater.shared.presentFirstLaunchNoticeIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        WindowManager.shared.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
