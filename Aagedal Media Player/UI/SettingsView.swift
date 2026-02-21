// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum ScreenshotLocationMode: String, CaseIterable {
    case original = "original"
    case custom = "custom"
    case ask = "ask"

    var label: String {
        switch self {
        case .original: "Next to Original"
        case .custom: "Custom Folder"
        case .ask: "Ask Every Time"
        }
    }
}

enum ScreenshotFormat: String, CaseIterable {
    case jxl = "jxl"
    case png = "png"
    case jpeg = "jpeg"

    var label: String {
        switch self {
        case .jxl: "JPEG XL"
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .jxl: "jxl"
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

struct SettingsView: View {
    static let modeKey = "screenshotLocationMode"
    static let formatKey = "screenshotFormat"
    static let bookmarkKey = "screenshotSaveDirectory"

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            KeyboardShortcutsView()
                .tabItem { Label("Keyboard Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 360)
    }

    // MARK: - Static Resolution

    static var selectedScreenshotFormat: ScreenshotFormat {
        let raw = UserDefaults.standard.string(forKey: formatKey) ?? "jxl"
        return ScreenshotFormat(rawValue: raw) ?? .jxl
    }

    static func resolvedScreenshotDirectory(sourceURL: URL) -> URL? {
        let raw = UserDefaults.standard.string(forKey: modeKey) ?? "custom"
        let mode = ScreenshotLocationMode(rawValue: raw) ?? .custom

        switch mode {
        case .original:
            return sourceURL.deletingLastPathComponent()
        case .custom:
            return resolveBookmark() ?? desktopURL()
        case .ask:
            return nil
        }
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }

        return url
    }

    private static func desktopURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @State private var mode: ScreenshotLocationMode = .custom
    @State private var format: ScreenshotFormat = .jxl
    @State private var customFolderName: String = "Desktop"

    var body: some View {
        Form {
            LabeledContent("Screenshot Format") {
                Picker("", selection: $format) {
                    ForEach(ScreenshotFormat.allCases, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: format) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: SettingsView.formatKey)
                }
            }

            LabeledContent("Screenshot Location") {
                VStack(alignment: .trailing, spacing: 8) {
                    Picker("", selection: $mode) {
                        ForEach(ScreenshotLocationMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: mode) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: SettingsView.modeKey)
                        if newValue == .custom {
                            ensureCustomBookmark()
                        }
                    }

                    if mode == .custom {
                        HStack(spacing: 6) {
                            Text(customFolderName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button("Choose\u{2026}") {
                                chooseDirectory()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadState()
        }
    }

    private func loadState() {
        if let raw = UserDefaults.standard.string(forKey: SettingsView.modeKey),
           let saved = ScreenshotLocationMode(rawValue: raw) {
            mode = saved
        } else {
            mode = .custom
            UserDefaults.standard.set(ScreenshotLocationMode.custom.rawValue, forKey: SettingsView.modeKey)
        }

        if let raw = UserDefaults.standard.string(forKey: SettingsView.formatKey),
           let saved = ScreenshotFormat(rawValue: raw) {
            format = saved
        } else {
            format = .jxl
        }

        if mode == .custom {
            ensureCustomBookmark()
        }

        loadCustomFolderName()
    }

    private func ensureCustomBookmark() {
        if UserDefaults.standard.data(forKey: SettingsView.bookmarkKey) == nil {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            if let data = try? desktop.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: SettingsView.bookmarkKey)
            }
        }
        loadCustomFolderName()
    }

    private func loadCustomFolderName() {
        guard let data = UserDefaults.standard.data(forKey: SettingsView.bookmarkKey) else {
            customFolderName = "Desktop"
            return
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            customFolderName = "Desktop"
            return
        }

        if isStale {
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: SettingsView.bookmarkKey)
            }
        }

        customFolderName = url.lastPathComponent
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a default folder for screenshots"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: SettingsView.bookmarkKey)
            customFolderName = url.lastPathComponent
        } catch {
            // Silently fail — user keeps previous setting
        }
    }
}

// MARK: - Keyboard Shortcuts

private struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                shortcutSection("Playback", shortcuts: [
                    ("Space / K", "Play / Pause"),
                    ("J", "Reverse (press again to increase speed)"),
                    ("L", "Fast Forward (press again to increase speed)"),
                ])

                shortcutSection("Navigation", shortcuts: [
                    ("\u{2190}", "Back 1 frame"),
                    ("\u{2192}", "Forward 1 frame"),
                    ("\u{2191}", "Back 10 frames"),
                    ("\u{2193}", "Forward 10 frames"),
                    ("\u{21E7}\u{2190}", "Back 10 seconds"),
                    ("\u{21E7}\u{2192}", "Forward 10 seconds"),
                    ("\u{2318}\u{2191}", "Jump to start"),
                    ("\u{2318}\u{2193}", "Jump to end"),
                ])

                shortcutSection("Trim", shortcuts: [
                    ("I", "Set trim in"),
                    ("O", "Set trim out"),
                    ("\u{2325}I", "Clear trim in"),
                    ("\u{2325}O", "Clear trim out"),
                    ("\u{2325}X", "Clear all trim points"),
                    ("\u{2318}E", "Export trim"),
                ])

                shortcutSection("General", shortcuts: [
                    ("\u{2318}S", "Screenshot"),
                    ("F", "Toggle fullscreen"),
                    ("T", "Cycle timecode display"),
                    ("\u{2318}I", "Toggle inspector"),
                    ("\u{2318}O", "Open file"),
                    ("\u{2318},", "Settings"),
                ])
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                HStack {
                    Text(shortcut.0)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)

                    Text(shortcut.1)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
