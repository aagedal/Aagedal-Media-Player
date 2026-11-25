// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Category taxonomy and search index for the sidebar-based Settings window.

import Foundation

nonisolated enum SettingsCategoryGroup: String, CaseIterable, Sendable, Identifiable {
    case playbackAndDisplay
    case analysisAndMonitoring
    case captureAndExport
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playbackAndDisplay: "Playback & Display"
        case .analysisAndMonitoring: "Analysis & Monitoring"
        case .captureAndExport: "Capture & Export"
        case .app: "Application"
        }
    }

    var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.group == self }
    }
}

nonisolated enum SettingsCategory: String, CaseIterable, Sendable, Identifiable {
    case general
    case cleanfeed
    case scopes
    case audio
    case screenshots
    case export
    case shortcuts
    case updates

    var id: String { rawValue }

    var group: SettingsCategoryGroup {
        switch self {
        case .general, .cleanfeed: .playbackAndDisplay
        case .scopes, .audio: .analysisAndMonitoring
        case .screenshots, .export: .captureAndExport
        case .shortcuts, .updates: .app
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .cleanfeed: "Cleanfeed Output"
        case .scopes: "Video Scopes"
        case .audio: "Audio & Waveform"
        case .screenshots: "Screenshots"
        case .export: "Trim & Export"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Windows, playback behavior, and timeline display"
        case .cleanfeed: "External SDI/HDMI video output via CoreMediaIO"
        case .scopes: "Waveform, vectorscope, and parade rendering"
        case .audio: "Audio waveform presentation and multi-mono layout"
        case .screenshots: "Still image format, quality, and save destination"
        case .export: "Trim encoding presets, sizing, and destination"
        case .shortcuts: "Keyboard controls for playback, navigation, and trim"
        case .updates: "Application version and automatic update checks"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .cleanfeed: "tv"
        case .scopes: "waveform"
        case .audio: "waveform.path"
        case .screenshots: "camera.fill"
        case .export: "square.and.arrow.up.fill"
        case .shortcuts: "command"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

nonisolated struct SettingsSearchItem: Sendable, Equatable, Identifiable {
    let id: String
    let category: SettingsCategory
    let section: String
    let title: String
    let keywords: [String]
}

nonisolated enum SettingsSearchIndex {
    static let allItems: [SettingsSearchItem] = [
        // General
        SettingsSearchItem(
            id: "general.multiwindow",
            category: .general,
            section: "Windows",
            title: "Allow Multiple Windows",
            keywords: ["window", "multiple", "tabs", "sync", "transport", "timecode"]
        ),
        SettingsSearchItem(
            id: "general.sync",
            category: .general,
            section: "Windows",
            title: "Sync Transport Commands Across Windows",
            keywords: ["sync", "synchronize", "playback", "windows", "compare"]
        ),
        SettingsSearchItem(
            id: "general.cursor",
            category: .general,
            section: "Windows",
            title: "Show Cursor Hide Zone Indicator",
            keywords: ["cursor", "mouse", "hide", "pointer", "overlay"]
        ),
        SettingsSearchItem(
            id: "general.resolution",
            category: .general,
            section: "Windows",
            title: "Open Windows at Source Resolution",
            keywords: ["window", "size", "source", "resolution", "center", "clamp", "screen"]
        ),
        SettingsSearchItem(
            id: "general.timeline",
            category: .general,
            section: "Playback",
            title: "Show Timeline Details",
            keywords: ["timeline", "chapters", "markers", "review", "trim"]
        ),
        SettingsSearchItem(
            id: "general.scrub",
            category: .general,
            section: "Playback",
            title: "Precision Scrub",
            keywords: ["scrub", "option", "drag", "slow", "jog", "timeline"]
        ),

        // Cleanfeed Output
        SettingsSearchItem(
            id: "cleanfeed.device",
            category: .cleanfeed,
            section: "External Video Output",
            title: "Output Device & Color Bars Test",
            keywords: ["cleanfeed", "clean feed", "blackmagic", "ultrastudio", "decklink", "aja", "sdi", "hdmi", "coremediaio", "cmio", "monitor", "tv", "color bars", "test"]
        ),
        SettingsSearchItem(
            id: "cleanfeed.resolution",
            category: .cleanfeed,
            section: "Signal Format",
            title: "Cleanfeed Resolution Limit",
            keywords: ["cleanfeed", "resolution", "720p", "1080p", "2k", "2160p", "4k", "uhd", "dci", "hd", "limit", "cap", "downscale"]
        ),
        SettingsSearchItem(
            id: "cleanfeed.framerate",
            category: .cleanfeed,
            section: "Signal Format",
            title: "Cleanfeed Frame Rate",
            keywords: ["cleanfeed", "fps", "frame rate", "23.98", "24", "25", "29.97", "30", "50", "59.94", "60", "cadence"]
        ),
        SettingsSearchItem(
            id: "cleanfeed.colorspace",
            category: .cleanfeed,
            section: "Signal Format",
            title: "Cleanfeed Color Space (SDR / HDR)",
            keywords: ["cleanfeed", "color", "sdr", "rec709", "rec.709", "hdr", "hdr10", "pq", "hlg", "rec2020", "tone map"]
        ),
        SettingsSearchItem(
            id: "cleanfeed.pixelformat",
            category: .cleanfeed,
            section: "Signal Format",
            title: "Cleanfeed Pixel Format (v210 / BGRA)",
            keywords: ["cleanfeed", "pixel", "v210", "10-bit", "10bit", "8-bit", "bgra", "4:2:2", "yuv", "rgb"]
        ),
        SettingsSearchItem(
            id: "cleanfeed.audio",
            category: .cleanfeed,
            section: "Audio & Timecode",
            title: "Route Audio to Output Device",
            keywords: ["cleanfeed", "audio", "embedded", "sdi", "hdmi", "coreaudio", "speakers"]
        ),
        SettingsSearchItem(
            id: "cleanfeed.timecode",
            category: .cleanfeed,
            section: "Audio & Timecode",
            title: "Embed SMPTE Timecode",
            keywords: ["cleanfeed", "timecode", "smpte", "tc", "sdi"]
        ),

        // Video Scopes
        SettingsSearchItem(
            id: "scopes.display",
            category: .scopes,
            section: "Display",
            title: "Scope Display Mode & Background",
            keywords: ["scopes", "waveform", "vectorscope", "parade", "overlay", "window", "transparent", "black"]
        ),
        SettingsSearchItem(
            id: "scopes.resolution",
            category: .scopes,
            section: "Rendering",
            title: "Scope Resolution & Update Rate",
            keywords: ["scopes", "resolution", "fps", "frame rate", "cpu", "performance", "360", "720", "1080", "1440"]
        ),

        // Audio & Waveform
        SettingsSearchItem(
            id: "audio.auto",
            category: .audio,
            section: "Audio Waveform",
            title: "Automatic Audio-Only Waveform",
            keywords: ["audio", "waveform", "audio-only", "wav", "mp3", "flac"]
        ),
        SettingsSearchItem(
            id: "audio.appearance",
            category: .audio,
            section: "Audio Waveform",
            title: "Waveform Display Mode, Color & Boost",
            keywords: ["audio", "waveform", "color", "pink", "blue", "red", "green", "white", "boost", "gain", "overlay", "transparent"]
        ),
        SettingsSearchItem(
            id: "audio.multimono",
            category: .audio,
            section: "Audio Waveform",
            title: "Show All Waveforms for Multi-Mono Files",
            keywords: ["audio", "mono", "multi-mono", "tracks", "channels", "broadcast"]
        ),

        // Screenshots
        SettingsSearchItem(
            id: "screenshots.format",
            category: .screenshots,
            section: "Format",
            title: "Screenshot Format & Quality",
            keywords: ["screenshot", "still", "capture", "jxl", "jpeg", "jpg", "png", "quality", "lossless"]
        ),
        SettingsSearchItem(
            id: "screenshots.location",
            category: .screenshots,
            section: "Save Location",
            title: "Screenshot Save Location",
            keywords: ["screenshot", "folder", "directory", "save", "location", "desktop", "original"]
        ),

        // Trim & Export
        SettingsSearchItem(
            id: "export.format",
            category: .export,
            section: "Format",
            title: "Trim Export Format & Quality",
            keywords: ["export", "trim", "lossless", "copy", "gif", "avif", "h264", "h.264", "h265", "h.265", "hevc", "crf", "quality", "short side", "resize"]
        ),
        SettingsSearchItem(
            id: "export.location",
            category: .export,
            section: "Save Location",
            title: "Export Save Location",
            keywords: ["export", "trim", "folder", "directory", "save", "location", "ask"]
        ),

        // Shortcuts
        SettingsSearchItem(
            id: "shortcuts.all",
            category: .shortcuts,
            section: "Keyboard Shortcuts",
            title: "Playback, Navigation, Trim & Compare Shortcuts",
            keywords: ["shortcut", "keyboard", "key", "hotkey", "jkl", "space", "trim", "compare", "wipe", "fullscreen", "inspector", "cleanfeed", "reload"]
        ),

        // Updates
        SettingsSearchItem(
            id: "updates.check",
            category: .updates,
            section: "Update Check",
            title: "Automatic Updates & Version",
            keywords: ["update", "sparkle", "homebrew", "brew", "version", "release", "check", "download"]
        ),
    ]

    /// Returns all settings entries matching every whitespace-separated token in `query`.
    static func search(_ query: String) -> [SettingsSearchItem] {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        return allItems.filter { item in
            let haystack = (
                [item.title, item.section, item.category.title, item.category.subtitle]
                + item.keywords
            )
            .joined(separator: " ")
            .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}
