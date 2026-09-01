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

enum AudioWaveformColor: String, CaseIterable {
    case pink = "FF2D78"
    case blue = "4A9EE5"
    case red = "E54A4A"
    case green = "4AE57A"
    case white = "FFFFFF"

    var label: String {
        switch self {
        case .pink: "Pink"
        case .blue: "Blue"
        case .red: "Red"
        case .green: "Green"
        case .white: "White"
        }
    }

    /// Hex color string for ffmpeg (without #).
    var ffmpegHex: String { rawValue }

    /// SwiftUI preview color.
    var swiftUIColor: Color {
        let hex = rawValue
        let r = Double(Int(hex.prefix(2), radix: 16) ?? 0) / 255.0
        let g = Double(Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
        let b = Double(Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

enum AudioWaveformDisplayMode: String, CaseIterable {
    case window = "window"
    case overlay = "overlay"

    var label: String {
        switch self {
        case .window: "Separate Window"
        case .overlay: "Overlay"
        }
    }
}


enum AudioWaveformBackground: String, CaseIterable {
    case black = "black"
    case transparent = "transparent"

    var label: String {
        switch self {
        case .black: "Black"
        case .transparent: "Transparent"
        }
    }
}

enum ScopeDisplayMode: String, CaseIterable {
    case window = "window"
    case overlay = "overlay"

    var label: String {
        switch self {
        case .window: "Separate Window"
        case .overlay: "Overlay"
        }
    }
}

enum ScopeBackground: String, CaseIterable {
    case black = "black"
    case transparent = "transparent"

    var label: String {
        switch self {
        case .black: "Black"
        case .transparent: "Transparent"
        }
    }
}

enum ScopeResolution: Int, CaseIterable {
    case low = 360
    case standard = 720
    case high = 1080
    case ultra = 1440

    var label: String {
        switch self {
        case .low: "Low (360)"
        case .standard: "Standard (720)"
        case .high: "High (1080)"
        case .ultra: "Ultra (1440)"
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ScreenshotSettingsView()
                .tabItem { Label("Screenshots", systemImage: "camera") }

            ExportSettingsView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }

            ScopeSettingsView()
                .tabItem { Label("Scopes", systemImage: "waveform") }

            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "waveform.path") }

            KeyboardShortcutsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }

            UpdateSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480, height: 500)
    }

    // MARK: - Static Resolution

    static var selectedScreenshotFormat: ScreenshotFormat {
        let raw = UserDefaults.standard.value(for: AppSettings.screenshotFormat)
        return ScreenshotFormat(rawValue: raw) ?? .jxl
    }

    static var selectedTrimExportFormat: TrimExportFormat {
        let raw = UserDefaults.standard.value(for: AppSettings.trimExportFormat)
        return TrimExportFormat(rawValue: raw) ?? .copy
    }

    static func resolvedScreenshotDirectory(sourceURL: URL) -> URL? {
        resolvedDirectory(
            modeSetting: AppSettings.screenshotLocationMode,
            bookmarkSetting: AppSettings.screenshotSaveDirectory,
            defaultMode: .custom,
            sourceURL: sourceURL
        )
    }

    static func resolvedTrimDirectory(sourceURL: URL) -> URL? {
        resolvedDirectory(
            modeSetting: AppSettings.trimLocationMode,
            bookmarkSetting: AppSettings.trimSaveDirectory,
            defaultMode: .ask,
            sourceURL: sourceURL
        )
    }

    private static func resolvedDirectory(
        modeSetting: AppSetting<String>,
        bookmarkSetting: AppSetting<Data?>,
        defaultMode: SaveLocationMode,
        sourceURL: URL
    ) -> URL? {
        let raw = UserDefaults.standard.value(for: modeSetting)
        let mode = SaveLocationMode(rawValue: raw) ?? defaultMode

        switch mode {
        case .original:
            return sourceURL.deletingLastPathComponent()
        case .custom:
            return resolveBookmark(setting: bookmarkSetting) ?? desktopURL()
        case .ask:
            return nil
        }
    }

    static func resolveBookmark(setting: AppSetting<Data?>) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: setting.key) else {
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
                UserDefaults.standard.set(fresh, forKey: setting.key)
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
    @AppStorage(AppSettings.allowMultipleWindows.key)
    private var allowMultipleWindows = AppSettings.allowMultipleWindows.defaultValue
    @AppStorage(AppSettings.syncPlaybackControls.key)
    private var syncPlaybackControls = AppSettings.syncPlaybackControls.defaultValue
    @AppStorage(AppSettings.showCursorHideHint.key)
    private var showCursorHideHint = AppSettings.showCursorHideHint.defaultValue
    @AppStorage(AppSettings.precisionScrubFactor.key)
    private var precisionScrubFactor = AppSettings.precisionScrubFactor.defaultValue
    @AppStorage(AppSettings.openAtSourceResolution.key)
    private var openAtSourceResolution = AppSettings.openAtSourceResolution.defaultValue
    @AppStorage(AppSettings.clampWindowToScreen.key)
    private var clampWindowToScreen = AppSettings.clampWindowToScreen.defaultValue
    @AppStorage(AppSettings.centerWindowAfterResize.key)
    private var centerWindowAfterResize = AppSettings.centerWindowAfterResize.defaultValue

    var body: some View {
        Form {
            Section("Windows") {
                Toggle("Allow Multiple Windows", isOn: $allowMultipleWindows)
                if allowMultipleWindows {
                    Toggle("Sync Playback Controls", isOn: $syncPlaybackControls)
                }
                Toggle("Show Cursor Hide Zone Indicator", isOn: $showCursorHideHint)
                Toggle("Open Windows at Source Resolution", isOn: $openAtSourceResolution)
                if openAtSourceResolution {
                    Toggle("Limit Window Size to Screen", isOn: $clampWindowToScreen)
                    Toggle("Center Window on Screen", isOn: $centerWindowAfterResize)
                }
            }

            Section("Playback") {
                LabeledContent("Precision Scrub") {
                    HStack(spacing: 8) {
                        Slider(value: $precisionScrubFactor, in: 2...20, step: 1)
                        Text("\(Int(precisionScrubFactor))x slower")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Location Settings Section (Reusable)

private struct LocationSettingsSection: View {
    @Binding var mode: SaveLocationMode
    @State private var folderName: String = "Desktop"

    let modeSetting: AppSetting<String>
    let bookmarkSetting: AppSetting<Data?>

    var body: some View {
        Section("Save Location") {
            LabeledContent("Location") {
                VStack(alignment: .trailing, spacing: 8) {
                    Picker("", selection: $mode) {
                        ForEach(SaveLocationMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: mode) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, for: modeSetting)
                        if newValue == .custom {
                            ensureBookmark(setting: bookmarkSetting)
                        }
                    }

                    if mode == .custom {
                        HStack(spacing: 6) {
                            Text(folderName)
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
        .onAppear {
            loadMode()
            folderName = folderNameFromBookmark()
        }
    }

    private func loadMode() {
        if let raw = UserDefaults.standard.string(forKey: modeSetting.key),
           let saved = SaveLocationMode(rawValue: raw) {
            mode = saved
        }
        if mode == .custom {
            ensureBookmark(setting: bookmarkSetting)
        }
    }

    private func ensureBookmark(setting: AppSetting<Data?>) {
        if UserDefaults.standard.data(forKey: setting.key) == nil {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            if let data = try? desktop.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: setting.key)
            }
        }
    }

    private func folderNameFromBookmark() -> String {
        guard let url = SettingsView.resolveBookmark(setting: bookmarkSetting) else {
            return "Desktop"
        }
        return url.lastPathComponent
    }

    private func chooseDirectory() {
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
            UserDefaults.standard.set(data, forKey: bookmarkSetting.key)
            folderName = url.lastPathComponent
        }
    }
}

// MARK: - Screenshot Settings

private struct ScreenshotSettingsView: View {
    @State private var screenshotFormat: ScreenshotFormat = .jxl
    @AppStorage(AppSettings.screenshotJXLQuality.key)
    private var jxlQuality = AppSettings.screenshotJXLQuality.defaultValue
    @AppStorage(AppSettings.screenshotJPEGQuality.key)
    private var jpegQuality = AppSettings.screenshotJPEGQuality.defaultValue

    @State private var screenshotMode: SaveLocationMode = .custom

    var body: some View {
        Form {
            Section("Format") {
                LabeledContent("Format") {
                    Picker("", selection: $screenshotFormat) {
                        ForEach(ScreenshotFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: screenshotFormat) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, for: AppSettings.screenshotFormat)
                    }
                }

                switch screenshotFormat {
                case .jxl:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $jxlQuality, in: 0...100, step: 1)
                            Text("\(Int(jxlQuality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                case .jpeg:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $jpegQuality, in: 0...100, step: 1)
                            Text("\(Int(jpegQuality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                case .png:
                    Text("PNG is always lossless.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LocationSettingsSection(
                mode: $screenshotMode,
                modeSetting: AppSettings.screenshotLocationMode,
                bookmarkSetting: AppSettings.screenshotSaveDirectory
            )
        }
        .formStyle(.grouped)
        .onAppear {
            screenshotFormat = SettingsView.selectedScreenshotFormat
        }
    }
}

// MARK: - Export Settings

private struct ExportSettingsView: View {
    @AppStorage(AppSettings.trimExportFormat.key)
    private var formatRaw = AppSettings.trimExportFormat.defaultValue

    @AppStorage(AppSettings.gifFrameRate.key)
    private var gifFrameRate = AppSettings.gifFrameRate.defaultValue
    @AppStorage(AppSettings.gifWidth.key)
    private var gifWidth = AppSettings.gifWidth.defaultValue
    @AppStorage(AppSettings.avifWidth.key)
    private var avifWidth = AppSettings.avifWidth.defaultValue
    @AppStorage(AppSettings.h264Width.key)
    private var h264Width = AppSettings.h264Width.defaultValue
    @AppStorage(AppSettings.h265Width.key)
    private var h265Width = AppSettings.h265Width.defaultValue

    @AppStorage(AppSettings.avifQuality.key)
    private var avifQuality = AppSettings.avifQuality.defaultValue
    @AppStorage(AppSettings.avifSpeed.key)
    private var avifSpeed = AppSettings.avifSpeed.defaultValue

    @AppStorage(AppSettings.h264Quality.key)
    private var h264Quality = AppSettings.h264Quality.defaultValue
    @AppStorage(AppSettings.h265Quality.key)
    private var h265Quality = AppSettings.h265Quality.defaultValue

    @State private var trimMode: SaveLocationMode = .ask

    private var format: TrimExportFormat {
        TrimExportFormat(rawValue: formatRaw) ?? .copy
    }

    private var widthBinding: Binding<Int> {
        switch format {
        case .copy: .constant(0)
        case .gif: $gifWidth
        case .animatedAVIF: $avifWidth
        case .hardwareH264: $h264Width
        case .hardwareH265: $h265Width
        }
    }

    var body: some View {
        Form {
            Section("Format") {
                Picker("Format", selection: $formatRaw) {
                    ForEach(TrimExportFormat.allCases, id: \.self) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                }

                switch format {
                case .copy:
                    Text("Fast and lossless, but the trim start may move to the preceding keyframe. The source container is preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .gif:
                    LabeledContent("Frame Rate") {
                        HStack(spacing: 8) {
                            Slider(value: $gifFrameRate, in: 5...30, step: 1)
                            Text("\(Int(gifFrameRate)) fps")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }

                case .animatedAVIF:
                    LabeledContent("Quality (CRF)") {
                        HStack(spacing: 8) {
                            Slider(value: $avifQuality, in: 0...63, step: 1)
                            Text("\(Int(avifQuality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Lower values = higher quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Speed") {
                        HStack(spacing: 8) {
                            Slider(value: $avifSpeed, in: 0...8, step: 1)
                            Text("\(Int(avifSpeed))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                case .hardwareH264:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $h264Quality, in: 1...100, step: 1)
                            Text("\(Int(h264Quality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Frame-accurate trim. Re-encodes video as H.264 and audio as AAC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .hardwareH265:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $h265Quality, in: 1...100, step: 1)
                            Text("\(Int(h265Quality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Frame-accurate trim. Re-encodes video as H.265 and audio as AAC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if format != .copy {
                    LabeledContent("Short Side") {
                        Picker("", selection: widthBinding) {
                            ForEach(ExportWidthPreset.allCases, id: \.self) { p in
                                Text(p.label).tag(p.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Limits the shortest side in pixels. The other side scales proportionally. Videos already within the limit are not upscaled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LocationSettingsSection(
                mode: $trimMode,
                modeSetting: AppSettings.trimLocationMode,
                bookmarkSetting: AppSettings.trimSaveDirectory
            )
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scope Settings

private struct ScopeSettingsView: View {
    @AppStorage(AppSettings.scopeDisplayMode.key)
    private var displayMode = AppSettings.scopeDisplayMode.defaultValue
    @AppStorage(AppSettings.scopeBackground.key)
    private var background = AppSettings.scopeBackground.defaultValue
    @AppStorage(AppSettings.scopeResolution.key)
    private var resolution = AppSettings.scopeResolution.defaultValue
    @AppStorage(AppSettings.scopeFrameRate.key)
    private var frameRate = AppSettings.scopeFrameRate.defaultValue

    var body: some View {
        Form {
            Section("Display") {
                LabeledContent("Display Mode") {
                    Picker("", selection: $displayMode) {
                        ForEach(ScopeDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                Text("Overlay renders scopes over the video. Separate window opens a floating panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if displayMode == ScopeDisplayMode.overlay.rawValue {
                    LabeledContent("Background") {
                        Picker("", selection: $background) {
                            ForEach(ScopeBackground.allCases, id: \.self) { bg in
                                Text(bg.label).tag(bg.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Transparent lets the video show through the scopes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Rendering") {
                LabeledContent("Resolution") {
                    Picker("", selection: $resolution) {
                        ForEach(ScopeResolution.allCases, id: \.self) { r in
                            Text(r.label).tag(r.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                Text("Higher resolution shows more detail but uses more CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Performance") {
                LabeledContent("Update Rate") {
                    HStack(spacing: 8) {
                        Slider(value: $frameRate, in: 5...30, step: 1)
                        Text("\(Int(frameRate)) fps")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Text("How often scopes refresh. Lower values reduce CPU usage. Changes apply when scopes are reopened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio Settings

private struct AudioSettingsView: View {
    @AppStorage(AppSettings.audioWaveformDisplayMode.key)
    private var displayMode = AppSettings.audioWaveformDisplayMode.defaultValue
    @AppStorage(AppSettings.audioWaveformBackground.key)
    private var background = AppSettings.audioWaveformBackground.defaultValue
    @AppStorage(AppSettings.audioWaveformColor.key)
    private var waveformColor = AppSettings.audioWaveformColor.defaultValue
    @AppStorage(AppSettings.showAllMonoWaveforms.key)
    private var showAllMonoWaveforms = AppSettings.showAllMonoWaveforms.defaultValue
    @AppStorage(AppSettings.audioWaveformBoost.key)
    private var waveformBoost = AppSettings.audioWaveformBoost.defaultValue
    @AppStorage(AppSettings.automaticAudioOnlyWaveform.key)
    private var automaticAudioOnlyWaveform = AppSettings.automaticAudioOnlyWaveform.defaultValue

    var body: some View {
        Form {
            Section("Audio Waveform") {
                Toggle("Show automatically for audio-only files", isOn: $automaticAudioOnlyWaveform)
                Text("Audio-only files use the waveform as their main playback surface. Turn this off for a simpler title-only presentation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Display Mode") {
                    Picker("", selection: $displayMode) {
                        ForEach(AudioWaveformDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                Text("Overlay renders the waveform over the video. Separate window opens a floating panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if displayMode == AudioWaveformDisplayMode.overlay.rawValue {
                    LabeledContent("Background") {
                        Picker("", selection: $background) {
                            ForEach(AudioWaveformBackground.allCases, id: \.self) { bg in
                                Text(bg.label).tag(bg.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Transparent lets the video show through the waveform.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Color") {
                    Picker("", selection: $waveformColor) {
                        ForEach(AudioWaveformColor.allCases, id: \.self) { c in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(c.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                Text(c.label)
                            }
                            .tag(c.rawValue)
                        }
                    }
                    .labelsHidden()
                }

                LabeledContent("Boost") {
                    HStack(spacing: 8) {
                        Slider(value: $waveformBoost, in: 0...100, step: 1)
                        Text("\(Int(waveformBoost))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Text("Amplifies quiet parts of the waveform while keeping peaks unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show all waveforms for multi-mono files", isOn: $showAllMonoWaveforms)
                Text("When enabled, files containing only mono tracks show all track waveforms at once instead of just the selected track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Keyboard Shortcuts

private struct KeyboardShortcutsView: View {
    @AppStorage(AppSettings.precisionScrubFactor.key)
    private var precisionScrubFactor = AppSettings.precisionScrubFactor.defaultValue

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
                    ("\u{2318}[", "Previous file in folder"),
                    ("\u{2318}]", "Next file in folder"),
                    ("\u{2325}\u{2190}\u{2192}\u{2191}\u{2193}", "Same as above, current window only"),
                    ("\u{2325}Drag", "Precision scrub (\(Int(precisionScrubFactor))x slower)"),
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
                    ("\u{21E7}\u{2318}R", "Reload player"),
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
