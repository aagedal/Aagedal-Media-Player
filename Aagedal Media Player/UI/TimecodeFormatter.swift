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

    mutating func toggle() {
        switch self {
        case .relative: self = .source
        case .source: self = .frames
        case .frames: self = .relative
        }
    }

    static var preferred: TimecodeDisplayMode {
        let rawValue = UserDefaults.standard.string(forKey: "preferredTimecodeDisplayMode") ?? "relative"
        return TimecodeDisplayMode(rawValue: rawValue) ?? .relative
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
            let startTC = isDuration ? nil : effectiveStartTimecode(for: item)
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
