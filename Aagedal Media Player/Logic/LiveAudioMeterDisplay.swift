// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum LiveAudioMeterDisplayError: Error, Equatable {
    case invalidSampleRate
    case invalidLevel
    case discontinuousPosition
    case invalidReference
}

/// Display-only ballistics. Call with every measured peak bucket, even when the
/// UI coalesces snapshots. Pause/buffering must not advance sourceSamplePosition.
/// A nil level means unavailable; negative infinity is measured digital silence.
nonisolated struct LiveAudioPeakDisplay: Sendable {
    let sampleRate: Double
    private(set) var bar: Double?
    private(set) var marker: Double?
    private(set) var sourceSamplePosition: Int64?
    private var markerHoldUntil: Double?

    init(sampleRate: Double) throws {
        guard sampleRate.isFinite, sampleRate > 0 else {
            throw LiveAudioMeterDisplayError.invalidSampleRate
        }
        self.sampleRate = sampleRate
    }

    mutating func consume(level: Double?, sourceSamplePosition position: Int64) throws {
        guard position >= 0,
              self.sourceSamplePosition.map({ position > $0 }) ?? true else {
            throw LiveAudioMeterDisplayError.discontinuousPosition
        }
        guard level.map(Self.isValidLevel) ?? true else {
            throw LiveAudioMeterDisplayError.invalidLevel
        }
        let time = Double(position) / sampleRate
        let previousTime = self.sourceSamplePosition.map { Double($0) / sampleRate } ?? time
        self.sourceSamplePosition = position
        guard let level else {
            bar = nil
            marker = nil
            markerHoldUntil = nil
            return
        }
        bar = max(level, (bar ?? -.infinity) - 20 * (time - previousTime))
        let releaseStart = max(previousTime, markerHoldUntil ?? previousTime)
        let releasedMarker = (marker ?? -.infinity) - 20 * max(0, time - releaseStart)
        if level >= releasedMarker {
            marker = level
            markerHoldUntil = time + 2
        } else {
            marker = releasedMarker
        }
    }

    /// EOF may revise the last bucket after draining reconstruction history.
    /// That drain adds no source time: only a higher final peak changes the bar
    /// or marker, and an unchanged reading must not restart the marker hold.
    mutating func reviseFinalPeak(level: Double, sourceSamplePosition position: Int64) throws {
        guard sourceSamplePosition == position else {
            throw LiveAudioMeterDisplayError.discontinuousPosition
        }
        guard Self.isValidLevel(level) else {
            throw LiveAudioMeterDisplayError.invalidLevel
        }
        bar = max(bar ?? -.infinity, level)
        if marker.map({ level > $0 }) ?? true {
            marker = level
            markerHoldUntil = Double(position) / sampleRate + 2
        }
    }

    /// A new measurement segment starts without bars or source-time history.
    mutating func reset() {
        bar = nil
        marker = nil
        sourceSamplePosition = nil
        markerHoldUntil = nil
    }

    static func isValidLevel(_ value: Double) -> Bool {
        value.isFinite || value == -.infinity
    }
}

/// Reference guides only; these do not assess programme or dialogue compliance.
nonisolated struct LiveAudioMeterReference: Equatable, Sendable {
    enum Preset: Equatable, Sendable { case ebuProduction, atscExchange, custom }
    let preset: Preset
    let loudnessTarget: Double
    let truePeakCeiling: Double?

    static let ebuProduction = Self(preset: .ebuProduction, loudnessTarget: -23, truePeakCeiling: -1)
    static let atscExchange = Self(preset: .atscExchange, loudnessTarget: -24, truePeakCeiling: -2)

    private init(preset: Preset, loudnessTarget: Double, truePeakCeiling: Double?) {
        self.preset = preset
        self.loudnessTarget = loudnessTarget
        self.truePeakCeiling = truePeakCeiling
    }

    static func custom(loudnessTarget: Double, truePeakCeiling: Double?) throws -> Self {
        guard loudnessTarget.isFinite, truePeakCeiling.map(\.isFinite) ?? true else {
            throw LiveAudioMeterDisplayError.invalidReference
        }
        return Self(preset: .custom, loudnessTarget: loudnessTarget, truePeakCeiling: truePeakCeiling)
    }

    var loudnessUnit: String { preset == .atscExchange ? "LKFS" : "LUFS" }
    var dialogueAssessmentUnavailable: Bool { preset == .atscExchange }

    /// Uses original precision. Nil means no ceiling or no valid measurement.
    /// Custom uses a maximum ceiling, with the same strict comparison as EBU.
    func exceedsTruePeakGuide(_ truePeak: Double?) -> Bool? {
        guard let truePeak, LiveAudioPeakDisplay.isValidLevel(truePeak),
              let ceiling = truePeakCeiling else { return nil }
        return preset == .atscExchange ? truePeak >= ceiling : truePeak > ceiling
    }
}

/// Independent numeric maxima for the current continuous segment. M/S have no
/// display attack/release. Feed aggregate channel peak maxima without summing.
nonisolated struct LiveAudioMeterMaxima: Sendable {
    private(set) var samplePeak: Double?
    private(set) var truePeak: Double?
    private(set) var momentary: Double?
    private(set) var shortTerm: Double?
    private(set) var truePeakGuideExceeded = false
    private(set) var reference: LiveAudioMeterReference

    init(reference: LiveAudioMeterReference = .ebuProduction) {
        self.reference = reference
    }

    mutating func consume(samplePeak: Double?, truePeak: Double?, momentary: Double?, shortTerm: Double?) throws {
        guard [samplePeak, truePeak, momentary, shortTerm].allSatisfy({
            $0.map(LiveAudioPeakDisplay.isValidLevel) ?? true
        }) else { throw LiveAudioMeterDisplayError.invalidLevel }
        self.samplePeak = Self.maximum(self.samplePeak, samplePeak)
        self.truePeak = Self.maximum(self.truePeak, truePeak)
        self.momentary = Self.maximum(self.momentary, momentary)
        self.shortTerm = Self.maximum(self.shortTerm, shortTerm)
        truePeakGuideExceeded = reference.exceedsTruePeakGuide(self.truePeak) == true
    }

    mutating func setReference(_ reference: LiveAudioMeterReference) {
        self.reference = reference
        truePeakGuideExceeded = reference.exceedsTruePeakGuide(truePeak) == true
    }

    /// Does not touch DSP filters/windows or the independent peak display.
    mutating func clearMaxima() {
        samplePeak = nil
        truePeak = nil
        momentary = nil
        shortTerm = nil
        truePeakGuideExceeded = false
    }

    private static func maximum(_ previous: Double?, _ next: Double?) -> Double? {
        guard let next else { return previous }
        return max(previous ?? -.infinity, next)
    }
}
