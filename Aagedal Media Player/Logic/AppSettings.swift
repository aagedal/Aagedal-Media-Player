// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A persisted preference with one stable storage key and one canonical default.
///
/// Keeping the value type on the descriptor prevents callers from accidentally
/// reading a numeric preference as a string (or vice versa), while the existing
/// key names preserve preferences written by earlier app versions.
nonisolated struct AppSetting<Value: Sendable>: Sendable {
    let key: String
    let defaultValue: Value
}

nonisolated enum AppSettings {
    // Windows and playback
    static let allowMultipleWindows = AppSetting(key: "allowMultipleWindows", defaultValue: false)
    static let syncPlaybackControls = AppSetting(key: "syncPlaybackControls", defaultValue: false)
    static let showCursorHideHint = AppSetting(key: "showCursorHideHint", defaultValue: true)
    static let didShowCompareModeCallout = AppSetting(
        key: "didShowCompareModeCallout",
        defaultValue: false
    )
    static let precisionScrubFactor = AppSetting(key: "precisionScrubFactor", defaultValue: 10.0)
    static let openAtSourceResolution = AppSetting(key: "openAtSourceResolution", defaultValue: true)
    static let clampWindowToScreen = AppSetting(key: "clampWindowToScreen", defaultValue: true)
    static let centerWindowAfterResize = AppSetting(key: "centerWindowAfterResize", defaultValue: true)
    static let playbackVolume = AppSetting(key: "playbackVolume", defaultValue: 100.0)
    static let playbackMuted = AppSetting(key: "playbackMuted", defaultValue: false)

    // Screenshots and trim exports
    static let screenshotLocationMode = AppSetting(key: "screenshotLocationMode", defaultValue: "custom")
    static let screenshotFormat = AppSetting(key: "screenshotFormat", defaultValue: "jxl")
    static let screenshotSaveDirectory = AppSetting<Data?>(key: "screenshotSaveDirectory", defaultValue: nil)
    static let trimLocationMode = AppSetting(key: "trimLocationMode", defaultValue: "ask")
    static let trimSaveDirectory = AppSetting<Data?>(key: "trimSaveDirectory", defaultValue: nil)
    static let trimExportFormat = AppSetting(key: "trimExportFormat", defaultValue: "copy")
    static let screenshotJXLQuality = AppSetting(key: "screenshotJXLQuality", defaultValue: 90.0)
    static let screenshotJPEGQuality = AppSetting(key: "screenshotJPEGQuality", defaultValue: 90.0)
    static let gifFrameRate = AppSetting(key: "gifFrameRate", defaultValue: 15.0)
    static let gifWidth = AppSetting(key: "gifWidth", defaultValue: 720)
    static let avifWidth = AppSetting(key: "avifWidth", defaultValue: 1080)
    static let h264Width = AppSetting(key: "h264Width", defaultValue: 0)
    static let h265Width = AppSetting(key: "h265Width", defaultValue: 0)
    static let avifQuality = AppSetting(key: "avifQuality", defaultValue: 28.0)
    static let avifSpeed = AppSetting(key: "avifSpeed", defaultValue: 4.0)
    static let h264Quality = AppSetting(key: "h264Quality", defaultValue: 65.0)
    static let h265Quality = AppSetting(key: "h265Quality", defaultValue: 65.0)

    // Video scopes
    static let scopeDisplayMode = AppSetting(key: "scopeDisplayMode", defaultValue: "overlay")
    static let scopeBackground = AppSetting(key: "scopeBackground", defaultValue: "transparent")
    static let scopeResolution = AppSetting(key: "scopeResolution", defaultValue: 720)
    static let scopeFrameRate = AppSetting(key: "scopeFrameRate", defaultValue: 15.0)

    // Audio waveform
    static let audioWaveformDisplayMode = AppSetting(key: "audioWaveformDisplayMode", defaultValue: "overlay")
    static let audioWaveformBackground = AppSetting(key: "audioWaveformBackground", defaultValue: "transparent")
    static let audioWaveformColor = AppSetting(key: "audioWaveformColor", defaultValue: "FF2D78")
    static let showAllMonoWaveforms = AppSetting(key: "showAllMonoWaveforms", defaultValue: false)
    static let audioWaveformBoost = AppSetting(key: "audioWaveformBoost", defaultValue: 0.0)
    static let automaticAudioOnlyWaveform = AppSetting(key: "automaticAudioOnlyWaveform", defaultValue: true)

    // Update checker
    static let updateLastChecked = AppSetting<Date?>(key: "updateLastChecked", defaultValue: nil)
    static let updateCheckInterval = AppSetting(key: "updateCheckInterval", defaultValue: 7.0 * 24 * 3_600)
    static let didShowAutoUpdateNotice = AppSetting(key: "didShowAutoUpdateNotice", defaultValue: false)

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            allowMultipleWindows.key: allowMultipleWindows.defaultValue,
            syncPlaybackControls.key: syncPlaybackControls.defaultValue,
            showCursorHideHint.key: showCursorHideHint.defaultValue,
            didShowCompareModeCallout.key: didShowCompareModeCallout.defaultValue,
            precisionScrubFactor.key: precisionScrubFactor.defaultValue,
            openAtSourceResolution.key: openAtSourceResolution.defaultValue,
            clampWindowToScreen.key: clampWindowToScreen.defaultValue,
            centerWindowAfterResize.key: centerWindowAfterResize.defaultValue,
            playbackVolume.key: playbackVolume.defaultValue,
            playbackMuted.key: playbackMuted.defaultValue,
            screenshotLocationMode.key: screenshotLocationMode.defaultValue,
            screenshotFormat.key: screenshotFormat.defaultValue,
            trimLocationMode.key: trimLocationMode.defaultValue,
            trimExportFormat.key: trimExportFormat.defaultValue,
            screenshotJXLQuality.key: screenshotJXLQuality.defaultValue,
            screenshotJPEGQuality.key: screenshotJPEGQuality.defaultValue,
            gifFrameRate.key: gifFrameRate.defaultValue,
            gifWidth.key: gifWidth.defaultValue,
            avifWidth.key: avifWidth.defaultValue,
            h264Width.key: h264Width.defaultValue,
            h265Width.key: h265Width.defaultValue,
            avifQuality.key: avifQuality.defaultValue,
            avifSpeed.key: avifSpeed.defaultValue,
            h264Quality.key: h264Quality.defaultValue,
            h265Quality.key: h265Quality.defaultValue,
            scopeDisplayMode.key: scopeDisplayMode.defaultValue,
            scopeBackground.key: scopeBackground.defaultValue,
            scopeResolution.key: scopeResolution.defaultValue,
            scopeFrameRate.key: scopeFrameRate.defaultValue,
            audioWaveformDisplayMode.key: audioWaveformDisplayMode.defaultValue,
            audioWaveformBackground.key: audioWaveformBackground.defaultValue,
            audioWaveformColor.key: audioWaveformColor.defaultValue,
            showAllMonoWaveforms.key: showAllMonoWaveforms.defaultValue,
            audioWaveformBoost.key: audioWaveformBoost.defaultValue,
            automaticAudioOnlyWaveform.key: automaticAudioOnlyWaveform.defaultValue,
            updateCheckInterval.key: updateCheckInterval.defaultValue,
            didShowAutoUpdateNotice.key: didShowAutoUpdateNotice.defaultValue,
        ])
    }
}

extension UserDefaults {
    func value<Value: Sendable>(for setting: AppSetting<Value>) -> Value {
        object(forKey: setting.key) as? Value ?? setting.defaultValue
    }

    func set<Value: Sendable>(_ value: Value, for setting: AppSetting<Value>) {
        set(value, forKey: setting.key)
    }
}
