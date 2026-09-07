// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// UI percentages represent linear amplitude, matching AVPlayer.volume.
nonisolated enum PlaybackVolume {
    static func mpvValue(for percent: Double) -> Double {
        let amplitude = percent.isFinite ? min(100, max(0, percent)) / 100 : 1
        // mpv 0.41 audio_get_gain cubes volume/100. Invert that curve so
        // 50% means half amplitude instead of one eighth (-18 dB).
        // https://github.com/mpv-player/mpv/blob/v0.41.0/player/audio.c
        return 100 * cbrt(amplitude)
    }
}
