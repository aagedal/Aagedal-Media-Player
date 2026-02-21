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
    @State private var mode: ScreenshotLocationMode = .custom
    @State private var format: ScreenshotFormat = .jxl
    @State private var customFolderName: String = "Desktop"

    private static let modeKey = "screenshotLocationMode"
    private static let formatKey = "screenshotFormat"
    private static let bookmarkKey = "screenshotSaveDirectory"

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
                    UserDefaults.standard.set(newValue.rawValue, forKey: Self.formatKey)
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
                        UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey)
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
        .frame(width: 480)
        .onAppear {
            loadState()
        }
    }

    // MARK: - Private

    private func loadState() {
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let saved = ScreenshotLocationMode(rawValue: raw) {
            mode = saved
        } else {
            mode = .custom
            UserDefaults.standard.set(ScreenshotLocationMode.custom.rawValue, forKey: Self.modeKey)
        }

        if let raw = UserDefaults.standard.string(forKey: Self.formatKey),
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
        if UserDefaults.standard.data(forKey: Self.bookmarkKey) == nil {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            if let data = try? desktop.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            }
        }
        loadCustomFolderName()
    }

    private func loadCustomFolderName() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
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
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
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
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkKey)
            customFolderName = url.lastPathComponent
        } catch {
            // Silently fail — user keeps previous setting
        }
    }

    // MARK: - Static Resolution

    static var selectedScreenshotFormat: ScreenshotFormat {
        let raw = UserDefaults.standard.string(forKey: formatKey) ?? "jxl"
        return ScreenshotFormat(rawValue: raw) ?? .jxl
    }

    /// Resolves the screenshot directory based on current mode.
    /// - Parameter sourceURL: The URL of the currently playing media file.
    /// - Returns: A directory URL, or `nil` if the user should be prompted (ask mode).
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
