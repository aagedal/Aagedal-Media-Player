// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persisted reference-guide choices. Loading rejects non-finite legacy or
/// externally-written values so they cannot reach threshold comparisons.
nonisolated struct LiveAudioMeterPreferences: Equatable, Sendable {
    var preset: LiveAudioMeterReference.Preset
    var customLoudnessTarget: Double
    var customTruePeakCeiling: Double?

    static let defaults = Self(
        preset: .ebuProduction,
        customLoudnessTarget: AppSettings.liveAudioMeterCustomLoudnessTarget.defaultValue,
        customTruePeakCeiling: AppSettings.liveAudioMeterCustomTruePeakCeiling.defaultValue
    )

    init(
        preset: LiveAudioMeterReference.Preset = .ebuProduction,
        customLoudnessTarget: Double = AppSettings.liveAudioMeterCustomLoudnessTarget.defaultValue,
        customTruePeakCeiling: Double? = AppSettings.liveAudioMeterCustomTruePeakCeiling.defaultValue
    ) {
        self.preset = preset
        self.customLoudnessTarget = customLoudnessTarget.isFinite
            ? customLoudnessTarget
            : Self.defaults.customLoudnessTarget
        self.customTruePeakCeiling = customTruePeakCeiling?.isFinite == true
            ? customTruePeakCeiling
            : nil
    }

    init(defaults: UserDefaults) {
        let presetRaw = defaults.value(for: AppSettings.liveAudioMeterPreset)
        let target = defaults.value(for: AppSettings.liveAudioMeterCustomLoudnessTarget)
        let ceiling = defaults.object(forKey: AppSettings.liveAudioMeterCustomTruePeakCeiling.key) as? Double
        self.init(
            preset: LiveAudioMeterReference.Preset(rawValue: presetRaw) ?? .ebuProduction,
            customLoudnessTarget: target,
            customTruePeakCeiling: ceiling
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(preset.rawValue, for: AppSettings.liveAudioMeterPreset)
        defaults.set(customLoudnessTarget, for: AppSettings.liveAudioMeterCustomLoudnessTarget)
        if let customTruePeakCeiling {
            defaults.set(customTruePeakCeiling, for: AppSettings.liveAudioMeterCustomTruePeakCeiling)
        } else {
            defaults.removeObject(forKey: AppSettings.liveAudioMeterCustomTruePeakCeiling.key)
        }
    }

    var reference: LiveAudioMeterReference {
        switch preset {
        case .ebuProduction: .ebuProduction
        case .atscExchange: .atscExchange
        case .custom:
            // The initializer above keeps these finite. Preserve a safe
            // canonical fallback if the reference validator is tightened.
            (try? .custom(
                loudnessTarget: customLoudnessTarget,
                truePeakCeiling: customTruePeakCeiling
            )) ?? .ebuProduction
        }
    }
}

nonisolated enum LiveAudioMeterPresentationStatus: Equatable, Sendable {
    case unavailable(reason: String, diagnostic: String?)
    case warmingUp(position: String, momentaryReady: Bool, shortTermReady: Bool)
    case active(position: String)
    case paused(position: String)
    case buffering(position: String)
    case ended(position: String)

    var title: String {
        switch self {
        case .unavailable: "Unavailable"
        case .warmingUp: "Warming up"
        case .active: "Active"
        case .paused: "Paused"
        case .buffering: "Buffering"
        case .ended: "Ended"
        }
    }

    var position: String? {
        switch self {
        case .unavailable: nil
        case .warmingUp(let position, _, _), .active(let position), .paused(let position),
             .buffering(let position), .ended(let position): position
        }
    }
}

nonisolated struct LiveAudioMeterSourceOption: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let detail: String?

    init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

nonisolated struct LiveAudioMeterLevelState: Equatable, Sendable {
    /// Current measured bucket, display-decayed bar, held marker, and segment
    /// maximum. Nil is unavailable; negative infinity is measured silence.
    let current: Double?
    let bar: Double?
    let marker: Double?
    let maximum: Double?

    init(current: Double?, bar: Double?, marker: Double?, maximum: Double?) {
        self.current = current
        self.bar = bar
        self.marker = marker
        self.maximum = maximum
    }
}

nonisolated struct LiveAudioMeterChannelState: Identifiable, Equatable, Sendable {
    let id: Int
    let label: String
    let samplePeak: LiveAudioMeterLevelState
    let truePeak: LiveAudioMeterLevelState
}

nonisolated struct LiveAudioMeterLoudnessState: Equatable, Sendable {
    let momentary: Double?
    let maximumMomentary: Double?
    let shortTerm: Double?
    let maximumShortTerm: Double?
}

/// Provenance required to interpret a source-PCM reading. This deliberately
/// describes the measured source, not the audible monitor path.
nonisolated struct LiveAudioMeterProvenance: Equatable, Sendable {
    let sourceIdentity: String
    let streamIndex: Int
    let trackLabel: String
    let decoder: String
    let decoderVersion: String
    let sampleRate: Int
    let channelLayout: String
    let channelMap: [String]
    let algorithm: String
    let measurementGeneration: UInt64
    let sourceInterval: String
    let segmentStart: String
}

nonisolated struct LiveAudioMeterDiagnostic: Identifiable, Equatable, Sendable {
    enum Severity: Equatable, Sendable { case information, qualification, failure }

    let id: String
    let label: String
    let detail: String
    let severity: Severity

    init(id: String, label: String, detail: String, severity: Severity = .information) {
        self.id = id
        self.label = label
        self.detail = detail
        self.severity = severity
    }
}

nonisolated enum LiveAudioMeterThresholdComparison: String, Equatable, Sendable {
    case greaterThan = ">"
    case greaterThanOrEqual = "≥"
}

nonisolated enum LiveAudioMeterTruePeakAssessment: Equatable, Sendable {
    case noCeiling
    case unavailable(ceiling: Double, comparison: LiveAudioMeterThresholdComparison)
    case withinGuide(maximum: Double, ceiling: Double, comparison: LiveAudioMeterThresholdComparison)
    case exceeded(maximum: Double, ceiling: Double, comparison: LiveAudioMeterThresholdComparison)

    var isExceeded: Bool { if case .exceeded = self { true } else { false } }

    /// User-facing wording includes the exact preset boundary operator; colour
    /// is never the only indication. Values display at one decimal as required.
    var text: String {
        switch self {
        case .noCeiling:
            "No true-peak ceiling set."
        case .unavailable(let ceiling, let comparison):
            "True-peak guide: \(comparison.rawValue) \(Self.level(ceiling)) dBTP; maximum unavailable."
        case .withinGuide(let maximum, let ceiling, let comparison):
            "No true-peak guide exceedance: \(Self.level(maximum)) dBTP does not meet \(comparison.rawValue) \(Self.level(ceiling)) dBTP."
        case .exceeded(let maximum, let ceiling, let comparison):
            "True-peak guide exceeded: \(Self.level(maximum)) dBTP meets \(comparison.rawValue) \(Self.level(ceiling)) dBTP."
        }
    }

    /// Full stored precision for copied or expanded diagnostics.
    var diagnosticText: String {
        switch self {
        case .noCeiling: "comparison=none"
        case .unavailable(let ceiling, let comparison):
            "maximum=unavailable; comparison=\(comparison.rawValue); ceiling=\(Self.precise(ceiling)) dBTP"
        case .withinGuide(let maximum, let ceiling, let comparison),
             .exceeded(let maximum, let ceiling, let comparison):
            "maximum=\(Self.precise(maximum)) dBTP; comparison=\(comparison.rawValue); ceiling=\(Self.precise(ceiling)) dBTP"
        }
    }

    private static func level(_ value: Double) -> String {
        value == -.infinity ? "−∞" : String(format: "%.1f", value).replacingOccurrences(of: "-", with: "−")
    }

    private static func precise(_ value: Double) -> String {
        value == -.infinity ? "-inf" : String(format: "%.17g", value)
    }
}

nonisolated struct LiveAudioMeterViewState: Equatable, Sendable {
    let status: LiveAudioMeterPresentationStatus
    let sourceOptions: [LiveAudioMeterSourceOption]
    let selectedSourceID: String
    let measuredSourceLabel: String
    let channels: [LiveAudioMeterChannelState]
    let loudness: LiveAudioMeterLoudnessState
    let reference: LiveAudioMeterReference
    let provenance: LiveAudioMeterProvenance?
    let diagnostics: [LiveAudioMeterDiagnostic]

    var truePeakAssessment: LiveAudioMeterTruePeakAssessment {
        guard let ceiling = reference.truePeakCeiling else { return .noCeiling }
        let comparison: LiveAudioMeterThresholdComparison = reference.preset == .atscExchange
            ? .greaterThanOrEqual
            : .greaterThan
        let maximum = channels.compactMap(\.truePeak.maximum).max()
        guard let maximum else { return .unavailable(ceiling: ceiling, comparison: comparison) }
        return reference.exceedsTruePeakGuide(maximum) == true
            ? .exceeded(maximum: maximum, ceiling: ceiling, comparison: comparison)
            : .withinGuide(maximum: maximum, ceiling: ceiling, comparison: comparison)
    }
}
