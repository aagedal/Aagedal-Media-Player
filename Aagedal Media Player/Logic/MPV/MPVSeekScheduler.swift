// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

/// Owned by MPVPlayer's event queue. Command acceptance alone does not mean
/// that the decoder has produced a frame: wait for seek + playback-restart.
nonisolated struct MPVSeekScheduler {
    struct Request: Equatable {
        let time: Double
        let exact: Bool
    }

    struct Submission: Equatable {
        let id: UInt64
        let request: Request
    }

    private(set) var pending: Request?
    private(set) var inFlight: Submission?
    private var nextID: UInt64 = 0
    private var accepted = false
    private var started = false
    private var restarted = false

    mutating func request(_ request: Request) -> Submission? {
        guard request.time.isFinite else { return nil }
        pending = request
        return takeNext()
    }

    mutating func commandReplied(id: UInt64, succeeded: Bool) -> Submission? {
        guard inFlight?.id == id else { return nil }
        if !succeeded { return finish() }
        accepted = true
        return finishIfReady()
    }

    mutating func seekStarted() {
        guard inFlight != nil else { return }
        started = true
    }

    mutating func playbackRestarted() -> Submission? {
        // Ignore startup and other discontinuities preceding our seek event.
        guard inFlight != nil, started else { return nil }
        restarted = true
        return finishIfReady()
    }

    mutating func cancelPendingPreview() {
        if pending?.exact == false { pending = nil }
    }

    mutating func reset() {
        pending = nil
        inFlight = nil
        accepted = false
        started = false
        restarted = false
    }

    private mutating func finishIfReady() -> Submission? {
        guard accepted, restarted else { return nil }
        return finish()
    }

    private mutating func finish() -> Submission? {
        inFlight = nil
        return takeNext()
    }

    private mutating func takeNext() -> Submission? {
        guard inFlight == nil, let request = pending else { return nil }
        pending = nil
        nextID &+= 1
        let submission = Submission(id: nextID, request: request)
        inFlight = submission
        accepted = false
        started = false
        restarted = false
        return submission
    }
}
