// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Commands that can cross scene and view boundaries.
///
/// Using one typed payload keeps command parameters compiler-checked while
/// retaining NotificationCenter's synchronous broadcast behavior for playback
/// synchronization across multiple windows.
enum AppCommand {
    case openFilePicker
    case openFile(URL, targetWindow: NSWindow? = nil)
    case toggleInspector
    case captureScreenshot
    case exportTrim
    case cycleTimecodeMode
    case togglePlayback
    case toggleMute
    case adjustVolume(by: Double)
    case reverse
    case fastForward
    case slowForward
    case slowReverse
    case seekByFrames(Int)
    case seekBySeconds(Double)
    case seekToEdge(PlaybackEdge)
    case toggleFullscreen
    case syncTimecode
    case seekToSyncedTime(SyncedPlaybackTime)
    case copyTimecode
    case pasteTimecode
    case reloadPlayer
    case toggleScopes
    case toggleScopeParade
    case toggleAudioWaveform

    enum PlaybackEdge {
        case start
        case end
    }

    struct SyncedPlaybackTime {
        let relativeSeconds: Double
        let sourceSeconds: Double?
    }
}

extension Notification.Name {
    fileprivate static let appCommand = Notification.Name("com.aagedal.MediaPlayer.appCommand")
}

extension Notification {
    var appCommand: AppCommand? {
        guard name == .appCommand else { return nil }
        return object as? AppCommand
    }
}

extension NotificationCenter {
    func post(_ command: AppCommand) {
        post(name: .appCommand, object: command)
    }

    var appCommandPublisher: NotificationCenter.Publisher {
        publisher(for: .appCommand)
    }
}
