// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum SaveLocationMode: String, CaseIterable {
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
    static let trimModeKey = "trimLocationMode"
    static let trimBookmarkKey = "trimSaveDirectory"

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            KeyboardShortcutsView()
                .tabItem { Label("Keyboard Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 440)
    }

    // MARK: - Static Resolution

    static var selectedScreenshotFormat: ScreenshotFormat {
        let raw = UserDefaults.standard.string(forKey: formatKey) ?? "jxl"
        return ScreenshotFormat(rawValue: raw) ?? .jxl
    }

    static func resolvedScreenshotDirectory(sourceURL: URL) -> URL? {
        resolvedDirectory(modeKey: modeKey, bookmarkKey: bookmarkKey, defaultMode: .custom, sourceURL: sourceURL)
    }

    static func resolvedTrimDirectory(sourceURL: URL) -> URL? {
        resolvedDirectory(modeKey: trimModeKey, bookmarkKey: trimBookmarkKey, defaultMode: .ask, sourceURL: sourceURL)
    }

    private static func resolvedDirectory(modeKey: String, bookmarkKey: String, defaultMode: SaveLocationMode, sourceURL: URL) -> URL? {
        let raw = UserDefaults.standard.string(forKey: modeKey) ?? defaultMode.rawValue
        let mode = SaveLocationMode(rawValue: raw) ?? defaultMode

        switch mode {
        case .original:
            return sourceURL.deletingLastPathComponent()
        case .custom:
            return resolveBookmark(key: bookmarkKey) ?? desktopURL()
        case .ask:
            return nil
        }
    }

    static func resolveBookmark(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
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
                UserDefaults.standard.set(fresh, forKey: key)
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
    @AppStorage("allowMultipleWindows") private var allowMultipleWindows = false
    @AppStorage("syncPlaybackControls") private var syncPlaybackControls = false

    @State private var screenshotMode: SaveLocationMode = .custom
    @State private var screenshotFormat: ScreenshotFormat = .jxl
    @State private var screenshotFolderName: String = "Desktop"

    @State private var trimMode: SaveLocationMode = .ask
    @State private var trimFolderName: String = "Desktop"

    var body: some View {
        Form {
            Section("Windows") {
                Toggle("Allow Multiple Windows", isOn: $allowMultipleWindows)
                if allowMultipleWindows {
                    Toggle("Sync Playback Controls", isOn: $syncPlaybackControls)
                }
            }

            Section("Screenshots") {
                LabeledContent("Format") {
                    Picker("", selection: $screenshotFormat) {
                        ForEach(ScreenshotFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: screenshotFormat) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: SettingsView.formatKey)
                    }
                }

                locationPicker(
                    selection: $screenshotMode,
                    folderName: screenshotFolderName,
                    modeKey: SettingsView.modeKey,
                    bookmarkKey: SettingsView.bookmarkKey,
                    onChoose: { chooseDirectory(bookmarkKey: SettingsView.bookmarkKey) { screenshotFolderName = $0 } }
                )
            }

            Section("Trim Export") {
                locationPicker(
                    selection: $trimMode,
                    folderName: trimFolderName,
                    modeKey: SettingsView.trimModeKey,
                    bookmarkKey: SettingsView.trimBookmarkKey,
                    onChoose: { chooseDirectory(bookmarkKey: SettingsView.trimBookmarkKey) { trimFolderName = $0 } }
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadState()
        }
    }

    private func locationPicker(
        selection: Binding<SaveLocationMode>,
        folderName: String,
        modeKey: String,
        bookmarkKey: String,
        onChoose: @escaping () -> Void
    ) -> some View {
        LabeledContent("Location") {
            VStack(alignment: .trailing, spacing: 8) {
                Picker("", selection: selection) {
                    ForEach(SaveLocationMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selection.wrappedValue) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
                    if newValue == .custom {
                        ensureBookmark(key: bookmarkKey)
                    }
                }

                if selection.wrappedValue == .custom {
                    HStack(spacing: 6) {
                        Text(folderName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Button("Choose\u{2026}") {
                            onChoose()
                        }
                    }
                }
            }
        }
    }

    // MARK: - State Loading

    private func loadState() {
        screenshotMode = loadMode(key: SettingsView.modeKey, default: .custom)
        trimMode = loadMode(key: SettingsView.trimModeKey, default: .ask)

        if let raw = UserDefaults.standard.string(forKey: SettingsView.formatKey),
           let saved = ScreenshotFormat(rawValue: raw) {
            screenshotFormat = saved
        }

        if screenshotMode == .custom {
            ensureBookmark(key: SettingsView.bookmarkKey)
        }
        if trimMode == .custom {
            ensureBookmark(key: SettingsView.trimBookmarkKey)
        }

        screenshotFolderName = folderName(for: SettingsView.bookmarkKey)
        trimFolderName = folderName(for: SettingsView.trimBookmarkKey)
    }

    private func loadMode(key: String, default defaultMode: SaveLocationMode) -> SaveLocationMode {
        if let raw = UserDefaults.standard.string(forKey: key),
           let saved = SaveLocationMode(rawValue: raw) {
            return saved
        }
        UserDefaults.standard.set(defaultMode.rawValue, forKey: key)
        return defaultMode
    }

    // MARK: - Bookmark Helpers

    private func ensureBookmark(key: String) {
        if UserDefaults.standard.data(forKey: key) == nil {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            if let data = try? desktop.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private func folderName(for bookmarkKey: String) -> String {
        guard let url = SettingsView.resolveBookmark(key: bookmarkKey) else {
            return "Desktop"
        }
        return url.lastPathComponent
    }

    private func chooseDirectory(bookmarkKey: String, update: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a default folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            update(url.lastPathComponent)
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
                    ("\u{2325}\u{2190}\u{2192}\u{2191}\u{2193}", "Same as above, current window only"),
                    ("\u{2325}Drag", "Precision scrub (10x slower)"),
                ])

                shortcutSection("Trim", shortcuts: [
                    ("I", "Set trim in"),
                    ("O", "Set trim out"),
                    ("\u{21E7}I", "Jump to trim in"),
                    ("\u{21E7}O", "Jump to trim out"),
                    ("\u{2325}I", "Clear trim in"),
                    ("\u{2325}O", "Clear trim out"),
                    ("\u{2325}X", "Clear all trim points"),
                    ("\u{2318}E", "Export trim"),
                ])

                shortcutSection("General", shortcuts: [
                    ("\u{2318}N", "New window (multi-window mode)"),
                    ("\u{2318}W", "Close window"),
                    ("\u{2318}S", "Screenshot"),
                    ("\u{2318}F", "Toggle fullscreen"),
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
