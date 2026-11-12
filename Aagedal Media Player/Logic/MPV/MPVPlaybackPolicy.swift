// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum MPVPlaybackPolicy {
    /// A decoder may be slow on long-GOP or remote media; don't mistake a
    /// normal interactive seek for a stall. This bounds scheduler ownership,
    /// not the duration of libmpv's underlying decode.
    static let seekTimeout: TimeInterval = 30
    static let seekTimeoutMessage = "Seeking took too long. Reload the file to restore playback."

    /// Per-player caps, not allocations. Since MPVKit's mpv 0.42 build,
    /// VideoToolbox surfaces count against the cap too, and a keyframe range
    /// that doesn't fit plays backward at a reduced frame rate. An eighth of
    /// memory keeps a 1 s GOP of UHD 10-bit 60p (about 1.5 GB) at full rate
    /// on 16-GB machines and still leaves room for a comparison decoder, the
    /// GPU and the rest of the app on the supported 8-GB machines.
    static func reversalBufferBytes(physicalMemory: UInt64) -> UInt64 {
        let mib: UInt64 = 1_048_576
        return min(4 * 1024 * mib, max(256 * mib, physicalMemory / 8))
    }
}
