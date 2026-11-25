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
    @State private var selectedCategory: SettingsCategory = .general
    @State private var searchText: String = ""
    @State private var isSidebarCompact: Bool = false
    @State private var highlightedSection: String?
    @FocusState private var isSearchFocused: Bool
    @ObservedObject private var cleanfeed = CleanfeedSession.shared

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchIndex.search(trimmedSearch)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: isSidebarCompact ? 56 : 224)
                .background(.background.secondary)

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 660, idealWidth: 740, maxWidth: 920, minHeight: 480, idealHeight: 560, maxHeight: 760)
        .animation(.snappy(duration: 0.18), value: isSidebarCompact)
        .onChange(of: searchText) { _, newValue in
            let matches = SettingsSearchIndex.search(newValue)
            if let first = matches.first, !matches.contains(where: { $0.category == selectedCategory }) {
                selectedCategory = first.category
                highlightedSection = first.section
            } else if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                highlightedSection = nil
            }
        }
        .background {
            // Hidden Cmd+F shortcut to focus the settings search bar
            Button("") {
                if isSidebarCompact { isSidebarCompact = false }
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            Divider()

            if trimmedSearch.isEmpty || isSidebarCompact {
                categoryList
            } else {
                searchResultsList
            }
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 6) {
            if !isSidebarCompact {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            highlightedSection = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Button {
                isSidebarCompact.toggle()
                if isSidebarCompact { isSearchFocused = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSidebarCompact ? "Expand sidebar" : "Collapse sidebar to icons")
        }
        .padding(.horizontal, isSidebarCompact ? 8 : 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: isSidebarCompact ? .center : .leading)
    }

    private var categoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(SettingsCategoryGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        if !isSidebarCompact {
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 2)
                        }

                        ForEach(group.categories) { category in
                            sidebarRow(for: category)
                        }
                    }
                }
            }
            .padding(.horizontal, isSidebarCompact ? 6 : 8)
            .padding(.vertical, 10)
        }
    }

    private func sidebarRow(for category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
            highlightedSection = nil
        } label: {
            HStack(spacing: 9) {
                categoryIconBadge(category, size: 22)

                if !isSidebarCompact {
                    Text(category.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if category == .cleanfeed, cleanfeed.isStreaming {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .help("Cleanfeed active")
                    }
                }
            }
            .padding(.horizontal, isSidebarCompact ? 0 : 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: isSidebarCompact ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSidebarCompact ? category.title : "")
    }

    private var searchResultsList: some View {
        ScrollView {
            if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("No Matching Settings")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Try a different term such as “4K”, “SDI”, “JXL”, or “waveform”.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(searchResults) { item in
                        let isSelected = selectedCategory == item.category && highlightedSection == item.section
                        Button {
                            selectedCategory = item.category
                            highlightedSection = item.section
                        } label: {
                            HStack(spacing: 9) {
                                categoryIconBadge(item.category, size: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(item.category.title) \u{203A} \(item.section)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }

    private func categoryIconBadge(_ category: SettingsCategory, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(categoryTint(category).gradient)
                .frame(width: size, height: size)
            Image(systemName: category.systemImage)
                .font(.system(size: size * 0.54, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func categoryTint(_ category: SettingsCategory) -> Color {
        switch category {
        case .general: .gray
        case .cleanfeed: .indigo
        case .scopes: .teal
        case .audio: .pink
        case .screenshots: .orange
        case .export: .green
        case .shortcuts: .blue
        case .updates: .cyan
        }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        VStack(spacing: 0) {
            detailHeader

            Divider()

            Group {
                switch selectedCategory {
                case .general:
                    GeneralSettingsView()
                case .cleanfeed:
                    CleanfeedSettingsView()
                case .scopes:
                    ScopeSettingsView()
                case .audio:
                    AudioSettingsView()
                case .screenshots:
                    ScreenshotSettingsView()
                case .export:
                    ExportSettingsView()
                case .shortcuts:
                    KeyboardShortcutsView(filterQuery: trimmedSearch)
                case .updates:
                    UpdateSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            categoryIconBadge(selectedCategory, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedCategory.title)
                    .font(.headline)
                Text(selectedCategory.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let highlightedSection, !trimmedSearch.isEmpty {
                Label(highlightedSection, systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            } else if selectedCategory == .cleanfeed, let device = cleanfeed.resolvedTargetDevice {
                HStack(spacing: 5) {
                    Circle()
                        .fill(cleanfeed.isStreaming ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(device.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
            return resolveBookmark(setting: bookmarkSetting)
        case .ask:
            return nil
        }
    }

    static var screenshotDirectoryRecoveryMessage: String? {
        directoryRecoveryMessage(modeSetting: AppSettings.screenshotLocationMode,
                                 bookmarkSetting: AppSettings.screenshotSaveDirectory)
    }

    static var trimDirectoryRecoveryMessage: String? {
        directoryRecoveryMessage(modeSetting: AppSettings.trimLocationMode,
                                 bookmarkSetting: AppSettings.trimSaveDirectory)
    }

    private static func directoryRecoveryMessage(
        modeSetting: AppSetting<String>, bookmarkSetting: AppSetting<Data?>
    ) -> String? {
        guard SaveLocationMode(rawValue: UserDefaults.standard.value(for: modeSetting)) == .custom,
              resolveBookmark(setting: bookmarkSetting) == nil else { return nil }
        return "Your saved export folder is unavailable. Choose a destination for this export. You can update the saved folder in Settings."
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
    @AppStorage(AppSettings.showTimelineDetails.key)
    private var showTimelineDetails = AppSettings.showTimelineDetails.defaultValue
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
                    Toggle("Sync Transport Commands Across Windows", isOn: $syncPlaybackControls)
                    Text("Shares playback and navigation commands. Windows keep independent playback clocks and are not continuously frame-locked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Playback > Align Windows to Current Timecode Once seeks other windows once, using source timecode when both files have it, otherwise relative time. This works independently of transport sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("For two-file inspection, open a comparison file in Compare Mode to use a shared timeline and explicit alignment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show Cursor Hide Zone Indicator", isOn: $showCursorHideHint)
                Toggle("Open Windows at Source Resolution", isOn: $openAtSourceResolution)
                if openAtSourceResolution {
                    Toggle("Limit Window Size to Screen", isOn: $clampWindowToScreen)
                    Toggle("Center Window on Screen", isOn: $centerWindowAfterResize)
                }
            }

            Section("Playback") {
                Toggle("Show Timeline Details", isOn: $showTimelineDetails)
                Text("Show chapters, review markers, and comparison overlap. Turn off for a minimal timeline; trim points remain visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Cleanfeed Output Settings

private struct CleanfeedSettingsView: View {
    @ObservedObject private var cleanfeed = CleanfeedSession.shared

    var body: some View {
        Form {
            Section("External Video Output (CoreMediaIO)") {
                if cleanfeed.availableDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No CoreMediaIO output device detected.")
                            .foregroundStyle(.secondary)
                        Text("Connect an SDI/HDMI device such as a Blackmagic UltraStudio and ensure its macOS Driver Extension and Camera Extension are enabled in System Settings \u{2192} General \u{2192} Login Items & Extensions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Output Device") {
                        Picker("", selection: Binding(
                            get: { cleanfeed.resolvedTargetDevice?.uid ?? "" },
                            set: { cleanfeed.selectedDeviceUID = $0 }
                        )) {
                            ForEach(cleanfeed.availableDevices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .labelsHidden()
                    }
                }

                LabeledContent("Status") {
                    Text(cleanfeed.statusSummary)
                        .foregroundStyle(cleanfeed.errorMessage != nil ? .red : .secondary)
                        .multilineTextAlignment(.trailing)
                }

                if cleanfeed.isStreaming {
                    LabeledContent("Telemetry") {
                        Text("\(cleanfeed.stats.framesScheduled) scheduled \u{2022} \(cleanfeed.stats.droppedFrames) dropped \u{2022} \(cleanfeed.stats.underrunCount) underruns")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(cleanfeed.isColorBarsActive ? "Stop Color Bars Test" : "Send Color Bars Test") {
                        cleanfeed.toggleColorBarsTest()
                    }
                    .disabled(!cleanfeed.hasOutputDevice && !cleanfeed.isColorBarsActive)

                    Spacer()

                    Button("Refresh Devices") {
                        cleanfeed.refreshDevices()
                    }
                }
            }

            Section("Signal Format") {
                let caps = cleanfeed.capabilities

                LabeledContent("Resolution") {
                    Picker("", selection: Binding(
                        get: { caps.effectiveResolutionMode },
                        set: { cleanfeed.resolutionMode = $0 }
                    )) {
                        ForEach(caps.resolutionModes) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
                Text("Filtered to resolutions advertised by the selected device. Defaults to 1080p HD so HD displays don\u{2019}t lose signal on 4K files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Scan Mode") {
                    Picker("", selection: Binding(
                        get: { caps.effectiveScanMode },
                        set: { cleanfeed.scanMode = $0 }
                    )) {
                        ForEach(caps.scanModes) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .disabled(caps.scanModes.count <= 1)
                }
                Text("Interlaced options (such as 1080i50 / 1080i59.94) appear only when supported at the chosen resolution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Frame Rate") {
                    Picker("", selection: Binding(
                        get: { caps.effectiveFrameRateMode },
                        set: { cleanfeed.frameRateMode = $0 }
                    )) {
                        ForEach(caps.frameRateModes) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
                Text("Filtered to frame rates supported at the chosen resolution. Use a fixed rate to prevent monitor re-sync between clips, or cap automatic matching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Color Space") {
                    Picker("", selection: Binding(
                        get: { caps.effectiveColorMode },
                        set: { cleanfeed.colorMode = $0 }
                    )) {
                        ForEach(caps.colorModes) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .disabled(caps.colorModes.count <= 1)
                }
                Text("SDR (Rec.709) safely tone-maps HDR clips for standard monitors. HDR options appear only when supported by the connected device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Pixel Format") {
                    Picker("", selection: Binding(
                        get: { caps.effectivePixelFormatMode },
                        set: { cleanfeed.pixelFormatMode = $0 }
                    )) {
                        ForEach(caps.pixelFormatModes) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .disabled(caps.pixelFormatModes.count <= 1)
                }
                Text("Filtered to pixel formats supported at the chosen resolution and frame rate (e.g. 4K 50/60p requires 10-bit 4:2:2 v210).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio & Timecode") {
                Toggle("Route Audio to Output Device", isOn: Binding(
                    get: { cleanfeed.routeAudioToDevice },
                    set: { cleanfeed.routeAudioToDevice = $0 }
                ))
                Text("Routes playback audio to the output device\u{2019}s linked CoreAudio driver (SDI/HDMI embedded audio) while cleanfeed is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Embed SMPTE Timecode", isOn: Binding(
                    get: { cleanfeed.embedSMPTETimecode },
                    set: { cleanfeed.embedSMPTETimecode = $0 }
                ))
                Text("Attaches source or relative SMPTE timecode to each CoreMediaIO output frame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            cleanfeed.refreshDevices()
        }
    }
}

// MARK: - Keyboard Shortcuts

private struct KeyboardShortcutsView: View {
    let filterQuery: String
    @AppStorage(AppSettings.precisionScrubFactor.key)
    private var precisionScrubFactor = AppSettings.precisionScrubFactor.defaultValue

    private var allSections: [(title: String, shortcuts: [(String, String)])] {
        [
            ("Playback", [
                ("Space / K", "Play / Pause"),
                ("J", "Reverse (press again to increase speed)"),
                ("L", "Fast Forward (press again to increase speed)"),
            ]),
            ("Navigation", [
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
            ]),
            ("Trim", [
                ("I", "Set trim in"),
                ("O", "Set trim out"),
                ("\u{21E7}I", "Jump to trim in"),
                ("\u{21E7}O", "Jump to trim out"),
                ("\u{2325}I", "Clear trim in"),
                ("\u{2325}O", "Clear trim out"),
                ("\u{2325}X", "Clear all trim points"),
                ("\u{2318}E", "Export trim"),
            ]),
            ("Compare Mode", [
                ("B", "Toggle source A / B"),
                ("[ / ]", "Move wipe 2%"),
                ("\u{21E7}[ / ]", "Move wipe 10%"),
            ]),
            ("General", [
                ("\u{2318}N", "New window (multi-window mode)"),
                ("\u{21E7}\u{2318}S", "Align windows to current timecode once"),
                ("\u{2318}W", "Close window"),
                ("\u{2318}S", "Screenshot"),
                ("\u{2318}F", "Toggle fullscreen"),
                ("T", "Cycle timecode display"),
                ("\u{2318}I", "Toggle inspector"),
                ("\u{2318}O", "Open file"),
                ("\u{21E7}\u{2318}O", "Toggle cleanfeed output"),
                ("\u{21E7}\u{2318}R", "Reload player"),
                ("\u{2318},", "Settings"),
            ]),
        ]
    }

    private var filteredSections: [(title: String, shortcuts: [(String, String)])] {
        let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allSections }
        let matched = allSections.compactMap { section -> (title: String, shortcuts: [(String, String)])? in
            if section.title.lowercased().contains(query) {
                return section
            }
            let items = section.shortcuts.filter { key, desc in
                key.lowercased().contains(query) || desc.lowercased().contains(query)
            }
            return items.isEmpty ? nil : (section.title, items)
        }
        return matched.isEmpty ? allSections : matched
    }

    var body: some View {
        Form {
            ForEach(filteredSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(Array(section.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                        HStack {
                            Text(shortcut.1)
                            Spacer()
                            Text(shortcut.0)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
