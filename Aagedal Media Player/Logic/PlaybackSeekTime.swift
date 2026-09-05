// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreMedia
import Foundation

/// Converts playback seconds without truncating a frame boundary backwards.
/// 120,000 ticks represent 23.976/24/25/29.97/30/50/59.94/60 fps exactly.
nonisolated enum PlaybackSeekTime {
    static let timescale: CMTimeScale = 120_000

    static func make(seconds: TimeInterval) -> CMTime? {
        guard seconds.isFinite, seconds >= 0,
              let ticks = Int64(exactly: (seconds * Double(timescale)).rounded()) else { return nil }
        return CMTime(value: ticks, timescale: timescale)
    }
}
