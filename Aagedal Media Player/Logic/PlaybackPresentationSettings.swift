// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// mpv `deinterlace` modes. `auto` only filters frames flagged as interlaced.
nonisolated enum DeinterlaceMode: String, CaseIterable, Sendable {
    case auto, on, off

    var label: String {
        switch self {
        case .auto: "Automatic"
        case .on: "Always"
        case .off: "Off"
        }
    }

    var mpvValue: String {
        switch self {
        case .auto: "auto"
        case .on: "yes"
        case .off: "no"
        }
    }
}

/// On-screen picture adjustments applied by mpv's renderer. Source files,
/// FFmpeg screenshots and exports are unaffected.
nonisolated struct VideoPictureAdjustments: Equatable, Sendable {
    nonisolated enum Kind: String, CaseIterable, Sendable {
        case brightness, contrast, saturation, gamma, hue

        var label: String { rawValue.capitalized }
        /// mpv property names match the case names.
        var mpvProperty: String { rawValue }
    }

    static let range: ClosedRange<Double> = -100...100

    private var values: [Kind: Double] = [:]

    subscript(kind: Kind) -> Double {
        get { values[kind] ?? 0 }
        set {
            guard newValue.isFinite else { return }
            let clamped = min(Self.range.upperBound, max(Self.range.lowerBound, newValue)).rounded()
            values[kind] = clamped == 0 ? nil : clamped
        }
    }

    var isNeutral: Bool { values.isEmpty }
}

/// Subtitle timing and placement. Positive delays show subtitles later.
nonisolated struct SubtitlePresentation: Equatable, Sendable {
    static let delayRangeMilliseconds: ClosedRange<Double> = -10_000...10_000
    static let scaleRange: ClosedRange<Double> = 0.5...3
    /// mpv `sub-pos`: 0 is the top of the video, 100 the bottom edge.
    static let positionRange: ClosedRange<Double> = 0...150

    var delayMilliseconds: Double = 0 {
        didSet { delayMilliseconds = Self.clamp(delayMilliseconds, Self.delayRangeMilliseconds, fallback: oldValue).rounded() }
    }
    var scale: Double = 1 {
        didSet { scale = Self.clamp(scale, Self.scaleRange, fallback: oldValue) }
    }
    var position: Double = 100 {
        didSet { position = Self.clamp(position, Self.positionRange, fallback: oldValue).rounded() }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
