// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Utility for formatting time as timecode (HH:MM:SS:FF)

import Foundation

/// Represents how timecode should be displayed
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

struct TimecodeFormatter {
    static func timecode(
        from seconds: Double,
        frameRate: Double? = nil,
        startTimecode: String? = nil,
        useDropFrame: Bool = false
    ) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "--:--:--:--"
        }

        let fps = frameRate ?? 30.0
        let roundedFps = Int(fps.rounded())

        let startOffsetFrames: Int
        if let startTC = startTimecode {
            startOffsetFrames = parseTimecodeToFrames(startTC, fps: fps)
        } else {
            startOffsetFrames = 0
        }

        let totalFramesFromSeconds = Int((seconds * fps).rounded())
        let totalFrames = startOffsetFrames + totalFramesFromSeconds

        let frames = totalFrames % roundedFps
        var remainingFrames = totalFrames / roundedFps

        let secs = remainingFrames % 60
        remainingFrames /= 60

        let mins = remainingFrames % 60
        remainingFrames /= 60

        let hours = remainingFrames % 24

        let separator = useDropFrame ? ";" : ":"

        return String(format: "%02d:%02d:%02d%@%02d", hours, mins, secs, separator, frames)
    }

    static func parseTimecodeToFrames(_ timecode: String, fps: Double) -> Int {
        let components = timecode.split(whereSeparator: { $0 == ":" || $0 == ";" })

        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let frames = Int(components[3]) else {
            return 0
        }

        let roundedFps = Int(fps.rounded())

        var totalFrames = hours * 3600 * roundedFps
        totalFrames += minutes * 60 * roundedFps
        totalFrames += seconds * roundedFps
        totalFrames += frames

        return totalFrames
    }

    static func effectiveStartTimecode(for item: MediaItem) -> String? {
        return item.metadata?.timecode
    }

    static func shouldUseTimecode(for item: MediaItem) -> Bool {
        return item.metadata?.timecode != nil
    }

    /// Converts a MediaItem's start timecode to absolute seconds (e.g. "01:00:00:00" at 24fps → 3600.0).
    /// Returns nil if the item has no source timecode.
    static func startTimecodeInSeconds(for item: MediaItem) -> Double? {
        guard let startTC = effectiveStartTimecode(for: item) else { return nil }
        let fps = effectiveFrameRate(for: item)
        let totalFrames = parseTimecodeToFrames(startTC, fps: fps)
        return Double(totalFrames) / fps
    }

    /// Parses an absolute timecode string (e.g. "01:23:45:12") into playback seconds,
    /// subtracting the item's start timecode offset when in source mode.
    /// Used by both ControlsView and the paste-timecode handler.
    static func parseAbsoluteTimecodeToSeconds(
        _ input: String,
        item: MediaItem,
        mode: TimecodeDisplayMode
    ) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let frameRate = effectiveFrameRate(for: item)
        let fps = Int(frameRate.rounded())

        let components = trimmed.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." })
        guard !components.isEmpty, components.count <= 4 else { return nil }

        var hours = 0
        var minutes = 0
        var seconds = 0
        var frames = 0

        switch components.count {
        case 1:
            guard let s = Int(components[0]) else { return nil }
            seconds = s
        case 2:
            guard let m = Int(components[0]),
                  let s = Int(components[1]) else { return nil }
            minutes = m
            seconds = s
        case 3:
            guard let h = Int(components[0]),
                  let m = Int(components[1]),
                  let s = Int(components[2]) else { return nil }
            hours = h
            minutes = m
            seconds = s
        case 4:
            guard let h = Int(components[0]),
                  let m = Int(components[1]),
                  let s = Int(components[2]),
                  let f = Int(components[3]) else { return nil }
            hours = h
            minutes = m
            seconds = s
            frames = f
        default:
            return nil
        }

        guard hours >= 0, hours < 24,
              minutes >= 0, minutes < 60,
              seconds >= 0, seconds < 60,
              frames >= 0, frames < fps else {
            return nil
        }

        let startTC: String? = (mode == .source) ? effectiveStartTimecode(for: item) : nil

        if let startTC = startTC {
            let inputTotalFrames = hours * 3600 * fps + minutes * 60 * fps + seconds * fps + frames
            let startTotalFrames = parseTimecodeToFrames(startTC, fps: frameRate)
            let frameOffset = inputTotalFrames - startTotalFrames
            return Double(frameOffset) / frameRate
        } else {
            let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds)
            let frameSeconds = Double(frames) / frameRate
            return totalSeconds + frameSeconds
        }
    }

    static func effectiveFrameRate(for item: MediaItem) -> Double {
        if let frameRate = item.metadata?.primaryVideoStream?.frameRate?.value, frameRate > 0 {
            return frameRate
        }
        return 30.0
    }

    static func formatTraditionalTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    static func formatTimeForDisplayWithMode(
        seconds: Double,
        item: MediaItem,
        mode: TimecodeDisplayMode,
        isOutPoint: Bool = false,
        isDuration: Bool = false,
        includePrefix: Bool = false
    ) -> String {
        let frameRate = effectiveFrameRate(for: item)
        let adjustedSeconds = isOutPoint ? seconds + (1.0 / frameRate) : seconds

        let displayString: String

        switch mode {
        case .relative:
            displayString = timecode(
                from: adjustedSeconds,
                frameRate: frameRate,
                startTimecode: nil,
                useDropFrame: false
            )
        case .source:
            let startTC = effectiveStartTimecode(for: item)
            let useDropFrame = startTC?.contains(";") ?? false
            displayString = timecode(
                from: adjustedSeconds,
                frameRate: frameRate,
                startTimecode: startTC,
                useDropFrame: useDropFrame
            )
        case .frames:
            let frameNumber = Int((adjustedSeconds * frameRate).rounded())
            displayString = String(frameNumber)
        }

        if includePrefix {
            return "\(mode.prefix) \(displayString)"
        }
        return displayString
    }
}
