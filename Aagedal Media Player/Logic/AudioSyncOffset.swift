// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Presentation timing only. Positive offsets delay audio relative to video;
/// source PCM measurements, file timestamps and exports retain original timing.
nonisolated enum AudioSyncOffset {
    static let rangeMilliseconds: ClosedRange<Double> = -2000...2000

    static func validatedMilliseconds(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(rangeMilliseconds.upperBound, max(rangeMilliseconds.lowerBound, value)).rounded()
    }
}
