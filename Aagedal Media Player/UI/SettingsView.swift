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

enum TrimExportFormat: String, CaseIterable {
    case copy = "copy"
    case gif = "gif"
    case animatedAVIF = "animatedAVIF"
    case hardwareH264 = "hardwareH264"
    case hardwareH265 = "hardwareH265"

    var label: String {
        switch self {
        case .copy: "Lossless Copy"
        case .gif: "GIF"
        case .animatedAVIF: "Animated AVIF"
        case .hardwareH264: "Hardware H.264"
        case .hardwareH265: "Hardware H.265"
        }
    }

    var fileExtension: String? {
        switch self {
        case .copy: nil
        case .gif: "gif"
        case .animatedAVIF: "avif"
        case .hardwareH264: "mp4"
        case .hardwareH265: "mp4"
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

enum ExportWidthPreset: Int, CaseIterable {
    case original = 0
    case w2160 = 2160
    case w1080 = 1080
    case w720 = 720
    case w480 = 480
    case w320 = 320

    var label: String {
        switch self {
        case .original: "Original"
        case .w2160: "2160"
        case .w1080: "1080"
        case .w720: "720"
        case .w480: "480"
        case .w320: "320"
        }
    }
}

struct SettingsView: View {
    static let modeKey = "screenshotLocationMode"
    static let formatKey = "screenshotFormat"
    static let bookmarkKey = "screenshotSaveDirectory"
    static let trimModeKey = "trimLocationMode"
    static let trimBookmarkKey = "trimSaveDirectory"

    // Export format keys
    static let trimFormatKey = "trimExportFormat"
    static let screenshotJXLQualityKey = "screenshotJXLQuality"
    static let screenshotJPEGQualityKey = "screenshotJPEGQuality"
    static let gifFrameRateKey = "gifFrameRate"
    static let gifWidthKey = "gifWidth"
    static let avifWidthKey = "avifWidth"
    static let h264WidthKey = "h264Width"
    static let h265WidthKey = "h265Width"
    static let avifQualityKey = "avifQuality"
    static let avifSpeedKey = "avifSpeed"
    static let h264QualityKey = "h264Quality"
    static let h265QualityKey = "h265Quality"

    // Scope keys
    static let scopeDisplayModeKey = "scopeDisplayMode"
    static let scopeBackgroundKey = "scopeBackground"
    static let scopeResolutionKey = "scopeResolution"
    static let scopeFrameRateKey = "scopeFrameRate"

    // Audio waveform keys
    static let audioWaveformDisplayModeKey = "audioWaveformDisplayMode"
    static let audioWaveformBackgroundKey = "audioWaveformBackground"
    static let audioWaveformColorKey = "audioWaveformColor"
    static let showAllMonoWaveformsKey = "showAllMonoWaveforms"

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
        let raw = UserDefaults.standard.string(forKey: formatKey) ?? "jxl"
        return ScreenshotFormat(rawValue: raw) ?? .jxl
    }

    static var selectedTrimExportFormat: TrimExportFormat {
        let raw = UserDefaults.standard.string(forKey: trimFormatKey) ?? "copy"
        return TrimExportFormat(rawValue: raw) ?? .copy
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
    @AppStorage("showCursorHideHint") private var showCursorHideHint = true
    @AppStorage("precisionScrubFactor") private var precisionScrubFactor: Double = 10.0
    @AppStorage("alwaysUseMPV") private var alwaysUseMPV = false
    @AppStorage("openAtSourceResolution") private var openAtSourceResolution = true
    @AppStorage("clampWindowToScreen") private var clampWindowToScreen = true
    @AppStorage("centerWindowAfterResize") private var centerWindowAfterResize = true

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
                Toggle("Always Use MPV Player", isOn: $alwaysUseMPV)
                if alwaysUseMPV {
                    Text("ProRes RAW always uses Apple AVFoundation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    let modeKey: String
    let bookmarkKey: String

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
                        UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
                        if newValue == .custom {
                            ensureBookmark(key: bookmarkKey)
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
        if let raw = UserDefaults.standard.string(forKey: modeKey),
           let saved = SaveLocationMode(rawValue: raw) {
            mode = saved
        }
        if mode == .custom {
            ensureBookmark(key: bookmarkKey)
        }
    }

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

    private func folderNameFromBookmark() -> String {
        guard let url = SettingsView.resolveBookmark(key: bookmarkKey) else {
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
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderName = url.lastPathComponent
        }
    }
}

// MARK: - Screenshot Settings

private struct ScreenshotSettingsView: View {
    @State private var screenshotFormat: ScreenshotFormat = .jxl
    @AppStorage(SettingsView.screenshotJXLQualityKey) private var jxlQuality: Double = 90
    @AppStorage(SettingsView.screenshotJPEGQualityKey) private var jpegQuality: Double = 90

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
                        UserDefaults.standard.set(newValue.rawValue, forKey: SettingsView.formatKey)
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
                modeKey: SettingsView.modeKey,
                bookmarkKey: SettingsView.bookmarkKey
            )
        }
        .formStyle(.grouped)
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: SettingsView.formatKey),
               let saved = ScreenshotFormat(rawValue: raw) {
                screenshotFormat = saved
            }
        }
    }
}

// MARK: - Export Settings

private struct ExportSettingsView: View {
    @AppStorage(SettingsView.trimFormatKey) private var formatRaw: String = TrimExportFormat.copy.rawValue

    @AppStorage(SettingsView.gifFrameRateKey) private var gifFrameRate: Double = 15
    @AppStorage(SettingsView.gifWidthKey) private var gifWidth: Int = ExportWidthPreset.w720.rawValue
    @AppStorage(SettingsView.avifWidthKey) private var avifWidth: Int = ExportWidthPreset.w1080.rawValue
    @AppStorage(SettingsView.h264WidthKey) private var h264Width: Int = ExportWidthPreset.original.rawValue
    @AppStorage(SettingsView.h265WidthKey) private var h265Width: Int = ExportWidthPreset.original.rawValue

    @AppStorage(SettingsView.avifQualityKey) private var avifQuality: Double = 28
    @AppStorage(SettingsView.avifSpeedKey) private var avifSpeed: Double = 4

    @AppStorage(SettingsView.h264QualityKey) private var h264Quality: Double = 65
    @AppStorage(SettingsView.h265QualityKey) private var h265Quality: Double = 65

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
                    Text("Lossless stream copy. No re-encoding.")
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

                case .hardwareH265:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $h265Quality, in: 1...100, step: 1)
                            Text("\(Int(h265Quality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
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
                modeKey: SettingsView.trimModeKey,
                bookmarkKey: SettingsView.trimBookmarkKey
            )
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scope Settings

private struct ScopeSettingsView: View {
    @AppStorage(SettingsView.scopeDisplayModeKey) private var displayMode: String = ScopeDisplayMode.overlay.rawValue
    @AppStorage(SettingsView.scopeBackgroundKey) private var background: String = ScopeBackground.transparent.rawValue
    @AppStorage(SettingsView.scopeResolutionKey) private var resolution: Int = ScopeResolution.standard.rawValue
    @AppStorage(SettingsView.scopeFrameRateKey) private var frameRate: Double = 15

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
    @AppStorage(SettingsView.audioWaveformDisplayModeKey) private var displayMode: String = AudioWaveformDisplayMode.overlay.rawValue
    @AppStorage(SettingsView.audioWaveformBackgroundKey) private var background: String = AudioWaveformBackground.transparent.rawValue
    @AppStorage(SettingsView.audioWaveformColorKey) private var waveformColor: String = AudioWaveformColor.pink.rawValue
    @AppStorage(SettingsView.showAllMonoWaveformsKey) private var showAllMonoWaveforms: Bool = false

    var body: some View {
        Form {
            Section("Audio Waveform") {
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
    @AppStorage("precisionScrubFactor") private var precisionScrubFactor: Double = 10.0

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

// MARK: - Updates

private struct UpdateSettingsView: View {
    @StateObject private var checker = UpdateChecker.shared

    @AppStorage("updateCheckInterval") private var checkInterval: Double = 7 * 24 * 3600

    private static let releasesURL = URL(string: "https://github.com/aagedal/Aagedal-Media-Player/releases")!

    private var intervalOptions: [(String, Double)] {
        [
            ("Daily", 24 * 3600),
            ("Weekly", 7 * 24 * 3600),
            ("Monthly", 30 * 24 * 3600),
            ("Never", 0),
        ]
    }

    var body: some View {
        Form {
            Section("Current Version") {
                LabeledContent("Version") {
                    Text(checker.currentVersion)
                        .monospacedDigit()
                }
            }

            Section("Update Check") {
                LabeledContent("Check Frequency") {
                    Picker("", selection: $checkInterval) {
                        ForEach(intervalOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                LabeledContent("Last Checked") {
                    if let date = checker.lastChecked {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                        + Text(" ago")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if !checker.updateAvailable, checker.lastChecked != nil, !checker.isChecking {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Up to date")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check Now") {
                        Task { await checker.checkNow() }
                    }
                    .disabled(checker.isChecking)
                }
            }

            if checker.updateAvailable, let latest = checker.latestVersion {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(latest) Available")
                                .fontWeight(.medium)
                            Text("You are running \(checker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Link("Download", destination: Self.releasesURL)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}
