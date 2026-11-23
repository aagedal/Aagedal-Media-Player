// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Coordinates macOS display and idle-sleep assertions across active players.

import Foundation
import OSLog

nonisolated enum PlaybackSleepAssertionLevel: Int, Equatable, Comparable, Sendable {
    /// No sleep prevention (paused, idle, failed, or no playable streams).
    case none = 0
    /// Prevent idle system sleep while allowing the display to dim and sleep.
    case preventSystemSleep = 1
    /// Prevent display dimming, display sleep, and idle system sleep.
    case preventDisplaySleep = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var reason: String {
        switch self {
        case .none:
            ""
        case .preventSystemSleep:
            "Playing audio"
        case .preventDisplaySleep:
            "Playing video"
        }
    }

    static func required(
        isPlaying: Bool,
        isReversing: Bool,
        hasMediaItem: Bool,
        presentationKind: MediaPresentationKind?,
        hasVideoStream: Bool
    ) -> PlaybackSleepAssertionLevel {
        guard hasMediaItem, isPlaying || isReversing else {
            return .none
        }

        switch presentationKind {
        case .video:
            return .preventDisplaySleep
        case .audioOnly:
            return .preventSystemSleep
        case .noPlayableStreams:
            return .none
        case .unresolved, nil:
            return hasVideoStream ? .preventDisplaySleep : .preventSystemSleep
        }
    }
}

@MainActor
protocol PlaybackSleepAssertionBackend: AnyObject {
    func beginAssertion(level: PlaybackSleepAssertionLevel, reason: String) -> AnyObject
    func endAssertion(_ token: AnyObject)
}

@MainActor
final class ProcessInfoSleepAssertionBackend: PlaybackSleepAssertionBackend {
    private final class ActivityToken {
        let activity: NSObjectProtocol

        init(_ activity: NSObjectProtocol) {
            self.activity = activity
        }
    }

    func beginAssertion(level: PlaybackSleepAssertionLevel, reason: String) -> AnyObject {
        let options: ProcessInfo.ActivityOptions
        switch level {
        case .none:
            options = []
        case .preventSystemSleep:
            options = [.userInitiated]
        case .preventDisplaySleep:
            options = [.userInitiated, .idleDisplaySleepDisabled]
        }
        return ActivityToken(ProcessInfo.processInfo.beginActivity(options: options, reason: reason))
    }

    func endAssertion(_ token: AnyObject) {
        guard let activityToken = token as? ActivityToken else { return }
        ProcessInfo.processInfo.endActivity(activityToken.activity)
    }
}

/// Tracks active playback sleep requirements across all windows and compare
/// sessions, holding at most one macOS power assertion matching the highest
/// active requirement.
@MainActor
final class PlaybackSleepAssertionCoordinator {
    static let shared = PlaybackSleepAssertionCoordinator()

    private let backend: any PlaybackSleepAssertionBackend
    private let logger = Logger(
        subsystem: "com.aagedal.MediaPlayer",
        category: "PlaybackSleepAssertion"
    )

    private var sourceLevels: [UUID: PlaybackSleepAssertionLevel] = [:]
    private(set) var activeLevel: PlaybackSleepAssertionLevel = .none
    private var activeToken: AnyObject?

    init(backend: any PlaybackSleepAssertionBackend = ProcessInfoSleepAssertionBackend()) {
        self.backend = backend
    }

    var activeSourceCount: Int {
        sourceLevels.count
    }

    func update(sourceID: UUID, level: PlaybackSleepAssertionLevel) {
        if level == .none {
            sourceLevels.removeValue(forKey: sourceID)
        } else {
            sourceLevels[sourceID] = level
        }
        reconcile()
    }

    func removeSource(_ sourceID: UUID) {
        guard sourceLevels.removeValue(forKey: sourceID) != nil else { return }
        reconcile()
    }

    private func reconcile() {
        let desiredLevel = sourceLevels.values.max() ?? .none
        guard desiredLevel != activeLevel else { return }

        let previousToken = activeToken
        if desiredLevel == .none {
            activeToken = nil
            activeLevel = .none
            if let previousToken {
                backend.endAssertion(previousToken)
            }
            logger.debug("Released playback sleep assertion")
            return
        }

        // Acquire the replacement before releasing the old token so display or
        // system sleep prevention never has an unprotected gap.
        activeToken = backend.beginAssertion(level: desiredLevel, reason: desiredLevel.reason)
        activeLevel = desiredLevel
        if let previousToken {
            backend.endAssertion(previousToken)
        }
        logger.debug("Updated playback sleep assertion to \(desiredLevel.reason, privacy: .public)")
    }
}
