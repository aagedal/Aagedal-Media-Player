// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Rational SMPTE timecode formatting and parsing.

import Foundation

enum TimecodeDisplayMode: String, CaseIterable {
    case relative = "relative"
    case source = "source"
    case frames = "frames"

    var prefix: String {
        switch self {
        case .relative: return "REL TC"
        case .source: return "SRC TC"
        case .frames: return "FRM"
        }
    }

    var displayName: String {
        switch self {
        case .relative: return "Relative Timecode (REL TC)"
        case .source: return "Source Timecode (SRC TC)"
        case .frames: return "Frame Count (FRM)"
        }
    }

    mutating func toggle(hasSourceTimecode: Bool) {
        switch self {
        case .relative: self = hasSourceTimecode ? .source : .frames
        case .source: self = .frames
        case .frames: self = .relative
        }
    }
}

/// A media rate and its SMPTE label rules. Counts are real frames; the nominal
/// rate is used only for the HH:MM:SS:FF label fields.
struct TimecodeRate: Equatable, Sendable {
    let numerator: Int64
    let denominator: Int64
    let nominalFPS: Int64
    let isDropFrame: Bool

    init(numerator: Int, denominator: Int, dropFrame: Bool = false) {
        let safeNumerator = max(Int64(numerator), 1)
        let safeDenominator = max(Int64(denominator), 1)
        let divisor = Self.greatestCommonDivisor(safeNumerator, safeDenominator)

        self.numerator = safeNumerator / divisor
        self.denominator = safeDenominator / divisor
        self.nominalFPS = max(Int64((Double(safeNumerator) / Double(safeDenominator)).rounded()), 1)
        self.isDropFrame = dropFrame && Self.isDropFrameCompatible(
            numerator: safeNumerator,
            denominator: safeDenominator,
            nominalFPS: nominalFPS
        )
    }

    init(frameRate: Double, dropFrame: Bool = false) {
        let safeRate = frameRate.isFinite && frameRate > 0 ? frameRate : 30
        let broadcastRates = [(24_000, 1_001), (30_000, 1_001), (48_000, 1_001), (60_000, 1_001), (120_000, 1_001)]

        if let rate = broadcastRates.first(where: {
            abs(safeRate - (Double($0.0) / Double($0.1))) < 0.001
        }) {
            self.init(numerator: rate.0, denominator: rate.1, dropFrame: dropFrame)
        } else if abs(safeRate - safeRate.rounded()) < 0.000_001 {
            self.init(numerator: Int(safeRate.rounded()), denominator: 1, dropFrame: dropFrame)
        } else {
            self.init(
                numerator: Int((safeRate * 1_000_000).rounded()),
                denominator: 1_000_000,
                dropFrame: dropFrame
            )
        }
    }

    var value: Double {
        Double(numerator) / Double(denominator)
    }

    var droppedFramesPerMinute: Int64 {
        guard isDropFrame else { return 0 }
        return nominalFPS / 15
    }

    func frameCount(forSeconds seconds: Double) -> Int64? {
        guard seconds.isFinite else { return nil }
        let frames = seconds * Double(numerator) / Double(denominator)
        guard frames >= Double(Int64.min), frames <= Double(Int64.max) else { return nil }
        return Int64(frames.rounded())
    }

    func seconds(forFrameCount frames: Int64) -> Double {
        Double(frames) * Double(denominator) / Double(numerator)
    }

    func timecode(forFrameCount frames: Int64) -> String {
        let labelFrames: Int64

        if isDropFrame {
            let dropped = droppedFramesPerMinute
            let framesPerMinute = nominalFPS * 60 - dropped
            let framesPerTenMinutes = nominalFPS * 600 - dropped * 9
            let framesPer24Hours = framesPerTenMinutes * 6 * 24
            let wrapped = Self.positiveModulo(frames, framesPer24Hours)
            let tenMinuteBlocks = wrapped / framesPerTenMinutes
            let remainder = wrapped % framesPerTenMinutes

            var labelsSkipped = dropped * 9 * tenMinuteBlocks
            if remainder >= dropped {
                labelsSkipped += dropped * ((remainder - dropped) / framesPerMinute)
            }
            labelFrames = wrapped + labelsSkipped
        } else {
            labelFrames = Self.positiveModulo(frames, nominalFPS * 60 * 60 * 24)
        }

        let frame = labelFrames % nominalFPS
        let totalSeconds = labelFrames / nominalFPS
        let second = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minute = totalMinutes % 60
        let hour = (totalMinutes / 60) % 24
        let separator = isDropFrame ? ";" : ":"

        return String(format: "%02lld:%02lld:%02lld%@%02lld", hour, minute, second, separator, frame)
    }

    /// Invalid dropped labels such as 00:01:00;00 at 29.97 are rejected.
    func frameCount(forTimecode timecode: String) -> Int64? {
        let fields = timecode.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." })
        guard fields.count == 4,
              let hour = Int64(fields[0]),
              let minute = Int64(fields[1]),
              let second = Int64(fields[2]),
              let frame = Int64(fields[3]),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60,
              second >= 0, second < 60,
              frame >= 0, frame < nominalFPS else {
            return nil
        }

        if isDropFrame,
           minute % 10 != 0,
           second == 0,
           frame < droppedFramesPerMinute {
            return nil
        }

        let totalMinutes = hour * 60 + minute
        let nominalFrames = ((hour * 3_600 + minute * 60 + second) * nominalFPS) + frame
        let droppedLabels = isDropFrame
            ? droppedFramesPerMinute * (totalMinutes - totalMinutes / 10)
            : 0
        return nominalFrames - droppedLabels
    }

    private static func isDropFrameCompatible(
        numerator: Int64,
        denominator: Int64,
        nominalFPS: Int64
    ) -> Bool {
        guard nominalFPS == 30 || nominalFPS == 60 else { return false }
        let actual = Double(numerator) / Double(denominator)
        let expected = Double(nominalFPS) * 1_000 / 1_001
        return abs(actual - expected) < 0.001
    }

    private static func greatestCommonDivisor(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }

    private static func positiveModulo(_ value: Int64, _ modulus: Int64) -> Int64 {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}

struct TimecodeFormatter {
    static func timecode(
        from seconds: Double,
        frameRate: Double? = nil,
        startTimecode: String? = nil,
        useDropFrame: Bool = false
    ) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--:--:--" }

        let dropFrame = useDropFrame || (startTimecode?.contains(";") ?? false)
        let rate = TimecodeRate(frameRate: frameRate ?? 30, dropFrame: dropFrame)
        guard let elapsedFrames = rate.frameCount(forSeconds: seconds) else {
            return "--:--:--:--"
        }

        let startFrames: Int64
        if let startTimecode {
            guard let parsedStart = rate.frameCount(forTimecode: startTimecode) else {
                return "--:--:--:--"
            }
            startFrames = parsedStart
        } else {
            startFrames = 0
        }

        return rate.timecode(forFrameCount: startFrames + elapsedFrames)
    }

    /// Compatibility wrapper. The optional form distinguishes invalid input
    /// from a valid zero label.
    static func parseTimecodeToFrames(_ timecode: String, fps: Double) -> Int {
        parseTimecodeToFramesIfValid(timecode, fps: fps) ?? 0
    }

    static func parseTimecodeToFramesIfValid(_ timecode: String, fps: Double) -> Int? {
        let rate = TimecodeRate(frameRate: fps, dropFrame: timecode.contains(";"))
        guard let frames = rate.frameCount(forTimecode: timecode),
              frames >= Int64(Int.min), frames <= Int64(Int.max) else {
            return nil
        }
        return Int(frames)
    }

    static func effectiveStartTimecode(for item: MediaItem) -> String? {
        item.metadata?.timecode
    }

    static func shouldUseTimecode(for item: MediaItem) -> Bool {
        item.metadata?.timecode != nil
    }

    static func startTimecodeInSeconds(for item: MediaItem) -> Double? {
        guard let startTimecode = effectiveStartTimecode(for: item) else { return nil }
        let rate = effectiveTimecodeRate(for: item, dropFrame: startTimecode.contains(";"))
        guard let frames = rate.frameCount(forTimecode: startTimecode) else { return nil }
        return rate.seconds(forFrameCount: frames)
    }

    static func parseAbsoluteTimecodeToSeconds(
        _ input: String,
        item: MediaItem,
        mode: TimecodeDisplayMode
    ) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let startTimecode = mode == .source ? effectiveStartTimecode(for: item) : nil
        let dropFrame = trimmed.contains(";") || (startTimecode?.contains(";") ?? false)
        let rate = effectiveTimecodeRate(for: item, dropFrame: dropFrame)
        guard let inputFrames = parseAbsoluteFrames(trimmed, rate: rate) else { return nil }

        let startFrames: Int64
        if let startTimecode {
            guard let parsedStart = rate.frameCount(forTimecode: startTimecode) else { return nil }
            startFrames = parsedStart
        } else {
            startFrames = 0
        }
        return rate.seconds(forFrameCount: inputFrames - startFrames)
    }

    /// Shared parser for typed navigation, pasted labels, frame counts, source
    /// offsets, frame-only navigation, and +/- offsets.
    static func parseInputToSeconds(
        _ input: String,
        item: MediaItem,
        mode: TimecodeDisplayMode,
        currentSeconds: Double,
        duration: Double
    ) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sourceTimecode = mode == .source ? effectiveStartTimecode(for: item) : nil
        let dropFrame = trimmed.contains(";") || (sourceTimecode?.contains(";") ?? false)
        let rate = effectiveTimecodeRate(for: item, dropFrame: dropFrame)

        if mode == .frames {
            if let sign = leadingSign(in: trimmed) {
                if let frames = Int64(trimmed.dropFirst()), frames >= 0 {
                    return currentSeconds + Double(sign) * rate.seconds(forFrameCount: frames)
                }
            }
            if let frames = Int64(trimmed), frames >= 0 {
                return rate.seconds(forFrameCount: frames)
            }
        }

        if trimmed.hasPrefix("+..") || trimmed.hasPrefix("-..") {
            let sign: Double = trimmed.hasPrefix("+") ? 1 : -1
            guard let frames = Int64(trimmed.dropFirst(3)), frames >= 0 else { return nil }
            return clamped(currentSeconds + sign * rate.seconds(forFrameCount: frames), duration: duration)
        }

        if trimmed.hasPrefix("..") {
            guard let frame = Int64(trimmed.dropFirst(2)),
                  frame >= 0, frame < rate.nominalFPS else { return nil }
            return clamped(floor(currentSeconds) + rate.seconds(forFrameCount: frame), duration: duration)
        }

        if let sign = leadingSign(in: trimmed) {
            let offset = String(trimmed.dropFirst())
            guard let offsetSeconds = parseDuration(offset, rate: rate) else { return nil }
            return clamped(currentSeconds + Double(sign) * offsetSeconds, duration: duration)
        }

        return parseAbsoluteTimecodeToSeconds(trimmed, item: item, mode: mode)
    }

    static func effectiveFrameRate(for item: MediaItem) -> Double {
        effectiveTimecodeRate(for: item).value
    }

    static func effectiveTimecodeRate(for item: MediaItem, dropFrame: Bool = false) -> TimecodeRate {
        if let frameRate = item.metadata?.primaryVideoStream?.frameRate,
           frameRate.numerator > 0, frameRate.denominator > 0 {
            return TimecodeRate(
                numerator: frameRate.numerator,
                denominator: frameRate.denominator,
                dropFrame: dropFrame
            )
        }
        return TimecodeRate(numerator: 30, denominator: 1, dropFrame: dropFrame)
    }

    static func formatTraditionalTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func formatTimeForDisplayWithMode(
        seconds: Double,
        item: MediaItem,
        mode: TimecodeDisplayMode,
        isOutPoint: Bool = false,
        isDuration: Bool = false,
        includePrefix: Bool = false
    ) -> String {
        let sourceTimecode = mode == .source ? effectiveStartTimecode(for: item) : nil
        let dropFrame = sourceTimecode?.contains(";") ?? false
        let rate = effectiveTimecodeRate(for: item, dropFrame: dropFrame)
        guard var elapsedFrames = rate.frameCount(forSeconds: seconds), elapsedFrames >= 0 else {
            return mode == .frames ? "--" : "--:--:--:--"
        }

        // Trim out is stored at the final included frame; display its exclusive endpoint.
        if isOutPoint { elapsedFrames += 1 }

        let displayString: String
        switch mode {
        case .relative:
            displayString = rate.timecode(forFrameCount: elapsedFrames)
        case .source:
            let startFrames: Int64
            if let sourceTimecode,
               let parsedStart = rate.frameCount(forTimecode: sourceTimecode) {
                startFrames = parsedStart
            } else {
                startFrames = 0
            }
            displayString = rate.timecode(forFrameCount: startFrames + elapsedFrames)
        case .frames:
            displayString = String(elapsedFrames)
        }

        return includePrefix ? "\(mode.prefix) \(displayString)" : displayString
    }

    private static func parseAbsoluteFrames(_ input: String, rate: TimecodeRate) -> Int64? {
        let fields = input.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." })
        guard !fields.isEmpty, fields.count <= 4 else { return nil }

        let parsed = fields.compactMap { Int64($0) }
        guard parsed.count == fields.count, parsed.allSatisfy({ $0 >= 0 }) else { return nil }

        var values = [Int64](repeating: 0, count: 4)
        switch parsed.count {
        case 1: values[2] = parsed[0]
        case 2: values[1] = parsed[0]; values[2] = parsed[1]
        case 3: values[0] = parsed[0]; values[1] = parsed[1]; values[2] = parsed[2]
        case 4: values = parsed
        default: return nil
        }

        return rate.frameCount(forTimecode: String(
            format: "%02lld:%02lld:%02lld:%02lld",
            values[0], values[1], values[2], values[3]
        ))
    }

    private static func parseDuration(_ input: String, rate: TimecodeRate) -> Double? {
        let fields = input.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." })
        guard !fields.isEmpty, fields.count <= 4 else { return nil }
        let values = fields.compactMap { Int64($0) }
        guard values.count == fields.count, values.allSatisfy({ $0 >= 0 }) else { return nil }

        var hours: Int64 = 0
        var minutes: Int64 = 0
        var seconds: Int64 = 0
        var frames: Int64 = 0
        switch values.count {
        case 1: seconds = values[0]
        case 2:
            if values[0] < 60, values[1] < 60 {
                minutes = values[0]
                seconds = values[1]
            } else {
                minutes = values[0] / 60
                seconds = values[0] % 60
                frames = values[1]
            }
        case 3: hours = values[0]; minutes = values[1]; seconds = values[2]
        case 4: hours = values[0]; minutes = values[1]; seconds = values[2]; frames = values[3]
        default: return nil
        }

        guard minutes < 60, seconds < 60, frames < rate.nominalFPS else { return nil }
        return Double(hours * 3_600 + minutes * 60 + seconds) + rate.seconds(forFrameCount: frames)
    }

    private static func leadingSign(in input: String) -> Int? {
        if input.hasPrefix("+") { return 1 }
        if input.hasPrefix("-") { return -1 }
        return nil
    }

    private static func clamped(_ seconds: Double, duration: Double) -> Double {
        max(0, min(seconds, max(duration, 0)))
    }
}
