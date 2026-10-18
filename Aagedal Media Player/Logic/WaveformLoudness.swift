// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Display geometry for the analyzer's already bounded, source-relative history.
/// Missing windows break the line; range results never stretch to the whole file.
nonisolated enum WaveformLoudnessGeometry {
    struct Point: Equatable { let x: Double; let y: Double }
    static let minimumLUFS = -70.0
    static let maximumLUFS = 0.0

    static func segments(samples: [FFmpegService.LoudnessSample], duration: Double,
                         range: FFmpegService.LoudnessRange?, shortTerm: Bool) -> [[Point]] {
        guard duration.isFinite, duration > 0 else { return [] }
        var segments: [[Point]] = []
        var current: [Point] = []
        var previousTime = -Double.infinity
        for sample in samples {
            let value = shortTerm ? sample.shortTerm : sample.momentary
            let ordered = sample.seconds > previousTime
            if sample.seconds.isFinite { previousTime = max(previousTime, sample.seconds) }
            guard sample.seconds.isFinite, sample.seconds >= 0, sample.seconds <= duration,
                  range.map({ sample.seconds >= $0.start && sample.seconds <= $0.end }) ?? true,
                  ordered, let value, value.isFinite else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            current.append(Point(x: sample.seconds / duration,
                y: 1 - (min(maximumLUFS, max(minimumLUFS, value)) - minimumLUFS) / (maximumLUFS - minimumLUFS)))
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}
