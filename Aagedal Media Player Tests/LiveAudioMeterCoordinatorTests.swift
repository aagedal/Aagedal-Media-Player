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

    func testPauseAndBufferingFreezeThenResumeAsFreshGeneration() async throws {
        let decoder = ControlledLiveMeterDecoder(honorCancellation: false)
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: decoder.decode)
        let initial = try request(stream: 0, startFrame: 0)
        coordinator.start(initial)
        await decoder.waitUntilAttached(stream: 0)
        decoder.emit(snapshot(endFrame: 2_400), stream: 0)
        await eventually { coordinator.snapshot?.endFrame == 2_400 }

        let runningGeneration = coordinator.generation
        coordinator.pause()
        let suspendedGeneration = coordinator.generation
        XCTAssertGreaterThan(suspendedGeneration, runningGeneration)
        XCTAssertEqual(coordinator.status, .paused(frame: 2_400))
        decoder.emit(snapshot(endFrame: 4_800), stream: 0)
        decoder.finish(completion(for: initial, finalFrame: 48_000), stream: 0)
        await Task.yield()
        XCTAssertEqual(coordinator.status, .paused(frame: 2_400))
        XCTAssertEqual(coordinator.snapshot?.endFrame, 2_400)

        coordinator.markBuffering()
        XCTAssertEqual(coordinator.status, .buffering(frame: 2_400))
        XCTAssertEqual(coordinator.generation, suspendedGeneration)
        let resumed = try request(stream: 0, startFrame: 2_400)
        coordinator.resume(resumed)
        await decoder.waitUntilAttached(stream: 0, occurrence: 2)
        XCTAssertGreaterThan(coordinator.generation, suspendedGeneration)
        XCTAssertEqual(coordinator.restartCause, .resumeAfterSuspension)
        XCTAssertEqual(coordinator.status, .warmingUp(
            frame: 2_400, momentaryReady: false, shortTermReady: false
        ))
        XCTAssertNil(coordinator.snapshot, "A resumed decoder owns a clean DSP segment")
        decoder.finish(completion(for: resumed, finalFrame: 2_400), stream: 0)
        await eventually { coordinator.status == .ended(frame: 2_400) }
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
        LiveAudioMeterSnapshot(
            endFrame: endFrame, segmentStartFrame: segmentStart,
            samplePeakDBFS: [-12, -12], truePeakDBTP: [-11.8, -11.8],
            momentaryLUFS: endFrame - segmentStart >= 19_200 ? -23 : nil,
            shortTermLUFS: endFrame - segmentStart >= 144_000 ? -23 : nil,
            loudnessEndFrame: nil, maximumSamplePeakDBFS: [-12, -12],
            maximumTruePeakDBTP: [-11.8, -11.8], maximumMomentaryLUFS: nil,
            maximumShortTermLUFS: nil, isFinal: false
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
                codecNormalizationDisabled: true
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
            maximumShortTermLUFS: value.maximumShortTermLUFS, isFinal: isFinal
        )
    }

    private func eventually(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }
}

private enum TestFailure: Error { case oldGeneration, decode }

private final class ControlledLiveMeterDecoder: @unchecked Sendable {
    private struct Entry {
        let onSnapshot: LiveAudioMeterPCMStreamProcessor.SnapshotHandler
        let continuation: CheckedContinuation<LiveAudioMeterDecodeCompletion, Error>
    }

    private let lock = NSLock()
    private let honorCancellation: Bool
    private var entries: [Int: [Entry]] = [:]
    private var cancelled: Set<Int> = []
    private var attachmentCounts: [Int: Int] = [:]

    init(honorCancellation: Bool) { self.honorCancellation = honorCancellation }

    func decode(
        _ request: LiveAudioMeterDecodeRequest,
        onSnapshot: @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
    ) async throws -> LiveAudioMeterDecodeCompletion {
        let stream = request.audioStreamOrderIndex
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var cancelImmediately = false
                lock.withLock {
                    attachmentCounts[stream, default: 0] += 1
                    if cancelled.contains(stream), honorCancellation {
                        cancelImmediately = true
                    } else {
                        entries[stream, default: []].append(Entry(
                            onSnapshot: onSnapshot, continuation: continuation
                        ))
                    }
                }
                if cancelImmediately { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuations: [Entry] = self.lock.withLock {
                self.cancelled.insert(stream)
                guard self.honorCancellation else { return [] }
                return self.entries.removeValue(forKey: stream) ?? []
            }
            continuations.forEach { $0.continuation.resume(throwing: CancellationError()) }
        }
    }

    var activeCount: Int { lock.withLock { entries.values.reduce(0) { $0 + $1.count } } }
    func isActive(stream: Int) -> Bool { lock.withLock { entries[stream]?.isEmpty == false } }

    func emit(_ snapshot: LiveAudioMeterSnapshot, stream: Int) {
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
        for _ in 0..<200 {
            if lock.withLock({ attachmentCounts[stream, default: 0] >= occurrence }) { return }
            await Task.yield()
        }
        XCTFail("Decoder stream \(stream) did not attach")
    }

    func waitUntilCancelled(stream: Int) async {
        for _ in 0..<200 {
            if lock.withLock({ cancelled.contains(stream) }) { return }
            await Task.yield()
        }
        XCTFail("Decoder stream \(stream) was not cancelled")
    }
}
