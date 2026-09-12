// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

typealias LiveAudioMeterDecodeOperation = @Sendable (
    LiveAudioMeterDecodeRequest,
    SubprocessHandle,
    LiveAudioMeterWorkerGate,
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

/// Every peak bucket is reduced before the one-slot UI handoff. This preserves
/// immediate attacks and held transients even when the main actor coalesces
/// several raw DSP snapshots into one rendered update.
nonisolated struct LiveAudioMeterReducedSnapshot: Equatable, Sendable {
    let measurement: LiveAudioMeterSnapshot
    let samplePeaks: [LiveAudioMeterLevelState]
    let truePeaks: [LiveAudioMeterLevelState]
    let loudness: LiveAudioMeterLoudnessState

    func clearingMaxima() -> Self {
        Self(
            measurement: measurement,
            samplePeaks: samplePeaks.map {
                .init(current: $0.current, bar: $0.bar, marker: $0.marker, maximum: nil)
            },
            truePeaks: truePeaks.map {
                .init(current: $0.current, bar: $0.bar, marker: $0.marker, maximum: nil)
            },
            loudness: .init(
                momentary: loudness.momentary,
                maximumMomentary: nil,
                shortTerm: loudness.shortTerm,
                maximumShortTerm: nil
            )
        )
    }
}

/// Window-owned ownership boundary for one live source measurement. PCM remains
/// on the decoder/DSP worker. Only the newest already-computed snapshot crosses
/// to the main actor, so presentation pressure cannot discard DSP input or grow
/// a queue with playback duration.
@MainActor
final class LiveAudioMeterCoordinator: ObservableObject {
    nonisolated enum RestartCause: Equatable, Sendable {
        case initial, retry, manualReset, seek, loopWrap, geometryReload, speedRestored, sourceReplacement
        case resumeAfterSuspension
    }

    @Published private(set) var generation: UInt64 = 0
    @Published private(set) var restartCause: RestartCause?
    @Published private(set) var status: LiveAudioMeterLifecycleStatus = .unavailable(
        reason: "Live meters are closed.", diagnostic: nil
    )
    @Published private(set) var snapshot: LiveAudioMeterSnapshot?
    @Published private(set) var reducedSnapshot: LiveAudioMeterReducedSnapshot?
    @Published private(set) var provenance: LiveAudioMeterDecodeProvenance?
    @Published private(set) var publishedSnapshotCount = 0
    @Published private(set) var clockDrift: TimeInterval?

    private let decodeOperation: LiveAudioMeterDecodeOperation
    private var request: LiveAudioMeterDecodeRequest?
    private var decodeTask: Task<Void, Never>?
    private var decoderControl: SubprocessHandle?
    private var workerGate: LiveAudioMeterWorkerGate?
    private var handoff: SnapshotHandoff?
    private var isClosed = false
    private var isTransportSuspended = false
    private var isClockSuspended = false
    private var isWaitingForSupportedSpeed = false

    init(decodeOperation: @escaping LiveAudioMeterDecodeOperation = { request, control, gate, onSnapshot in
        try await LiveAudioMeterDecoder.decode(
            request, handle: control, workerGate: gate, onSnapshot: onSnapshot
        )
    }) {
        self.decodeOperation = decodeOperation
    }

    deinit {
        handoff?.invalidate()
        workerGate?.cancel()
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

    /// Retry at the player's current source clock, not at the failed segment's
    /// stale original request position.
    @discardableResult
    func retry(at playbackTime: TimeInterval) -> Bool {
        guard let request, !isClosed,
              let repositioned = try? request.repositioned(at: playbackTime) else { return false }
        begin(repositioned, cause: .retry)
        return true
    }

    /// Manual reset starts a completely new DSP segment at the current player
    /// clock while leaving source selection unchanged.
    @discardableResult
    func reset(at playbackTime: TimeInterval) -> Bool {
        guard let request, !isClosed,
              let repositioned = try? request.repositioned(at: playbackTime) else { return false }
        begin(repositioned, cause: .manualReset)
        return true
    }

    /// Clears presentation maxima without touching peak ballistics or the
    /// decoder/DSP window history. The reducer also updates any unpublished
    /// coalesced snapshot atomically.
    func clearMaxima() {
        handoff?.clearMaxima()
        reducedSnapshot = reducedSnapshot?.clearingMaxima()
    }

    func pause() {
        suspend(buffering: false)
    }

    func markBuffering() {
        suspend(buffering: true)
    }

    /// Resumes the same paced decoder and DSP generation when the selected
    /// source is unchanged. A replacement source starts a clean segment.
    func resume(_ request: LiveAudioMeterDecodeRequest) {
        guard isSuspended(status) else { return }
        guard self.request?.hasSameSource(as: request) == true,
              decoderControl != nil, handoff != nil, decodeTask != nil else {
            begin(request, cause: .resumeAfterSuspension)
            return
        }
        isTransportSuspended = false
        applyWorkerSuspension()
        let frame = snapshot?.endFrame ?? status.frame ?? request.startSourceFrame
        status = readinessStatus(frame: frame)
    }

    /// Reconciles the most recently reduced DSP endpoint with the actual
    /// measured-player clock. A violation is made unavailable; stale or
    /// advanced readings are never silently shown as synchronized.
    func updatePlaybackClock(_ playback: LiveAudioMeterPlaybackSnapshot) {
        guard !isClosed else { return }
        guard playback.supportsMeasurement else {
            suspendForUnsupportedSpeed()
            return
        }
        if isWaitingForSupportedSpeed, let request,
           let repositioned = try? request.repositioned(at: playback.time) {
            begin(repositioned, cause: .speedRestored)
        }
        if playback.phase == .buffering {
            workerGate?.update(playbackTime: playback.time)
            markBuffering()
            return
        }
        guard playback.isPlaying else {
            workerGate?.update(playbackTime: playback.time)
            pause()
            return
        }
        workerGate?.update(playbackTime: playback.time)
        if isTransportSuspended, let request {
            resume(request)
        }
        guard let request, let endFrame = reducedSnapshot?.measurement.endFrame else { return }
        let assessment = LiveAudioMeterClockPolicy(
            sampleRate: request.format.sampleRate
        ).assess(
            decodedEndFrame: endFrame,
            playbackTime: playback.time,
            isSuspendedAhead: isClockSuspended
        )
        switch assessment {
        case .synchronized(let drift):
            clockDrift = drift
        case .suspendAhead(let drift):
            clockDrift = drift
            if !isClockSuspended {
                isClockSuspended = true
                applyWorkerSuspension()
            }
        case .resume(let drift):
            clockDrift = drift
            isClockSuspended = false
            applyWorkerSuspension()
        case .failed(let drift):
            clockDrift = drift
            invalidateCurrent(
                status: .unavailable(
                    reason: "Live meters lost synchronization with playback.",
                    diagnostic: String(
                        format: "Decoded source drift was %+.1f ms; retry to start at the current player position.",
                        drift * 1_000
                    )
                ),
                clearRequest: false
            )
        case .invalidClock:
            invalidateCurrent(
                status: .unavailable(
                    reason: "The playback clock is unavailable.",
                    diagnostic: "Retry after the player reports a finite source position."
                ),
                clearRequest: false
            )
        }
    }

    /// Applies the typed transport boundary. Source and track replacements
    /// deliberately require the window session to supply a newly resolved
    /// request; reusing the old stream identity would be unsafe.
    func handlePlaybackEvent(_ event: LiveAudioMeterPlaybackEvent) {
        switch event {
        case .clock(let playback), .transport(let playback):
            updatePlaybackClock(playback)
        case .scrubbing:
            invalidateCurrent(
                status: .unavailable(
                    reason: "Live meters are suspended while scrubbing.",
                    diagnostic: "Finish scrubbing to start a new measurement segment."
                ),
                clearRequest: false
            )
        case .ended(let playback):
            // The paced source decoder owns FIR-tail drainage and publishes
            // the authoritative final endpoint. Playback normally reports
            // `isPlaying == false` here, which must not suspend that drainage.
            workerGate?.update(playbackTime: playback.time)
            isTransportSuspended = false
            isClockSuspended = false
            applyWorkerSuspension()
        case .discontinuity(let cause, let playback):
            guard playback.supportsMeasurement else {
                suspendForUnsupportedSpeed()
                return
            }
            switch cause {
            case .sourceReplacement, .audioTrackReplacement:
                invalidateCurrent(
                    status: .unavailable(
                        reason: "The measured audio source changed.",
                        diagnostic: "Resolve the selected track and start a new meter generation."
                    ),
                    clearRequest: false
                )
            case .seek, .frameStep, .scrub, .loopWrap, .geometryReload:
                guard let request,
                      let repositioned = try? request.repositioned(at: playback.time) else {
                    invalidateCurrent(
                        status: .unavailable(
                            reason: "The playback position is unavailable.",
                            diagnostic: "Retry after the measured source reports a finite position."
                        ),
                        clearRequest: false
                    )
                    return
                }
                begin(repositioned, cause: restartCause(for: cause))
            }
        }
    }

    func suspendForUnsupportedSpeed() {
        guard !isWaitingForSupportedSpeed else { return }
        invalidateCurrent(
            status: .unavailable(
                reason: "Meters require forward 1× playback.",
                diagnostic: "Return to forward 1× playback to start a new measurement segment."
            ),
            clearRequest: false
        )
        isWaitingForSupportedSpeed = true
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
        reducedSnapshot = nil
        provenance = nil
        publishedSnapshotCount = 0
        clockDrift = nil
        isTransportSuspended = false
        isClockSuspended = false
        isWaitingForSupportedSpeed = false
        status = .warmingUp(
            frame: newRequest.startSourceFrame, momentaryReady: false, shortTermReady: false
        )

        let handoff = SnapshotHandoff(format: newRequest.format)
        self.handoff = handoff
        let decoderControl = SubprocessHandle()
        self.decoderControl = decoderControl
        let workerGate = LiveAudioMeterWorkerGate(request: newRequest)
        self.workerGate = workerGate
        let operation = decodeOperation
        decodeTask = Task { [weak self] in
            do {
                let completion = try await operation(
                    newRequest, decoderControl, workerGate
                ) { [weak self] snapshot in
                    switch handoff.submit(snapshot) {
                    case .scheduleDrain:
                        Task { @MainActor [weak self] in
                            self?.drain(handoff, generation: ownedGeneration)
                        }
                    case .noDrain:
                        break
                    case .rejected(let error):
                        // A malformed callback is a generation failure, not a
                        // reason to leave an invalid handoff and worker alive.
                        decoderControl.cancel()
                        Task { @MainActor [weak self] in
                            self?.fail(error, handoff: handoff, generation: ownedGeneration)
                        }
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
        if let rejection = handoff.rejection {
            fail(rejection, handoff: handoff, generation: ownedGeneration)
            return
        }
        if let final = completion.finalSnapshot, final != snapshot {
            _ = handoff.submit(final)
        }
        if let rejection = handoff.rejection {
            fail(rejection, handoff: handoff, generation: ownedGeneration)
            return
        }
        if let pending = handoff.invalidateAndTakeLatest() { publish(pending) }
        provenance = completion.provenance
        decodeTask = nil
        decoderControl = nil
        workerGate?.cancel()
        self.workerGate = nil
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
        // A malformed snapshot cancels its worker. If that cancellation races
        // this callback, retain the specific handoff rejection instead of
        // replacing it with a generic decoder/cancellation diagnostic.
        let presentedError = handoff.rejection ?? error
        handoff.invalidate()
        // `fail` usually runs after decode has already thrown. Snapshot-handoff
        // rejection is different: it originates in the callback while decode
        // is still active, so explicitly cancel any such in-flight operation.
        decodeTask?.cancel()
        decodeTask = nil
        decoderControl = nil
        workerGate?.cancel()
        self.workerGate = nil
        self.handoff = nil
        snapshot = nil
        reducedSnapshot = nil
        provenance = nil
        clockDrift = nil
        status = .unavailable(
            reason: "Live source audio is unavailable.",
            diagnostic: presentedError.localizedDescription
        )
    }

    private func cancelled(handoff: SnapshotHandoff, generation ownedGeneration: UInt64) {
        guard generation == ownedGeneration, self.handoff === handoff else {
            handoff.invalidate()
            return
        }
        if let rejection = handoff.rejection {
            fail(rejection, handoff: handoff, generation: ownedGeneration)
            return
        }
        handoff.invalidate()
        decodeTask = nil
        decoderControl = nil
        workerGate?.cancel()
        self.workerGate = nil
        self.handoff = nil
        snapshot = nil
        reducedSnapshot = nil
        provenance = nil
        clockDrift = nil
        status = .unavailable(
            reason: "Live source audio is unavailable.",
            diagnostic: LiveAudioMeterDecoder.Failure.cancelled.localizedDescription
        )
    }

    private func publish(_ next: LiveAudioMeterReducedSnapshot) {
        snapshot = next.measurement
        reducedSnapshot = next
        publishedSnapshotCount += 1
        status = readinessStatus(frame: next.measurement.endFrame)
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
        reducedSnapshot = nil
        provenance = nil
        publishedSnapshotCount = 0
        clockDrift = nil
        restartCause = nil
        isTransportSuspended = false
        isClockSuspended = false
        if clearRequest { request = nil }
        status = newStatus
    }

    private func invalidateWorker() {
        let oldHandoff = handoff
        let oldTask = decodeTask
        let oldWorkerGate = workerGate
        handoff = nil
        decodeTask = nil
        decoderControl = nil
        workerGate = nil
        oldHandoff?.invalidate()
        oldWorkerGate?.cancel()
        oldTask?.cancel()
    }

    private func suspend(buffering: Bool) {
        guard !isClosed, let frame = status.frame, !isTerminal(status) else { return }
        if !isSuspended(status) {
            isTransportSuspended = true
            applyWorkerSuspension()
        }
        status = buffering ? .buffering(frame: frame) : .paused(frame: frame)
    }

    private func applyWorkerSuspension() {
        if isTransportSuspended || isClockSuspended {
            handoff?.suspend()
            workerGate?.suspend()
            decoderControl?.suspend()
            return
        }
        if let pending = handoff?.resumeAndTakeLatest() { publish(pending) }
        workerGate?.resume()
        decoderControl?.resume()
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

    private func restartCause(
        for discontinuity: LiveAudioMeterPlaybackDiscontinuity
    ) -> RestartCause {
        switch discontinuity {
        case .seek, .frameStep, .scrub: .seek
        case .loopWrap: .loopWrap
        case .geometryReload: .geometryReload
        case .sourceReplacement, .audioTrackReplacement: .sourceReplacement
        }
    }
}

private extension LiveAudioMeterDecodeRequest {
    func hasSameSource(as other: Self) -> Bool {
        url == other.url
            && audioStreamOrderIndex == other.audioStreamOrderIndex
            && format == other.format
    }

    func repositioned(at playbackTime: TimeInterval) throws -> Self {
        guard playbackTime.isFinite, playbackTime >= 0 else {
            throw LiveAudioMeterDecoder.Failure.invalidStartPosition
        }
        let frameValue = (playbackTime * Double(format.sampleRate)).rounded()
        guard frameValue.isFinite, frameValue < Double(Int64.max) else {
            throw LiveAudioMeterDecoder.Failure.invalidStartPosition
        }
        let frame = Int64(frameValue)
        return try Self(
            url: url,
            audioStreamOrderIndex: audioStreamOrderIndex,
            format: format,
            startSourceFrame: frame,
            startSourceTime: Double(frame) / Double(format.sampleRate)
        )
    }
}

/// One-slot, post-DSP handoff. Submitting replaces only an unpublished UI
/// snapshot; the decoder has already synchronously processed every PCM sample.
nonisolated private final class SnapshotHandoff: @unchecked Sendable {
    enum Submission: Sendable {
        case scheduleDrain
        case noDrain
        case rejected(LiveAudioMeterDisplayError)
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var reducer: SnapshotReducer
    private nonisolated(unsafe) var pending: LiveAudioMeterReducedSnapshot?
    private nonisolated(unsafe) var drainScheduled = false
    private nonisolated(unsafe) var isValid = true
    private nonisolated(unsafe) var isSuspended = false
    private nonisolated(unsafe) var storedRejection: LiveAudioMeterDisplayError?

    init(format: LiveAudioMeterFormat) {
        reducer = SnapshotReducer(format: format)
    }

    /// Requests a main-actor drain only for valid snapshots. Invalid levels or
    /// positions are retained as an explicit generation failure so completion
    /// and cancellation races cannot conceal the original fault.
    func submit(_ snapshot: LiveAudioMeterSnapshot) -> Submission {
        lock.withLock {
            guard isValid else { return .noDrain }
            let reduced: LiveAudioMeterReducedSnapshot
            do {
                reduced = try reducer.consume(snapshot)
            } catch let error as LiveAudioMeterDisplayError {
                isValid = false
                pending = nil
                drainScheduled = false
                storedRejection = error
                return .rejected(error)
            } catch {
                isValid = false
                pending = nil
                drainScheduled = false
                storedRejection = .invalidLevel
                return .rejected(.invalidLevel)
            }
            pending = reduced
            guard !isSuspended else { return .noDrain }
            guard !drainScheduled else { return .noDrain }
            drainScheduled = true
            return .scheduleDrain
        }
    }

    var rejection: LiveAudioMeterDisplayError? {
        lock.withLock { storedRejection }
    }

    func suspend() {
        lock.withLock { isSuspended = true }
    }

    func clearMaxima() {
        lock.withLock {
            reducer.clearMaxima()
            pending = pending?.clearingMaxima()
        }
    }

    func resumeAndTakeLatest() -> LiveAudioMeterReducedSnapshot? {
        lock.withLock {
            guard isValid else { return nil }
            isSuspended = false
            defer { pending = nil; drainScheduled = false }
            return pending
        }
    }

    func takeLatest() -> LiveAudioMeterReducedSnapshot? {
        lock.withLock {
            guard isValid else { return nil }
            guard !isSuspended else {
                drainScheduled = false
                return nil
            }
            defer { pending = nil; drainScheduled = false }
            return pending
        }
    }

    func invalidateAndTakeLatest() -> LiveAudioMeterReducedSnapshot? {
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

/// Decoder-thread state which applies display ballistics to every source-time
/// bucket before the UI handoff is allowed to replace an older pending value.
nonisolated private struct SnapshotReducer: Sendable {
    private var sampleDisplays: [LiveAudioPeakDisplay]
    private var trueDisplays: [LiveAudioPeakDisplay]
    private var sampleMaxima: [Double?]
    private var trueMaxima: [Double?]
    private var maximumMomentary: Double?
    private var maximumShortTerm: Double?

    init(format: LiveAudioMeterFormat) {
        sampleDisplays = (0..<format.channelCount).map { _ in
            try! LiveAudioPeakDisplay(sampleRate: Double(format.sampleRate))
        }
        trueDisplays = sampleDisplays
        sampleMaxima = .init(repeating: nil, count: format.channelCount)
        trueMaxima = sampleMaxima
    }

    mutating func consume(_ snapshot: LiveAudioMeterSnapshot) throws -> LiveAudioMeterReducedSnapshot {
        guard snapshot.samplePeakDBFS.count == sampleDisplays.count,
              snapshot.truePeakDBTP.count == trueDisplays.count else {
            throw LiveAudioMeterDisplayError.invalidLevel
        }
        for channel in sampleDisplays.indices {
            try Self.consumePeak(
                snapshot.samplePeakDBFS[channel],
                position: snapshot.endFrame,
                isFinal: snapshot.isFinal,
                display: &sampleDisplays[channel]
            )
            try Self.consumePeak(
                snapshot.truePeakDBTP[channel],
                position: snapshot.endFrame,
                isFinal: snapshot.isFinal,
                display: &trueDisplays[channel]
            )
            sampleMaxima[channel] = Self.maximum(sampleMaxima[channel], snapshot.samplePeakDBFS[channel])
            trueMaxima[channel] = Self.maximum(trueMaxima[channel], snapshot.truePeakDBTP[channel])
        }
        maximumMomentary = Self.maximum(maximumMomentary, snapshot.momentaryLUFS)
        maximumShortTerm = Self.maximum(maximumShortTerm, snapshot.shortTermLUFS)
        return LiveAudioMeterReducedSnapshot(
            measurement: snapshot,
            samplePeaks: sampleDisplays.indices.map { channel in
                levelState(
                    current: snapshot.samplePeakDBFS[channel],
                    display: sampleDisplays[channel],
                    maximum: sampleMaxima[channel]
                )
            },
            truePeaks: trueDisplays.indices.map { channel in
                levelState(
                    current: snapshot.truePeakDBTP[channel],
                    display: trueDisplays[channel],
                    maximum: trueMaxima[channel]
                )
            },
            loudness: .init(
                momentary: snapshot.momentaryLUFS,
                maximumMomentary: maximumMomentary,
                shortTerm: snapshot.shortTermLUFS,
                maximumShortTerm: maximumShortTerm
            )
        )
    }

    mutating func clearMaxima() {
        sampleMaxima = .init(repeating: nil, count: sampleMaxima.count)
        trueMaxima = .init(repeating: nil, count: trueMaxima.count)
        maximumMomentary = nil
        maximumShortTerm = nil
    }

    private func levelState(
        current: Double,
        display: LiveAudioPeakDisplay,
        maximum: Double?
    ) -> LiveAudioMeterLevelState {
        .init(current: current, bar: display.bar, marker: display.marker, maximum: maximum)
    }

    private static func consumePeak(
        _ level: Double,
        position: Int64,
        isFinal: Bool,
        display: inout LiveAudioPeakDisplay
    ) throws {
        if isFinal, display.sourceSamplePosition == position {
            try display.reviseFinalPeak(level: level, sourceSamplePosition: position)
        } else {
            try display.consume(level: level, sourceSamplePosition: position)
        }
    }

    private static func maximum(_ previous: Double?, _ next: Double?) -> Double? {
        guard let next else { return previous }
        return max(previous ?? -.infinity, next)
    }
}
