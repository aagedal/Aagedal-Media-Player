// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LiveAudioMeterCoordinatorTests: XCTestCase {
    func testRestartRejectsStaleSnapshotsCompletionsAndErrors() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let first = try request(stream: 0, startFrame: 0)
        let second = try request(stream: 1, startFrame: 4_800)
        coordinator.start(first)
        await decoder.waitUntilAttached(stream: 0)
        let firstGeneration = coordinator.generation

        coordinator.restart(second, because: .sourceReplacement)
        await decoder.waitUntilAttached(stream: 1)
        XCTAssertGreaterThan(coordinator.generation, firstGeneration)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        decoder.fail(TestFailure.oldGeneration, stream: 0)
        decoder.emit(snapshot(endFrame: 7_200, segmentStart: 4_800), stream: 1)
        await eventually { coordinator.snapshot?.endFrame == 7_200 }

        XCTAssertEqual(coordinator.snapshot?.segmentStartFrame, 4_800)
        XCTAssertNotEqual(coordinator.status, .unavailable(
            reason: "Live source audio is unavailable.", diagnostic: TestFailure.oldGeneration.localizedDescription
        ))
        decoder.finish(completion(for: second, finalFrame: 9_600), stream: 1)
        await eventually { coordinator.status == .ended(frame: 9_600) }
        XCTAssertEqual(coordinator.provenance?.request, second)
    }

    func testSnapshotHandoffCoalescesAfterDSPWithoutGrowingPresentationQueue() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let request = try request(stream: 0, startFrame: 0)
        coordinator.start(request)
        await decoder.waitUntilAttached(stream: 0)

        for frame in 1...100 {
            decoder.emit(snapshot(endFrame: Int64(frame * 2_400)), stream: 0)
        }
        await eventually { coordinator.snapshot?.endFrame == 240_000 }

        XCTAssertEqual(coordinator.publishedSnapshotCount, 1)
        XCTAssertEqual(coordinator.status, .active(frame: 240_000))
        decoder.finish(completion(for: request, finalFrame: 240_000), stream: 0)
        await eventually { coordinator.status == .ended(frame: 240_000) }
    }

    func testCoalescedSnapshotsRetainIntermediateTransientBallistics() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)

        decoder.emit(snapshot(endFrame: 2_400, peak: 0), stream: 0)
        decoder.emit(snapshot(endFrame: 4_800, peak: -80), stream: 0)
        await eventually { coordinator.reducedSnapshot?.measurement.endFrame == 4_800 }

        XCTAssertEqual(coordinator.publishedSnapshotCount, 1)
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].current, -80)
        XCTAssertEqual(try XCTUnwrap(coordinator.reducedSnapshot?.samplePeaks[0].bar), -1, accuracy: 0.000_001)
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].marker, 0)
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].maximum, 0)
        coordinator.close()
    }

    func testClearMaximaPreservesBarsAndRebasesSubsequentMaxima() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400, peak: -3), stream: 0)
        await eventually { coordinator.reducedSnapshot != nil }
        let bar = coordinator.reducedSnapshot?.samplePeaks[0].bar
        let generation = coordinator.generation

        coordinator.clearMaxima()

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].bar, bar)
        XCTAssertNil(coordinator.reducedSnapshot?.samplePeaks[0].maximum)

        let staleFinal = snapshot(endFrame: 2_400, segmentStart: 0, isFinal: true)
        decoder.emitPreservingRevision(staleFinal, stream: 0)
        await eventually { coordinator.reducedSnapshot?.measurement.isFinal == true }
        XCTAssertNil(
            coordinator.reducedSnapshot?.samplePeaks[0].maximum,
            "An in-flight pre-clear EOF revision must not relatch an old maximum"
        )

        decoder.emit(snapshot(endFrame: 4_800, peak: -.infinity), stream: 0)
        await eventually { coordinator.reducedSnapshot?.measurement.endFrame == 4_800 }
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].maximum, -.infinity)

        decoder.emit(snapshot(endFrame: 7_200, peak: -12), stream: 0)
        await eventually { coordinator.reducedSnapshot?.measurement.endFrame == 7_200 }
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].maximum, -12)
        XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].marker, -3)
        coordinator.close()
    }

    func testRetryAndManualResetUseCurrentPlaybackClock() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)

        XCTAssertTrue(coordinator.retry(at: 2.25))
        await decoder.waitUntilAttached(stream: 0, occurrence: 2)
        XCTAssertEqual(decoder.request(stream: 0, occurrence: 2)?.startSourceFrame, 108_000)
        XCTAssertEqual(coordinator.restartCause, .retry)

        XCTAssertTrue(coordinator.reset(at: 4.5))
        await decoder.waitUntilAttached(stream: 0, occurrence: 3)
        XCTAssertEqual(decoder.request(stream: 0, occurrence: 3)?.startSourceFrame, 216_000)
        XCTAssertEqual(coordinator.restartCause, .manualReset)
        coordinator.close()
    }

    func testTypedSeekRestartsWhileTrackReplacementRequiresNewIdentity() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)

        coordinator.handlePlaybackEvent(.discontinuity(
            .seek, snapshot: playback(time: 3, playing: true)
        ))
        await decoder.waitUntilAttached(stream: 0, occurrence: 2)
        XCTAssertEqual(decoder.request(stream: 0, occurrence: 2)?.startSourceFrame, 144_000)
        XCTAssertEqual(coordinator.restartCause, .seek)

        coordinator.handlePlaybackEvent(.discontinuity(
            .audioTrackReplacement, snapshot: playback(time: 3, playing: true)
        ))
        guard case .unavailable(let reason, _) = coordinator.status else {
            return XCTFail("Expected source replacement to invalidate the old request")
        }
        XCTAssertEqual(reason, "The measured audio source changed.")
    }

    func testPausedSeekImmediatelySuspendsReplacementGenerationAtNewClock() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)

        coordinator.handlePlaybackEvent(.discontinuity(
            .seek, snapshot: playback(time: 3, playing: false)
        ))
        await decoder.waitUntilAttached(stream: 0, occurrence: 2)

        XCTAssertEqual(coordinator.status, .paused(frame: 144_000))
        let gate = try XCTUnwrap(decoder.gate(stream: 0))
        XCTAssertEqual(gate.permittedEndFrame, 156_000)
        let capacityReturned = LockedFlag()
        let capacityTask = Task.detached {
            let capacity = try gate.waitForByteCapacity(
                processedEndFrame: 144_000,
                pendingByteCount: 0,
                bytesPerFrame: 2 * MemoryLayout<Float>.size
            )
            capacityReturned.set()
            return capacity
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(capacityReturned.value)

        coordinator.updatePlaybackClock(playback(time: 3, playing: true))
        let capacity = try await capacityTask.value
        XCTAssertEqual(capacity, 12_000 * 2 * MemoryLayout<Float>.size)
        XCTAssertTrue(capacityReturned.value)
        coordinator.close()
    }

    func testStartupWithoutPCMUsesBoundedCatchUpAndCancelsStalledWorker() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let startFrame: Int64 = 480_000
        coordinator.start(try request(stream: 0, startFrame: startFrame))
        await decoder.waitUntilAttached(stream: 0)
        let generation = coordinator.generation

        // A clock observation at the requested position is not proof that the
        // decoder has produced PCM. Keep the full existing startup allowance.
        coordinator.updatePlaybackClock(playback(time: 10, playing: true))
        coordinator.updatePlaybackClock(playback(time: 12, playing: true))
        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(coordinator.status, .warmingUp(
            frame: startFrame, momentaryReady: false, shortTermReady: false
        ))
        XCTAssertNil(coordinator.snapshot)
        XCTAssertTrue(decoder.isActive(stream: 0))

        coordinator.updatePlaybackClock(playback(time: 12.01, playing: true))

        guard case .unavailable(let reason, _) = coordinator.status else {
            return XCTFail("Expected a decoder with no PCM to exhaust the startup allowance")
        }
        XCTAssertEqual(reason, "Live meters lost synchronization with playback.")
        let failure = try XCTUnwrap(coordinator.clockFailureContext)
        XCTAssertEqual(failure.requestStartFrame, startFrame)
        XCTAssertEqual(failure.decodedEndFrame, startFrame)
        XCTAssertEqual(failure.publishedSnapshotCount, 0)
        XCTAssertFalse(failure.hadEstablishedSynchronization)
        await decoder.waitUntilCancelled(stream: 0)

        let failedGeneration = coordinator.generation
        coordinator.updatePlaybackClock(playback(time: 12.1, playing: true))
        XCTAssertEqual(coordinator.generation, failedGeneration)
        XCTAssertEqual(coordinator.clockFailureContext, failure)
        coordinator.close()
    }

    func testStartupCanPublishFirstPCMThenEstablishSynchronization() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        let generation = coordinator.generation

        coordinator.updatePlaybackClock(playback(time: 0, playing: true))
        coordinator.updatePlaybackClock(playback(time: 0.5, playing: true))
        decoder.emit(snapshot(endFrame: 24_000), stream: 0)
        coordinator.updatePlaybackClock(playback(time: 0.5, playing: true))

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(coordinator.snapshot?.endFrame, 24_000)
        XCTAssertEqual(coordinator.status, .warmingUp(
            frame: 24_000, momentaryReady: true, shortTermReady: false
        ))
        XCTAssertEqual(coordinator.clockDrift, 0)

        coordinator.updatePlaybackClock(playback(time: 0.76, playing: true))
        XCTAssertTrue(try XCTUnwrap(coordinator.clockFailureContext).hadEstablishedSynchronization)
        await decoder.waitUntilCancelled(stream: 0)
        coordinator.close()
    }

    func testStartupRejectsInvalidPlayingClockBeforeFirstPCM() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)

        coordinator.updatePlaybackClock(playback(time: .nan, playing: true))

        guard case .unavailable(let reason, _) = coordinator.status else {
            return XCTFail("Expected an invalid startup clock to invalidate the worker")
        }
        XCTAssertEqual(reason, "The playback clock is unavailable.")
        XCTAssertNil(coordinator.snapshot)
        await decoder.waitUntilCancelled(stream: 0)
        coordinator.close()
    }

    func testPausedClockLossClearsReadingsAndCancelsSuspendedWorker() async throws {
        try await assertSuspendedClockLoss(buffering: false)
    }

    func testBufferingClockLossClearsReadingsAndCancelsSuspendedWorker() async throws {
        try await assertSuspendedClockLoss(buffering: true)
    }

    func testValidPausedAndBufferingClocksPreserveReadingsUntilContiguousResume() async throws {
        for buffering in [false, true] {
            let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
            let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
            coordinator.start(try request(stream: 0, startFrame: 0))
            await decoder.waitUntilAttached(stream: 0)
            coordinator.updatePlaybackClock(playback(
                time: 0, playing: buffering, phase: buffering ? .buffering : .ready
            ))
            XCTAssertEqual(coordinator.status, buffering ? .buffering(frame: 0) : .paused(frame: 0))

            coordinator.updatePlaybackClock(playback(time: 0, playing: true))
            decoder.emit(snapshot(endFrame: 2_400, peak: -3), stream: 0)
            await eventually { coordinator.snapshot?.endFrame == 2_400 }
            let generation = coordinator.generation
            let reading = coordinator.reducedSnapshot
            coordinator.updatePlaybackClock(playback(
                time: 0.05, playing: buffering, phase: buffering ? .buffering : .ready
            ))

            // A callback already in flight may finish after suspension. Its
            // reading stays hidden until the contiguous source clock resumes.
            decoder.emit(snapshot(endFrame: 4_800, peak: -12), stream: 0)
            await Task.yield()
            XCTAssertEqual(coordinator.generation, generation)
            XCTAssertEqual(coordinator.reducedSnapshot, reading)
            XCTAssertEqual(coordinator.status, buffering ? .buffering(frame: 2_400) : .paused(frame: 2_400))
            XCTAssertTrue(decoder.isActive(stream: 0))

            coordinator.updatePlaybackClock(playback(time: 0.1, playing: true))
            XCTAssertEqual(coordinator.generation, generation)
            XCTAssertEqual(coordinator.snapshot?.endFrame, 4_800)
            XCTAssertEqual(coordinator.reducedSnapshot?.samplePeaks[0].maximum, -3)
            XCTAssertEqual(coordinator.clockDrift, 0)
            coordinator.close()
            await decoder.waitUntilCancelled(stream: 0)
        }
    }

    private func assertSuspendedClockLoss(buffering: Bool) async throws {
        for hasPCM in [false, true] {
            for invalidTime in [Double.nan, .infinity, -.infinity, -0.01, .greatestFiniteMagnitude] {
                let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
                let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
                coordinator.start(try request(stream: 0, startFrame: 0))
                await decoder.waitUntilAttached(stream: 0)
                if hasPCM {
                    decoder.emit(snapshot(endFrame: 2_400), stream: 0)
                    await eventually { coordinator.snapshot?.endFrame == 2_400 }
                }
                coordinator.updatePlaybackClock(playback(
                    time: hasPCM ? 0.05 : 0, playing: buffering,
                    phase: buffering ? .buffering : .ready
                ))
                let suspendedGeneration = coordinator.generation

                coordinator.updatePlaybackClock(playback(
                    time: invalidTime, playing: buffering,
                    phase: buffering ? .buffering : .ready
                ))

                XCTAssertEqual(coordinator.status, .unavailable(
                    reason: "The playback clock is unavailable.",
                    diagnostic: "Retry after the player reports a finite source position."
                ))
                XCTAssertGreaterThan(coordinator.generation, suspendedGeneration)
                XCTAssertNil(coordinator.snapshot)
                XCTAssertNil(coordinator.reducedSnapshot)
                XCTAssertNil(coordinator.clockDrift)
                await decoder.waitUntilCancelled(stream: 0)
                XCTAssertEqual(decoder.activeCount, 0)

                // Queued clocks must not resurrect readings from the rejected
                // segment. Explicit recovery creates a fresh current segment.
                let failedGeneration = coordinator.generation
                coordinator.updatePlaybackClock(playback(time: 0.1, playing: true))
                XCTAssertEqual(coordinator.generation, failedGeneration)
                XCTAssertNil(coordinator.snapshot)
                XCTAssertTrue(coordinator.retry(at: 0.1))
                await decoder.waitUntilAttached(stream: 0, occurrence: 2)
                XCTAssertEqual(decoder.request(stream: 0, occurrence: 2)?.startSourceFrame, 4_800)
                coordinator.close()
            }
        }
    }

    func testInitialClockLagCanCatchUpBeforeSteadyStateDriftFails() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        await eventually { coordinator.reducedSnapshot != nil }

        coordinator.updatePlaybackClock(playback(time: 0.31, playing: true))

        guard case .warmingUp = coordinator.status else {
            return XCTFail("Expected the cold decoder to catch up without losing its generation")
        }
        XCTAssertNotNil(coordinator.snapshot)

        decoder.emit(snapshot(endFrame: 14_400), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 14_400 }
        coordinator.updatePlaybackClock(playback(time: 0.31, playing: true))
        XCTAssertEqual(try XCTUnwrap(coordinator.clockDrift), -0.01, accuracy: 0.000_001)

        coordinator.updatePlaybackClock(playback(time: 0.56, playing: true))

        guard case .unavailable(let reason, let diagnostic) = coordinator.status else {
            return XCTFail("Expected excessive lag after synchronization to invalidate the segment")
        }
        XCTAssertEqual(reason, "Live meters lost synchronization with playback.")
        XCTAssertTrue(diagnostic?.contains("-260.0 ms") == true)
        XCTAssertNil(coordinator.snapshot)
        await decoder.waitUntilCancelled(stream: 0)
    }

    func testPlaybackClockAssessesNewestReducedSnapshotBeforeScheduledPresentationDrain() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 4_800), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 4_800 }
        coordinator.updatePlaybackClock(playback(time: 0.1, playing: true))
        let generation = coordinator.generation

        // Submit a fresh DSP bucket, then deliver the clock synchronously on
        // this main-actor turn before its scheduled presentation task can run.
        // The published endpoint is 300 ms behind; the reduced endpoint is
        // only 100 ms behind and remains inside the unchanged freshness bound.
        decoder.emit(snapshot(endFrame: 14_400), stream: 0)
        XCTAssertEqual(coordinator.snapshot?.endFrame, 4_800)
        coordinator.updatePlaybackClock(playback(time: 0.4, playing: true))

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(coordinator.snapshot?.endFrame, 14_400)
        XCTAssertEqual(try XCTUnwrap(coordinator.clockDrift), -0.1, accuracy: 0.000_001)
        XCTAssertNil(coordinator.clockFailureContext)
        XCTAssertTrue(decoder.isActive(stream: 0))
        let publicationCount = coordinator.publishedSnapshotCount
        await Task.yield()
        XCTAssertEqual(coordinator.publishedSnapshotCount, publicationCount)
        coordinator.close()
    }

    func testPendingMalformedSnapshotWinsRaceWithPlaybackClockFailure() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 4_800), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 4_800 }
        coordinator.updatePlaybackClock(playback(time: 0.1, playing: true))

        // The duplicate source endpoint rejects the handoff synchronously.
        // Deliver a late clock before its queued failure task can present it;
        // that clock must not replace the specific producer error with drift.
        decoder.emit(snapshot(endFrame: 4_800), stream: 0)
        coordinator.updatePlaybackClock(playback(time: 0.4, playing: true))

        guard case .unavailable(let reason, let diagnostic) = coordinator.status else {
            return XCTFail("Expected the pending source-endpoint rejection")
        }
        XCTAssertEqual(reason, "Live source audio is unavailable.")
        XCTAssertTrue(diagnostic?.contains("gap, duplicate, or out-of-order") == true)
        XCTAssertNil(coordinator.clockFailureContext)
        XCTAssertNil(coordinator.snapshot)
        await decoder.waitUntilCancelled(stream: 0)
        coordinator.close()
    }

    func testClockFailureRetainsRejectedSegmentContextWithoutKeepingReadingOrWorker() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 6_424_320))
        await decoder.waitUntilAttached(stream: 0)
        let generation = coordinator.generation
        decoder.emit(snapshot(endFrame: 6_429_120, segmentStart: 6_424_320), stream: 0)
        await eventually { coordinator.snapshot != nil }
        coordinator.updatePlaybackClock(playback(time: 133.95, playing: true))
        let publicationCount = coordinator.publishedSnapshotCount

        coordinator.updatePlaybackClock(playback(time: 134.20, playing: true))

        let failure = try XCTUnwrap(coordinator.clockFailureContext)
        XCTAssertEqual(failure.generation, generation)
        XCTAssertEqual(failure.requestStartFrame, 6_424_320)
        XCTAssertEqual(failure.decodedEndFrame, 6_429_120)
        XCTAssertEqual(failure.playbackTime, 134.20)
        XCTAssertEqual(failure.drift, -0.26, accuracy: 0.000_001)
        XCTAssertEqual(failure.publishedSnapshotCount, publicationCount)
        XCTAssertTrue(failure.hadEstablishedSynchronization)
        XCTAssertFalse(failure.wasSuspendedAhead)
        // 134.20's binary representation lies just below the exact source
        // frame. The existing gate floors it before adding the 12,000-frame
        // allowance, so diagnostic retention must preserve that strict bound.
        XCTAssertEqual(failure.permittedEndFrame, 6_453_599)
        XCTAssertNil(coordinator.snapshot)
        XCTAssertNil(coordinator.reducedSnapshot)
        XCTAssertNil(coordinator.clockDrift)
        await decoder.waitUntilCancelled(stream: 0)

        // A queued callback from the invalidated worker cannot overwrite the
        // rejected endpoint, and the next segment must not inherit it.
        decoder.emit(snapshot(endFrame: 6_436_320, segmentStart: 6_424_320), stream: 0)
        await Task.yield()
        XCTAssertEqual(coordinator.clockFailureContext, failure)
        XCTAssertTrue(coordinator.retry(at: 134.20))
        XCTAssertNil(coordinator.clockFailureContext)
        coordinator.close()
    }

    func testWorkerGateTracksPlaybackClockAndCancelsWithGeneration() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        let oldGate = try XCTUnwrap(decoder.gate(stream: 0))
        XCTAssertEqual(oldGate.permittedEndFrame, 0)

        coordinator.updatePlaybackClock(playback(time: 1, playing: true))
        XCTAssertEqual(oldGate.permittedEndFrame, 60_000)

        coordinator.restart(try request(stream: 1, startFrame: 48_000), because: .seek)
        XCTAssertThrowsError(try oldGate.waitForByteCapacity(
            processedEndFrame: 60_000,
            pendingByteCount: 0,
            bytesPerFrame: 2 * MemoryLayout<Float>.size
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        coordinator.close()
    }

    func testUnsupportedSpeedInvalidatesOnceAndRestartsAtRestoredClock() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        let unsupported = LiveAudioMeterPlaybackSnapshot(
            time: 1, phase: .ready, isPlaying: true, rate: 2, preparationID: 1
        )

        coordinator.updatePlaybackClock(unsupported)
        let suspendedGeneration = coordinator.generation
        coordinator.updatePlaybackClock(unsupported)
        XCTAssertEqual(coordinator.generation, suspendedGeneration)

        coordinator.updatePlaybackClock(playback(time: 2.5, playing: true))
        await decoder.waitUntilAttached(stream: 0, occurrence: 2)
        XCTAssertEqual(decoder.request(stream: 0, occurrence: 2)?.startSourceFrame, 120_000)
        XCTAssertEqual(coordinator.restartCause, .speedRestored)
        coordinator.close()
    }

    func testReplacementAtUnsupportedSpeedCannotReviveRetainedSourceAtOneTimes() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        let unsupported = LiveAudioMeterPlaybackSnapshot(
            time: 1, phase: .ready, isPlaying: true, rate: 2, preparationID: 1
        )

        coordinator.updatePlaybackClock(unsupported)
        await decoder.waitUntilCancelled(stream: 0)
        coordinator.handlePlaybackEvent(.discontinuity(
            .audioTrackReplacement, snapshot: unsupported
        ))
        let replacementGeneration = coordinator.generation

        coordinator.updatePlaybackClock(playback(time: 2.5, playing: true))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(coordinator.generation, replacementGeneration)
        XCTAssertNil(
            decoder.request(stream: 0, occurrence: 2),
            "Returning to 1x must not restart the pre-replacement stream identity"
        )
        XCTAssertFalse(coordinator.retry(at: 2.5))
        guard case .unavailable(let reason, _) = coordinator.status else {
            return XCTFail("Expected replacement to remain unavailable until a new source resolves")
        }
        XCTAssertEqual(reason, "The measured audio source changed.")

        let replacement = try request(stream: 1, startFrame: 120_000)
        coordinator.restart(replacement, because: .sourceReplacement)
        await decoder.waitUntilAttached(stream: 1)
        XCTAssertEqual(decoder.request(stream: 1, occurrence: 1), replacement)
        coordinator.close()
    }

    func testPauseAndBufferingFreezeThenResumeContinuousGeneration() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let initial = try request(stream: 0, startFrame: 0)
        coordinator.start(initial)
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 2_400 }

        let runningGeneration = coordinator.generation
        decoder.emit(snapshot(endFrame: 3_600), stream: 0)
        coordinator.pause()
        let suspendedGeneration = coordinator.generation
        XCTAssertEqual(suspendedGeneration, runningGeneration)
        XCTAssertEqual(coordinator.status, .paused(frame: 2_400))
        decoder.emit(snapshot(endFrame: 4_800), stream: 0)
        await Task.yield()
        XCTAssertEqual(coordinator.status, .paused(frame: 2_400))
        XCTAssertEqual(coordinator.snapshot?.endFrame, 2_400)

        coordinator.markBuffering()
        XCTAssertEqual(coordinator.status, .buffering(frame: 2_400))
        XCTAssertEqual(coordinator.generation, suspendedGeneration)
        let resumed = try request(stream: 0, startFrame: 2_400)
        coordinator.resume(resumed)
        XCTAssertEqual(coordinator.generation, suspendedGeneration)
        XCTAssertEqual(coordinator.restartCause, .initial)
        XCTAssertEqual(coordinator.status, .warmingUp(
            frame: 4_800, momentaryReady: false, shortTermReady: false
        ))
        XCTAssertEqual(coordinator.snapshot?.endFrame, 4_800)
        decoder.finish(completion(for: initial, finalFrame: 48_000), stream: 0)
        await eventually { coordinator.status == .ended(frame: 48_000) }
    }

    func testPlaybackEOFKeepsDecoderDrainRunningAcrossTrailingTransportTicks() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let request = try request(stream: 0, startFrame: 0)
        coordinator.start(request)
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 144_000), stream: 0)
        await eventually { coordinator.status == .active(frame: 144_000) }
        let generation = coordinator.generation
        let gate = try XCTUnwrap(decoder.gate(stream: 0))

        coordinator.handlePlaybackEvent(.ended(playback(time: 3, playing: false)))
        coordinator.handlePlaybackEvent(.transport(playback(time: 3, playing: false)))
        coordinator.handlePlaybackEvent(.clock(.init(
            time: 3, phase: .buffering, isPlaying: false, rate: 1, preparationID: 1
        )))

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(coordinator.status, .active(frame: 144_000))
        let capacityReturned = LockedFlag()
        let capacityTask = Task.detached {
            do {
                _ = try gate.waitForByteCapacity(
                    processedEndFrame: 144_000,
                    pendingByteCount: 0,
                    bytesPerFrame: 2 * MemoryLayout<Float>.size
                )
                capacityReturned.set()
            } catch {}
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(
            capacityReturned.value,
            "Pause/buffering publications after playback EOF must not suspend decoder drainage"
        )

        decoder.finish(completion(for: request, finalFrame: 144_000), stream: 0)
        await eventually { coordinator.status == .ended(frame: 144_000) }
        await capacityTask.value
    }

    func testInvalidPlaybackEOFClockClearsReadingsAndCancelsWorker() async throws {
        try await assertEOFClockLoss(afterValidEOF: false)
    }

    func testClockLossDuringPlaybackEOFDrainClearsReadingsAndCancelsWorker() async throws {
        try await assertEOFClockLoss(afterValidEOF: true)
    }

    private func assertEOFClockLoss(afterValidEOF: Bool) async throws {
        for invalidTime in [Double.nan, .infinity, -.infinity, -0.01, .greatestFiniteMagnitude] {
            let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
            let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
            coordinator.start(try request(stream: 0, startFrame: 0))
            await decoder.waitUntilAttached(stream: 0)
            decoder.emit(snapshot(endFrame: 144_000), stream: 0)
            await eventually { coordinator.status == .active(frame: 144_000) }
            let gate = try XCTUnwrap(decoder.gate(stream: 0))
            if afterValidEOF {
                coordinator.handlePlaybackEvent(.ended(playback(time: 3, playing: false)))
            } else {
                coordinator.pause()
            }
            let generation = coordinator.generation

            if afterValidEOF {
                coordinator.handlePlaybackEvent(.transport(playback(
                    time: invalidTime, playing: false, phase: .buffering
                )))
            } else {
                coordinator.handlePlaybackEvent(.ended(playback(
                    time: invalidTime, playing: false
                )))
            }

            guard case .unavailable(let reason, let diagnostic) = coordinator.status else {
                coordinator.close()
                return XCTFail("Expected EOF clock loss to invalidate the draining worker")
            }
            XCTAssertEqual(reason, "The playback clock is unavailable.")
            XCTAssertEqual(diagnostic, "Retry after the player reports a finite source position.")
            XCTAssertGreaterThan(coordinator.generation, generation)
            XCTAssertNil(coordinator.snapshot)
            XCTAssertNil(coordinator.reducedSnapshot)
            XCTAssertNil(coordinator.provenance)
            await decoder.waitUntilCancelled(stream: 0)
            XCTAssertEqual(decoder.activeCount, 0)
            XCTAssertThrowsError(try gate.waitForByteCapacity(
                processedEndFrame: 144_000,
                pendingByteCount: 0,
                bytesPerFrame: 2 * MemoryLayout<Float>.size
            )) { XCTAssertTrue($0 is CancellationError) }
            // Trailing valid EOF observations must not revive invalidated PCM.
            coordinator.handlePlaybackEvent(.ended(playback(time: 3, playing: false)))
            XCTAssertNil(coordinator.snapshot)
            XCTAssertEqual(coordinator.generation, generation + 1)
            coordinator.close()
        }
    }

    func testDecoderEOFFreezesFinalReadingWhileContainerClockContinues() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let request = try request(stream: 0, startFrame: 0)
        coordinator.start(request)
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 48_000), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 48_000 }
        decoder.finish(completion(for: request, finalFrame: 48_000), stream: 0)
        await eventually { coordinator.status == .ended(frame: 48_000) }
        let generation = coordinator.generation
        let finalSnapshot = coordinator.snapshot
        let provenance = coordinator.provenance

        coordinator.handlePlaybackEvent(.clock(playback(time: 2, playing: true)))
        coordinator.handlePlaybackEvent(.transport(playback(time: 3, playing: true)))

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(coordinator.status, .ended(frame: 48_000))
        XCTAssertEqual(coordinator.snapshot, finalSnapshot)
        XCTAssertEqual(coordinator.provenance, provenance)
        XCTAssertNil(coordinator.clockDrift)
    }

    func testRetryStartsNewGenerationAfterActionableFailure() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let request = try request(stream: 0, startFrame: 0)
        coordinator.start(request)
        await decoder.waitUntilAttached(stream: 0)
        decoder.fail(TestFailure.decode, stream: 0)
        await eventually {
            if case .unavailable = coordinator.status { return true }
            return false
        }
        let failedGeneration = coordinator.generation
        XCTAssertTrue(coordinator.retry())
        await decoder.waitUntilAttached(stream: 0, occurrence: 2)
        XCTAssertGreaterThan(coordinator.generation, failedGeneration)
        XCTAssertEqual(coordinator.restartCause, .retry)
        decoder.finish(completion(for: request, finalFrame: 0), stream: 0)
        await eventually { coordinator.status == .ended(frame: 0) }
    }

    func testMalformedSnapshotFailsGenerationAndCancelsWorker() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 2_400 }

        // Repeating a source endpoint would make display ballistics bridge a
        // duplicate block. It must fail the segment rather than silently
        // invalidating only the UI handoff while decode continues.
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)

        await eventually {
            guard case .unavailable(_, let diagnostic) = coordinator.status else { return false }
            return diagnostic?.contains("gap, duplicate, or out-of-order") == true
        }
        XCTAssertNil(coordinator.snapshot)
        XCTAssertNil(coordinator.reducedSnapshot)
        await decoder.waitUntilCancelled(stream: 0)
        XCTAssertEqual(decoder.activeCount, 0)
    }

    func testMalformedCurrentLoudnessFailsGenerationAndCancelsWorker() async throws {
        for invalidLevel in [Double.nan, Double.infinity] {
            for invalidatesMomentary in [true, false] {
                let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
                let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
                coordinator.start(try request(stream: 0, startFrame: 0))
                await decoder.waitUntilAttached(stream: 0)
                decoder.emit(snapshot(endFrame: 144_000), stream: 0)
                await eventually { coordinator.status == .active(frame: 144_000) }

                // Current loudness must be validated independently of maxima:
                // these malformed readings carry otherwise valid peak values
                // and nil loudness maxima, just as a post-clear bucket can.
                decoder.emit(snapshot(
                    endFrame: 146_400, peak: -12,
                    loudness: invalidatesMomentary ? (invalidLevel, -23) : (-23, invalidLevel)
                ), stream: 0)

                await eventually {
                    guard case .unavailable(_, let diagnostic) = coordinator.status else { return false }
                    return diagnostic?.contains("malformed or non-finite level") == true
                }
                XCTAssertNil(coordinator.snapshot)
                XCTAssertNil(coordinator.reducedSnapshot)
                await decoder.waitUntilCancelled(stream: 0)
                XCTAssertEqual(decoder.activeCount, 0)
                coordinator.close()
            }
        }
    }

    func testSilentCurrentLoudnessRemainsValidAfterMaximaClear() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 144_000), stream: 0)
        await eventually { coordinator.status == .active(frame: 144_000) }
        coordinator.clearMaxima()

        decoder.emit(snapshot(
            endFrame: 146_400, peak: -.infinity,
            loudness: (-.infinity, -.infinity)
        ), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 146_400 }

        XCTAssertEqual(coordinator.status, .active(frame: 146_400))
        XCTAssertEqual(coordinator.reducedSnapshot?.loudness.momentary, -.infinity)
        XCTAssertEqual(coordinator.reducedSnapshot?.loudness.shortTerm, -.infinity)
        XCTAssertNil(coordinator.reducedSnapshot?.loudness.maximumMomentary)
        XCTAssertNil(coordinator.reducedSnapshot?.loudness.maximumShortTerm)
        XCTAssertTrue(decoder.isActive(stream: 0))
        coordinator.close()
        await decoder.waitUntilCancelled(stream: 0)
    }

    func testMalformedSnapshotWinsRaceWithDecoderFailureDiagnostic() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 2_400 }

        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        decoder.fail(TestFailure.decode, stream: 0)

        await eventually {
            guard case .unavailable(_, let diagnostic) = coordinator.status else { return false }
            return diagnostic?.contains("gap, duplicate, or out-of-order") == true
        }
        XCTAssertNil(coordinator.snapshot)
        XCTAssertNil(coordinator.reducedSnapshot)
    }

    func testAllDiscontinuityCausesStartCleanGenerations() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let causes: [LiveAudioMeterCoordinator.RestartCause] = [
            .seek, .loopWrap, .geometryReload, .speedRestored, .sourceReplacement
        ]
        var previous = coordinator.generation
        coordinator.start(try request(stream: 0, startFrame: 0))
        XCTAssertGreaterThan(coordinator.generation, previous)
        previous = coordinator.generation
        for (index, cause) in causes.enumerated() {
            let start = Int64((index + 1) * 4_800)
            coordinator.restart(try request(stream: index + 1, startFrame: start), because: cause)
            XCTAssertGreaterThan(coordinator.generation, previous)
            XCTAssertEqual(coordinator.restartCause, cause)
            XCTAssertNil(coordinator.snapshot)
            XCTAssertEqual(coordinator.status, .warmingUp(
                frame: start, momentaryReady: false, shortTermReady: false
            ))
            previous = coordinator.generation
        }
        coordinator.close()
    }

    func testCancellationBeforeAndAfterDecoderAttachmentCleansWorkers() async throws {
        let before = ControlledLiveMeterDecoder(honorCancellation: true)
        let firstCoordinator = LiveAudioMeterCoordinator(decodeOperation: before.decode)
        firstCoordinator.start(try request(stream: 0, startFrame: 0))
        firstCoordinator.close()
        await before.waitUntilCancelled(stream: 0)
        XCTAssertEqual(before.activeCount, 0)

        let after = ControlledLiveMeterDecoder(honorCancellation: true)
        let secondCoordinator = LiveAudioMeterCoordinator(decodeOperation: after.decode)
        secondCoordinator.start(try request(stream: 1, startFrame: 0))
        await after.waitUntilAttached(stream: 1)
        secondCoordinator.restart(try request(stream: 2, startFrame: 0), because: .sourceReplacement)
        await after.waitUntilCancelled(stream: 1)
        XCTAssertFalse(after.isActive(stream: 1))
        secondCoordinator.close()
    }

    func testClosedCoordinatorRejectsQueuedTransportEventsAndSpeedSuspension() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        coordinator.start(try request(stream: 0, startFrame: 0))
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 2_400 }
        coordinator.close()
        await decoder.waitUntilCancelled(stream: 0)
        let closedGeneration = coordinator.generation
        let closedStatus = coordinator.status

        let observation = playback(time: 3, playing: true)
        var queuedEvents: [LiveAudioMeterPlaybackEvent] = [
            .clock(observation), .transport(observation),
            .scrubbing(observation), .ended(observation),
        ]
        let causes: [LiveAudioMeterPlaybackDiscontinuity] = [
            .seek, .frameStep, .scrub, .loopWrap, .geometryReload,
            .sourceReplacement, .audioTrackReplacement,
        ]
        for cause in causes {
            queuedEvents.append(.discontinuity(cause, snapshot: observation))
        }
        for event in queuedEvents {
            coordinator.handlePlaybackEvent(event)
            XCTAssertEqual(coordinator.generation, closedGeneration)
            XCTAssertEqual(coordinator.status, closedStatus)
        }
        coordinator.suspendForUnsupportedSpeed()
        coordinator.updatePlaybackClock(observation)
        XCTAssertEqual(coordinator.generation, closedGeneration)
        XCTAssertEqual(coordinator.status, closedStatus)
        XCTAssertNil(coordinator.snapshot)
        XCTAssertNil(coordinator.reducedSnapshot)
        XCTAssertNil(coordinator.provenance)
        XCTAssertFalse(coordinator.retry())
        XCTAssertEqual(decoder.activeCount, 0)
    }

    func testDeinitCancelsOwnedWorkerAndLeavesNoOrphan() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: true)
        weak var weakCoordinator: LiveAudioMeterCoordinator?
        do {
            var coordinator: LiveAudioMeterCoordinator? = LiveAudioMeterCoordinator(
                decodeOperation: decoder.decode
            )
            weakCoordinator = coordinator
            coordinator?.start(try request(stream: 4, startFrame: 0))
            await decoder.waitUntilAttached(stream: 4)
            coordinator = nil
        }

        await decoder.waitUntilCancelled(stream: 4)
        XCTAssertNil(weakCoordinator)
        XCTAssertEqual(decoder.activeCount, 0)
    }

    private func request(stream: Int, startFrame: Int64) throws -> LiveAudioMeterDecodeRequest {
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .stereo)
        return try LiveAudioMeterDecodeRequest(
            url: URL(fileURLWithPath: "/tmp/coordinator-\(stream).wav"),
            audioStreamOrderIndex: stream, format: format,
            startSourceFrame: startFrame,
            startSourceTime: Double(startFrame) / Double(format.sampleRate)
        )
    }

    private func snapshot(endFrame: Int64, segmentStart: Int64 = 0) -> LiveAudioMeterSnapshot {
        snapshot(endFrame: endFrame, segmentStart: segmentStart, peak: -12)
    }

    private func snapshot(
        endFrame: Int64,
        segmentStart: Int64 = 0,
        peak: Double,
        loudness: (momentary: Double?, shortTerm: Double?)? = nil
    ) -> LiveAudioMeterSnapshot {
        LiveAudioMeterSnapshot(
            endFrame: endFrame, segmentStartFrame: segmentStart,
            samplePeakDBFS: [peak, peak], truePeakDBTP: [peak + 0.2, peak + 0.2],
            momentaryLUFS: loudness?.momentary ?? (endFrame - segmentStart >= 19_200 ? -23 : nil),
            shortTermLUFS: loudness?.shortTerm ?? (endFrame - segmentStart >= 144_000 ? -23 : nil),
            loudnessEndFrame: nil, maximumSamplePeakDBFS: [peak, peak],
            maximumTruePeakDBTP: [peak + 0.2, peak + 0.2], maximumMomentaryLUFS: nil,
            maximumShortTermLUFS: nil, maximaResetRevision: 0, isFinal: false
        )
    }

    private func playback(
        time: TimeInterval, playing: Bool, phase: PlaybackPhase = .ready
    ) -> LiveAudioMeterPlaybackSnapshot {
        LiveAudioMeterPlaybackSnapshot(
            time: time,
            phase: phase,
            isPlaying: playing,
            rate: 1,
            preparationID: 1
        )
    }

    private func completion(
        for request: LiveAudioMeterDecodeRequest, finalFrame: Int64
    ) -> LiveAudioMeterDecodeCompletion {
        let final = finalFrame > request.startSourceFrame
            ? snapshot(endFrame: finalFrame, segmentStart: request.startSourceFrame, isFinal: true)
            : nil
        return LiveAudioMeterDecodeCompletion(
            provenance: LiveAudioMeterDecodeProvenance(
                request: request, decoderVersion: "ffmpeg version test", arguments: [],
                sampleFormat: "f32le", dynamicRangeCompressionDisabled: true,
                codecNormalizationDisabled: true,
                timestampSource: .ffmpegFrameCRC,
                timestampTimeBase: "1/\(request.format.sampleRate)",
                timestampFrameCount: max(0, finalFrame - request.startSourceFrame),
                syntheticInitialSilenceFrameCount: 0
            ),
            finalSnapshot: final
        )
    }

    private func snapshot(
        endFrame: Int64, segmentStart: Int64, isFinal: Bool
    ) -> LiveAudioMeterSnapshot {
        let value = snapshot(endFrame: endFrame, segmentStart: segmentStart)
        return LiveAudioMeterSnapshot(
            endFrame: value.endFrame, segmentStartFrame: value.segmentStartFrame,
            samplePeakDBFS: value.samplePeakDBFS, truePeakDBTP: value.truePeakDBTP,
            momentaryLUFS: value.momentaryLUFS, shortTermLUFS: value.shortTermLUFS,
            loudnessEndFrame: value.loudnessEndFrame,
            maximumSamplePeakDBFS: value.maximumSamplePeakDBFS,
            maximumTruePeakDBTP: value.maximumTruePeakDBTP,
            maximumMomentaryLUFS: value.maximumMomentaryLUFS,
            maximumShortTermLUFS: value.maximumShortTermLUFS,
            maximaResetRevision: value.maximaResetRevision, isFinal: isFinal
        )
    }

    private func eventually(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }
}

private enum TestFailure: Error { case oldGeneration, decode }

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

private final class ControlledLiveMeterDecoder: @unchecked Sendable {
    private struct Entry {
        let token: UUID
        let onSnapshot: LiveAudioMeterPCMStreamProcessor.SnapshotHandler
        let workerGate: LiveAudioMeterWorkerGate
        let continuation: CheckedContinuation<LiveAudioMeterDecodeCompletion, Error>
    }

    private let lock = NSLock()
    private let honorCancellation: Bool
    private var entries: [Int: [Entry]] = [:]
    private var cancelled: Set<Int> = []
    private var cancelledTokens: Set<UUID> = []
    private var attachmentCounts: [Int: Int] = [:]
    private var requests: [Int: [LiveAudioMeterDecodeRequest]] = [:]

    init(honorCancellation: Bool) { self.honorCancellation = honorCancellation }

    func decode(
        _ request: LiveAudioMeterDecodeRequest,
        control: SubprocessHandle,
        workerGate: LiveAudioMeterWorkerGate,
        onSnapshot: @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
    ) async throws -> LiveAudioMeterDecodeCompletion {
        let stream = request.audioStreamOrderIndex
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var cancelImmediately = false
                lock.withLock {
                    attachmentCounts[stream, default: 0] += 1
                    requests[stream, default: []].append(request)
                    if cancelledTokens.contains(token), honorCancellation {
                        cancelImmediately = true
                    } else {
                        entries[stream, default: []].append(Entry(
                            token: token,
                            onSnapshot: onSnapshot,
                            workerGate: workerGate,
                            continuation: continuation
                        ))
                    }
                }
                if cancelImmediately { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuations: [Entry] = self.lock.withLock {
                self.cancelled.insert(stream)
                self.cancelledTokens.insert(token)
                guard self.honorCancellation else { return [] }
                guard let index = self.entries[stream]?.firstIndex(where: {
                    $0.token == token
                }) else { return [] }
                let entry = self.entries[stream]!.remove(at: index)
                return [entry]
            }
            continuations.forEach { $0.continuation.resume(throwing: CancellationError()) }
        }
    }

    var activeCount: Int { lock.withLock { entries.values.reduce(0) { $0 + $1.count } } }
    func isActive(stream: Int) -> Bool { lock.withLock { entries[stream]?.isEmpty == false } }

    func request(stream: Int, occurrence: Int) -> LiveAudioMeterDecodeRequest? {
        lock.withLock {
            let index = occurrence - 1
            guard index >= 0, requests[stream]?.indices.contains(index) == true else { return nil }
            return requests[stream]?[index]
        }
    }

    func gate(stream: Int) -> LiveAudioMeterWorkerGate? {
        lock.withLock { entries[stream]?.first?.workerGate }
    }

    func emit(_ snapshot: LiveAudioMeterSnapshot, stream: Int) {
        let entry = lock.withLock { entries[stream]?.first }
        entry?.onSnapshot(snapshot.applyingMaximaResetRevision(
            entry?.workerGate.currentMaximaResetRevision ?? 0
        ))
    }

    func emitPreservingRevision(_ snapshot: LiveAudioMeterSnapshot, stream: Int) {
        let callback = lock.withLock { entries[stream]?.first?.onSnapshot }
        callback?(snapshot)
    }

    func finish(_ completion: LiveAudioMeterDecodeCompletion, stream: Int) {
        let entry = lock.withLock { entries[stream]?.isEmpty == false ? entries[stream]!.removeFirst() : nil }
        entry?.continuation.resume(returning: completion)
    }

    func fail(_ error: Error, stream: Int) {
        let entry = lock.withLock { entries[stream]?.isEmpty == false ? entries[stream]!.removeFirst() : nil }
        entry?.continuation.resume(throwing: error)
    }

    func waitUntilAttached(stream: Int, occurrence: Int = 1) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if lock.withLock({ attachmentCounts[stream, default: 0] >= occurrence }) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Decoder stream \(stream) did not attach")
    }

    func waitUntilCancelled(stream: Int) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if lock.withLock({ cancelled.contains(stream) }) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Decoder stream \(stream) was not cancelled")
    }
}
