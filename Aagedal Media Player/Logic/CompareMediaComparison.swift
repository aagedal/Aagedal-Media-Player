// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum CompareMismatchKind: String, CaseIterable, Sendable {
    case frameRate
    case duration
    case transferFunction
    case colorPrimaries
    case colorRange

    var label: String {
        switch self {
        case .frameRate: "Frame rate"
        case .duration: "Duration"
        case .transferFunction: "Transfer function"
        case .colorPrimaries: "Color primaries"
        case .colorRange: "Range"
        }
    }
}

nonisolated struct CompareMismatch: Identifiable, Equatable, Sendable {
    let kind: CompareMismatchKind
    let primaryValue: String
    let secondaryValue: String

    var id: CompareMismatchKind { kind }
}

/// The technical properties that affect paired playback or how two displayed
/// images should be interpreted. Unknown values intentionally remain nil; the
/// report can then distinguish two untagged sources from a one-sided gap.
nonisolated struct CompareMediaDescriptor: Equatable, Sendable {
    let duration: TimeInterval?
    let frameRate: Double?
    let transferFunction: String?
    let colorPrimaries: String?
    let colorRange: String?

    init(
        duration: TimeInterval?,
        frameRate: Double?,
        transferFunction: String?,
        colorPrimaries: String?,
        colorRange: String?
    ) {
        self.duration = Self.positiveFinite(duration)
        self.frameRate = Self.positiveFinite(frameRate)
        self.transferFunction = transferFunction
        self.colorPrimaries = colorPrimaries
        self.colorRange = colorRange
    }

    init(item: MediaItem) {
        let stream = item.metadata?.videoStreams.first
        self.init(
            duration: item.durationSeconds,
            frameRate: stream?.frameRate?.value,
            transferFunction: stream?.colorTransfer,
            colorPrimaries: stream?.colorPrimaries,
            colorRange: stream?.colorRange
        )
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

nonisolated enum CompareMediaComparison {
    static func mismatches(
        primary: CompareMediaDescriptor,
        secondary: CompareMediaDescriptor
    ) -> [CompareMismatch] {
        var result: [CompareMismatch] = []

        appendNumericMismatch(
            kind: .frameRate,
            primaryValue: primary.frameRate,
            secondaryValue: secondary.frameRate,
            tolerance: 0.001,
            formatter: frameRateLabel,
            to: &result
        )
        appendNumericMismatch(
            kind: .duration,
            primaryValue: primary.duration,
            secondaryValue: secondary.duration,
            tolerance: durationTolerance(primary: primary, secondary: secondary),
            formatter: durationLabel,
            to: &result
        )

        appendStringMismatch(
            kind: .transferFunction,
            primaryValue: primary.transferFunction,
            secondaryValue: secondary.transferFunction,
            normalizer: normalizedTransferFunction,
            to: &result
        )
        appendStringMismatch(
            kind: .colorPrimaries,
            primaryValue: primary.colorPrimaries,
            secondaryValue: secondary.colorPrimaries,
            normalizer: normalizedColorPrimaries,
            to: &result
        )
        appendStringMismatch(
            kind: .colorRange,
            primaryValue: primary.colorRange,
            secondaryValue: secondary.colorRange,
            normalizer: normalizedColorRange,
            to: &result
        )

        return result
    }

    static func mismatches(primary: MediaItem, secondary: MediaItem) -> [CompareMismatch] {
        mismatches(
            primary: CompareMediaDescriptor(item: primary),
            secondary: CompareMediaDescriptor(item: secondary)
        )
    }

    private static func appendNumericMismatch(
        kind: CompareMismatchKind,
        primaryValue: Double?,
        secondaryValue: Double?,
        tolerance: Double,
        formatter: (Double) -> String,
        to result: inout [CompareMismatch]
    ) {
        if let primaryValue, let secondaryValue,
           abs(primaryValue - secondaryValue) <= tolerance {
            return
        }
        guard primaryValue != nil || secondaryValue != nil else { return }

        result.append(CompareMismatch(
            kind: kind,
            primaryValue: primaryValue.map(formatter) ?? "Unavailable",
            secondaryValue: secondaryValue.map(formatter) ?? "Unavailable"
        ))
    }

    private static func appendStringMismatch(
        kind: CompareMismatchKind,
        primaryValue: String?,
        secondaryValue: String?,
        normalizer: (String) -> String,
        to result: inout [CompareMismatch]
    ) {
        let normalizedPrimary = cleaned(primaryValue).map(normalizer)
        let normalizedSecondary = cleaned(secondaryValue).map(normalizer)
        guard normalizedPrimary != normalizedSecondary else { return }

        result.append(CompareMismatch(
            kind: kind,
            primaryValue: normalizedPrimary.map { displayLabel($0, kind: kind) } ?? "Unavailable",
            secondaryValue: normalizedSecondary.map { displayLabel($0, kind: kind) } ?? "Unavailable"
        ))
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compact = compactIdentifier(cleaned)
        guard !cleaned.isEmpty,
              !["unknown", "unspecified", "na", "none", "notavailable"].contains(compact) else {
            return nil
        }
        return cleaned
    }

    private static func normalizedTransferFunction(_ value: String) -> String {
        let compact = compactIdentifier(value)
        if compact == "pq" || compact.contains("smpte2084") || compact.contains("st2084") {
            return "pq"
        }
        if compact == "hlg" || compact.contains("aribstdb67") {
            return "hlg"
        }
        return compact
    }

    private static func normalizedColorPrimaries(_ value: String) -> String {
        switch compactIdentifier(value) {
        case "bt202010", "bt202012": "bt2020"
        default: compactIdentifier(value)
        }
    }

    private static func normalizedColorRange(_ value: String) -> String {
        switch compactIdentifier(value) {
        case "pc", "jpeg", "full": "full"
        case "tv", "mpeg", "limited": "limited"
        default: compactIdentifier(value)
        }
    }

    private static func compactIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func displayLabel(_ value: String, kind: CompareMismatchKind) -> String {
        switch (kind, value) {
        case (.transferFunction, "pq"): "PQ (ST 2084)"
        case (.transferFunction, "hlg"): "HLG"
        case (.colorPrimaries, "bt709"): "BT.709"
        case (.colorPrimaries, "bt2020"): "BT.2020"
        case (.colorRange, "full"): "Full"
        case (.colorRange, "limited"): "Limited"
        default: value.uppercased()
        }
    }

    private static func frameRateLabel(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.0005 {
            return "\(Int(value.rounded())) fps"
        }
        return "\(trimmedDecimal(value, fractionDigits: 3)) fps"
    }

    private static func durationTolerance(
        primary: CompareMediaDescriptor,
        secondary: CompareMediaDescriptor
    ) -> TimeInterval {
        let frameDurations = [primary.frameRate, secondary.frameRate]
            .compactMap { $0 }
            .map { 1 / $0 }
        // Ignore timestamp rounding below one quarter of the shortest known
        // frame, while still reporting a one-frame duration difference.
        return max(0.002, (frameDurations.min() ?? 0.04) * 0.25)
    }

    private static func durationLabel(_ value: TimeInterval) -> String {
        let totalMilliseconds = Int((value * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let seconds = (totalMilliseconds / 1_000) % 60
        let milliseconds = totalMilliseconds % 1_000
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        }
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }

    private static func trimmedDecimal(_ value: Double, fractionDigits: Int) -> String {
        var label = String(format: "%.*f", fractionDigits, value)
        while label.last == "0" { label.removeLast() }
        if label.last == "." { label.removeLast() }
        return label
    }
}
