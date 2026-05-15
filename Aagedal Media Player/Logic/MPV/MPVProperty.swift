// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct MPVProperty {
    // Video parameters
    nonisolated static let videoParamsColormatrix = "video-params/colormatrix"
    nonisolated static let videoParamsColorlevels = "video-params/colorlevels"
    nonisolated static let videoParamsPrimaries = "video-params/primaries"
    nonisolated static let videoParamsGamma = "video-params/gamma"
    nonisolated static let videoParamsSigPeak = "video-params/sig-peak"

    // Playback state
    nonisolated static let duration = "duration"
    nonisolated static let timePos = "time-pos"
    nonisolated static let path = "path"
    nonisolated static let pause = "pause"
    nonisolated static let pausedForCache = "paused-for-cache"
    nonisolated static let eofReached = "eof-reached"
    nonisolated static let seekable = "seekable"
    nonisolated static let speed = "speed"

    // Video display dimensions used for window sizing.
    //
    // `video-params/dw,dh` are the source display dims (coded × PAR) — they
    // do *not* include container rotation. `video-params/rotate` carries the
    // file's rotation in degrees. With hwdec=videotoolbox the filter chain
    // doesn't reliably populate `video-out-params/*` or top-level
    // `dwidth`/`dheight` with rotation-applied dims either, so the most
    // reliable path is to read the source dims + rotate and apply the swap
    // ourselves — mirroring what MetadataService does on the SwiftExif side.
    nonisolated static let videoParamsDw = "video-params/dw"
    nonisolated static let videoParamsDh = "video-params/dh"
    nonisolated static let videoParamsRotate = "video-params/rotate"

    // Audio
    nonisolated static let volume = "volume"
    nonisolated static let mute = "mute"
    nonisolated static let aid = "aid"
    nonisolated static let trackListCount = "track-list/count"

    // Subtitles
    nonisolated static let sid = "sid"
    nonisolated static let subVisibility = "sub-visibility"

    // Chapters
    nonisolated static let chapter = "chapter"
    nonisolated static let chapterListCount = "chapter-list/count"
}
