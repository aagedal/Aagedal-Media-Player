// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum CompareMismatchKind: String, CaseIterable, Sendable {
    case videoCodec
    case raster
    case frameRate
    case transferFunction
    case colorPrimaries
    case colorRange
    case audioLayout
    case duration

    var label: String {
        switch self {
        case .videoCodec: "Video codec"
        case .raster: "Coded raster"
        case .frameRate: "Frame rate"
        case .transferFunction: "Transfer function"
        case .colorPrimaries: "Color primaries"
        case .colorRange: "Range"
        case .audioLayout: "Audio layout"
        case .duration: "Duration"
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
    let videoCodec: String?
    let rasterWidth: Int?
    let rasterHeight: Int?
    let duration: TimeInterval?
    let frameRate: Double?
    let transferFunction: String?
    let colorPrimaries: String?
    let colorRange: String?
    let audioLayout: String?

    init(
        videoCodec: String? = nil,
        rasterWidth: Int? = nil,
        rasterHeight: Int? = nil,
        duration: TimeInterval?,
        frameRate: Double?,
        transferFunction: String?,
        colorPrimaries: String?,
        colorRange: String?,
        audioLayout: String? = nil
    ) {
        self.videoCodec = videoCodec
        self.rasterWidth = Self.positive(rasterWidth)
        self.rasterHeight = Self.positive(rasterHeight)
        self.duration = Self.positiveFinite(duration)
        self.frameRate = Self.positiveFinite(frameRate)
        self.transferFunction = transferFunction
        self.colorPrimaries = colorPrimaries
        self.colorRange = colorRange
        self.audioLayout = audioLayout
    }

    init(item: MediaItem) {
        let stream = item.metadata?.videoStreams.first
        self.init(
            videoCodec: stream?.codec ?? stream?.codecLongName,
            rasterWidth: stream?.width,
            rasterHeight: stream?.height,
            duration: item.durationSeconds,
            frameRate: stream?.frameRate?.value,
            transferFunction: stream?.colorTransfer,
            colorPrimaries: stream?.colorPrimaries,
            colorRange: stream?.colorRange,
            audioLayout: Self.audioLayoutLabel(metadata: item.metadata)
        )
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func audioLayoutLabel(metadata: MediaMetadata?) -> String? {
        guard let metadata else { return nil }
        guard !metadata.audioStreams.isEmpty else { return "No audio" }

        return metadata.audioStreams.map { stream in
            if let layout = stream.channelLayout?.trimmingCharacters(in: .whitespacesAndNewlines),
               !layout.isEmpty {
                return layout
            }
            guard let channels = stream.channels, channels > 0 else { return "Unknown" }
            switch channels {
            case 1: return "Mono"
            case 2: return "Stereo"
            default: return "\(channels) channels"
            }
        }.joined(separator: " + ")
    }
}

nonisolated enum CompareMediaComparison {
    static func mismatches(
        primary: CompareMediaDescriptor,
        secondary: CompareMediaDescriptor
    ) -> [CompareMismatch] {
        var result: [CompareMismatch] = []

        appendStringMismatch(
            kind: .videoCodec,
            primaryValue: primary.videoCodec,
            secondaryValue: secondary.videoCodec,
            normalizer: normalizedVideoCodec,
            to: &result
        )
        appendRasterMismatch(primary: primary, secondary: secondary, to: &result)
        appendNumericMismatch(
            kind: .frameRate,
            primaryValue: primary.frameRate,
            secondaryValue: secondary.frameRate,
            tolerance: 0.001,
            formatter: frameRateLabel,
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
        appendStringMismatch(
            kind: .audioLayout,
            primaryValue: primary.audioLayout,
            secondaryValue: secondary.audioLayout,
            normalizer: normalizedAudioLayout,
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

    private static func appendRasterMismatch(
        primary: CompareMediaDescriptor,
        secondary: CompareMediaDescriptor,
        to result: inout [CompareMismatch]
    ) {
        let primaryRaster = rasterLabel(width: primary.rasterWidth, height: primary.rasterHeight)
        let secondaryRaster = rasterLabel(width: secondary.rasterWidth, height: secondary.rasterHeight)
        guard primaryRaster != secondaryRaster,
              primaryRaster != nil || secondaryRaster != nil else { return }

        result.append(CompareMismatch(
            kind: .raster,
            primaryValue: primaryRaster ?? "Unavailable",
            secondaryValue: secondaryRaster ?? "Unavailable"
        ))
    }

    private static func appendStringMismatch(
        kind: CompareMismatchKind,
        primaryValue: String?,
        secondaryValue: String?,
        normalizer: (String) -> String,
        to result: inout [CompareMismatch]
    ) {
        let cleanedPrimary = cleaned(primaryValue)
        let cleanedSecondary = cleaned(secondaryValue)
        let normalizedPrimary = cleanedPrimary.map(normalizer)
        let normalizedSecondary = cleanedSecondary.map(normalizer)
        guard normalizedPrimary != normalizedSecondary else { return }

        result.append(CompareMismatch(
            kind: kind,
            primaryValue: displayLabel(
                normalized: normalizedPrimary,
                original: cleanedPrimary,
                kind: kind
            ),
            secondaryValue: displayLabel(
                normalized: normalizedSecondary,
                original: cleanedSecondary,
                kind: kind
            )
        ))
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func normalizedVideoCodec(_ value: String) -> String {
        let compact = compactIdentifier(value)
        if compact == "h264" || compact == "avc" || compact == "avc1"
            || compact.hasPrefix("h264")
            || compact.contains("advancedvideocoding") {
            return "h264"
        }
        if compact == "h265" || compact == "hevc" || compact == "hev1" || compact == "hvc1"
            || compact.hasPrefix("h265") || compact.hasPrefix("hevc")
            || compact.contains("highefficiencyvideocoding") {
            return "hevc"
        }
        if compact == "av1" || compact.contains("aomediaav1") {
            return "av1"
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

    private static func normalizedAudioLayout(_ value: String) -> String {
        let compact = compactIdentifier(value)
        return switch compact {
        case "1", "10", "1channel", "mono": "mono"
        case "2", "20", "2channels", "stereo": "stereo"
        case "noaudio": "none"
        default: compact
        }
    }

    private static func compactIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func displayLabel(
        normalized value: String?,
        original: String?,
        kind: CompareMismatchKind
    ) -> String {
        guard let value else { return "Unavailable" }
        return switch (kind, value) {
        case (.videoCodec, "h264"): "H.264"
        case (.videoCodec, "hevc"): "HEVC"
        case (.videoCodec, "av1"): "AV1"
        case (.videoCodec, _): original ?? value.uppercased()
        case (.transferFunction, "pq"): "PQ (ST 2084)"
        case (.transferFunction, "hlg"): "HLG"
        case (.colorPrimaries, "bt709"): "BT.709"
        case (.colorPrimaries, "bt2020"): "BT.2020"
        case (.colorRange, "full"): "Full"
        case (.colorRange, "limited"): "Limited"
        case (.audioLayout, "mono"): "Mono"
        case (.audioLayout, "stereo"): "Stereo"
        case (.audioLayout, "none"): "No audio"
        case (.audioLayout, _): original ?? value.uppercased()
        default: value.uppercased()
        }
    }

    private static func rasterLabel(width: Int?, height: Int?) -> String? {
        guard let width, let height else { return nil }
        return "\(width) × \(height)"
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
