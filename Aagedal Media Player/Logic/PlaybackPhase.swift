// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum PlaybackBackend: String, Equatable, Sendable {
    case mpv
    case avFoundation

    var displayName: String {
        switch self {
        case .mpv: "mpv"
        case .avFoundation: "Apple AVFoundation"
        }
    }
}

nonisolated enum PlaybackFailureStage: String, Equatable, Sendable {
    case initialization
    case loading
    case playback

    var displayName: String {
        switch self {
        case .initialization: "Initialization"
        case .loading: "Loading"
        case .playback: "Playback"
        }
    }
}

nonisolated struct PlaybackFailure: Equatable, Sendable {
    let backend: PlaybackBackend
    let stage: PlaybackFailureStage
    let message: String
    let mediaURL: URL?

    var diagnosticText: String {
        var lines = [
            "Backend: \(backend.displayName)",
            "Stage: \(stage.displayName)",
            "Error: \(message)"
        ]
        if let mediaURL {
            lines.append("File: \(mediaURL.path)")
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated enum PlaybackPhase: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case buffering
    case failed(PlaybackFailure)

    var permitsPlaybackControls: Bool {
        switch self {
        case .ready, .buffering: true
        case .idle, .preparing, .failed: false
        }
    }

    var failure: PlaybackFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}
