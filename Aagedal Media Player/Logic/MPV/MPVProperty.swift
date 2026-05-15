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

    // Video display aspect ratio and dimensions (early sizing)
    nonisolated static let videoParamsAspect = "video-params/aspect"
    nonisolated static let videoParamsDw = "video-params/dw"
    nonisolated static let videoParamsDh = "video-params/dh"

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
