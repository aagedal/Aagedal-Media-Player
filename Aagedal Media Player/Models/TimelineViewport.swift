// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Display-only timeline geometry. Transport and frame stepping retain their
/// original source timebase, independently of the visible window.
nonisolated struct TimelineViewport: Equatable {
    let duration: Double
    let zoom: Double
    let start: Double
    let end: Double

    init(duration: Double, zoom: Double = 1, center: Double = 0) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.zoom = zoom.isFinite ? min(64, max(1, zoom)) : 1
        let span = self.duration / self.zoom
        let center = center.isFinite ? center : 0
        start = min(max(0, center - span / 2), self.duration - span)
        end = start + span
    }

    var span: Double { end - start }
    var center: Double { start + span / 2 }

    func contains(_ time: Double) -> Bool {
        time.isFinite && time >= start && time <= end
    }

    func fraction(for time: Double) -> Double {
        guard time.isFinite, span > 0 else { return 0 }
        return min(1, max(0, (time - start) / span))
    }

    func time(at fraction: Double) -> Double {
        guard fraction.isFinite else { return start }
        return start + min(1, max(0, fraction)) * span
    }

    /// Intersect ranges before drawing; offscreen points must be hidden instead
    /// of clamped into false markers at the viewport edges.
    func clipped(_ range: ClosedRange<Double>) -> ClosedRange<Double>? {
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              range.upperBound >= start, range.lowerBound <= end else { return nil }
        return max(start, range.lowerBound)...min(end, range.upperBound)
    }
}
