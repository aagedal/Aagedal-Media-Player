// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

typealias LiveAudioMeterDecodeOperation = @Sendable (
    LiveAudioMeterDecodeRequest,
    @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
) async throws -> LiveAudioMeterDecodeCompletion

nonisolated enum LiveAudioMeterLifecycleStatus: Equatable, Sendable {
    case unavailable(reason: String, diagnostic: String?)
    case warmingUp(frame: Int64, momentaryReady: Bool, shortTermReady: Bool)
    case active(frame: Int64)
    case paused(frame: Int64)
    case buffering(frame: Int64)
    case ended(frame: Int64)

    var frame: Int64? {
        switch self {
        case .unavailable: nil
        case .warmingUp(let frame, _, _), .active(let frame), .paused(let frame),
             .buffering(let frame), .ended(let frame): frame
        }
    }
}

/// Window-owned ownership boundary for one live source measurement. PCM remains
/// on the decoder/DSP worker. Only the newest already-computed snapshot crosses
/// to the main actor, so presentation pressure cannot discard DSP input or grow
/// a queue with playback duration.
@MainActor
final class LiveAudioMeterCoordinator {
    nonisolated enum RestartCause: Equatable, Sendable {
        case initial, retry, seek, loopWrap, geometryReload, speedRestored, sourceReplacement
        case resumeAfterSuspension
    }

    private(set) var generation: UInt64 = 0
    private(set) var restartCause: RestartCause?
    private(set) var status: LiveAudioMeterLifecycleStatus = .unavailable(
        reason: "Live meters are closed.", diagnostic: nil
    )
    private(set) var snapshot: LiveAudioMeterSnapshot?
    private(set) var provenance: LiveAudioMeterDecodeProvenance?
    private(set) var publishedSnapshotCount = 0

    private let decodeOperation: LiveAudioMeterDecodeOperation
    private var request: LiveAudioMeterDecodeRequest?
    private var decodeTask: Task<Void, Never>?
    private var handoff: SnapshotHandoff?
    private var isClosed = false

    init(decodeOperation: @escaping LiveAudioMeterDecodeOperation = { request, onSnapshot in
        try await LiveAudioMeterDecoder.decode(request, onSnapshot: onSnapshot)
    }) {
        self.decodeOperation = decodeOperation
    }

    deinit {
        handoff?.invalidate()
        decodeTask?.cancel()
    }

    func start(_ request: LiveAudioMeterDecodeRequest) {
        begin(request, cause: .initial)
    }

    /// Seek, loop wrap, timestamp-preserving reload, restored 1x speed, and
    /// source replacement all create a new DSP segment. They never bridge the
    /// old generation's filters, windows, maxima, or late callbacks.
    func restart(_ request: LiveAudioMeterDecodeRequest, because cause: RestartCause) {
        precondition(cause != .initial && cause != .retry)
        begin(request, cause: cause)
    }

    @discardableResult
    func retry() -> Bool {
        guard let request, !isClosed else { return false }
        begin(request, cause: .retry)
        return true
    }

    func pause() {
        suspend(buffering: false)
    }

    func markBuffering() {
        suspend(buffering: true)
    }

    /// The current decoder cannot be safely paused. Resuming therefore requires
    /// a new explicit source position and a fresh DSP generation; preserving
    /// filter/window history awaits a genuinely controllable paced worker.
    func resume(_ request: LiveAudioMeterDecodeRequest) {
        guard isSuspended(status) else { return }
        begin(request, cause: .resumeAfterSuspension)
    }

    func suspendForUnsupportedSpeed() {
        invalidateCurrent(
            status: .unavailable(
                reason: "Meters require forward 1× playback.",
                diagnostic: "Return to forward 1× playback to start a new measurement segment."
            ),
            clearRequest: false
        )
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        invalidateCurrent(
            status: .unavailable(reason: "Live meters are closed.", diagnostic: nil),
            clearRequest: true
        )
    }

    private func begin(_ newRequest: LiveAudioMeterDecodeRequest, cause: RestartCause) {
        guard !isClosed else { return }
        invalidateWorker()
        generation &+= 1
        let ownedGeneration = generation
        request = newRequest
        restartCause = cause
        snapshot = nil
        provenance = nil
        publishedSnapshotCount = 0
        status = .warmingUp(
            frame: newRequest.startSourceFrame, momentaryReady: false, shortTermReady: false
        )

        let handoff = SnapshotHandoff()
        self.handoff = handoff
        let operation = decodeOperation
        decodeTask = Task { [weak self] in
            do {
                let completion = try await operation(newRequest) { [weak self] snapshot in
                    guard handoff.submit(snapshot) else { return }
                    Task { @MainActor [weak self] in
                        self?.drain(handoff, generation: ownedGeneration)
                    }
                }
                try Task.checkCancellation()
                self?.complete(completion, handoff: handoff, generation: ownedGeneration)
            } catch is CancellationError {
                // Explicit invalidation already owns the visible state. An
                // unexpected current-generation cancellation is handled below.
                self?.cancelled(handoff: handoff, generation: ownedGeneration)
            } catch {
                self?.fail(error, handoff: handoff, generation: ownedGeneration)
            }
        }
    }

    private func drain(_ handoff: SnapshotHandoff, generation ownedGeneration: UInt64) {
        guard generation == ownedGeneration, self.handoff === handoff else {
            handoff.invalidate()
            return
        }
        guard let next = handoff.takeLatest() else { return }
        publish(next)
    }

    private func complete(
        _ completion: LiveAudioMeterDecodeCompletion,
        handoff: SnapshotHandoff,
        generation ownedGeneration: UInt64
    ) {
        guard generation == ownedGeneration, self.handoff === handoff else {
            handoff.invalidate()
            return
        }
        if let pending = handoff.invalidateAndTakeLatest() { publish(pending) }
        if completion.finalSnapshot != snapshot { completion.finalSnapshot.map(publish) }
        provenance = completion.provenance
        decodeTask = nil
        self.handoff = nil
        let endFrame = completion.finalSnapshot?.endFrame ?? snapshot?.endFrame
            ?? completion.provenance.request.startSourceFrame
        status = .ended(frame: endFrame)
    }

    private func fail(
        _ error: Error, handoff: SnapshotHandoff, generation ownedGeneration: UInt64
    ) {
        guard generation == ownedGeneration, self.handoff === handoff else {
            handoff.invalidate()
            return
        }
        handoff.invalidate()
        decodeTask = nil
        self.handoff = nil
        snapshot = nil
        provenance = nil
        status = .unavailable(
            reason: "Live source audio is unavailable.", diagnostic: error.localizedDescription
        )
    }

    private func cancelled(handoff: SnapshotHandoff, generation ownedGeneration: UInt64) {
        guard generation == ownedGeneration, self.handoff === handoff else {
            handoff.invalidate()
            return
        }
        handoff.invalidate()
        decodeTask = nil
        self.handoff = nil
        snapshot = nil
        provenance = nil
        status = .unavailable(
            reason: "Live source audio is unavailable.",
            diagnostic: LiveAudioMeterDecoder.Failure.cancelled.localizedDescription
        )
    }

    private func publish(_ next: LiveAudioMeterSnapshot) {
        snapshot = next
        publishedSnapshotCount += 1
        status = readinessStatus(frame: next.endFrame)
    }

    private func readinessStatus(frame: Int64) -> LiveAudioMeterLifecycleStatus {
        guard let request else {
            return .unavailable(reason: "No live meter source is selected.", diagnostic: nil)
        }
        let measuredFrames = max(0, frame - request.startSourceFrame)
        let momentaryReady = measuredFrames >= Int64(request.format.sampleRate * 4 / 10)
        let shortTermReady = measuredFrames >= Int64(request.format.sampleRate * 3)
        return momentaryReady && shortTermReady
            ? .active(frame: frame)
            : .warmingUp(
                frame: frame, momentaryReady: momentaryReady, shortTermReady: shortTermReady
            )
    }

    private func invalidateCurrent(
        status newStatus: LiveAudioMeterLifecycleStatus, clearRequest: Bool
    ) {
        invalidateWorker()
        generation &+= 1
        snapshot = nil
        provenance = nil
        publishedSnapshotCount = 0
        restartCause = nil
        if clearRequest { request = nil }
        status = newStatus
    }

    private func invalidateWorker() {
        let oldHandoff = handoff
        let oldTask = decodeTask
        handoff = nil
        decodeTask = nil
        oldHandoff?.invalidate()
        oldTask?.cancel()
    }

    private func suspend(buffering: Bool) {
        guard !isClosed, let frame = status.frame, !isTerminal(status) else { return }
        if !isSuspended(status) {
            // Invalidate ownership before cancellation so a decoder that ignores
            // cancellation cannot advance the frozen presentation.
            invalidateWorker()
            generation &+= 1
        }
        status = buffering ? .buffering(frame: frame) : .paused(frame: frame)
    }

    private func isSuspended(_ status: LiveAudioMeterLifecycleStatus) -> Bool {
        if case .paused = status { return true }
        if case .buffering = status { return true }
        return false
    }

    private func isTerminal(_ status: LiveAudioMeterLifecycleStatus) -> Bool {
        if case .unavailable = status { return true }
        if case .ended = status { return true }
        return false
    }
}

/// One-slot, post-DSP handoff. Submitting replaces only an unpublished UI
/// snapshot; the decoder has already synchronously processed every PCM sample.
nonisolated private final class SnapshotHandoff: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var pending: LiveAudioMeterSnapshot?
    private nonisolated(unsafe) var drainScheduled = false
    private nonisolated(unsafe) var isValid = true

    /// Returns true only when a main-actor drain must be scheduled.
    func submit(_ snapshot: LiveAudioMeterSnapshot) -> Bool {
        lock.withLock {
            guard isValid else { return false }
            pending = snapshot
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
    }

    func takeLatest() -> LiveAudioMeterSnapshot? {
        lock.withLock {
            guard isValid else { return nil }
            defer { pending = nil; drainScheduled = false }
            return pending
        }
    }

    func invalidateAndTakeLatest() -> LiveAudioMeterSnapshot? {
        lock.withLock {
            guard isValid else { return nil }
            isValid = false
            defer { pending = nil; drainScheduled = false }
            return pending
        }
    }

    func invalidate() {
        lock.withLock {
            isValid = false
            pending = nil
            drainScheduled = false
        }
    }
}
