// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import AppKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LiveAudioMeterPerformanceTests: XCTestCase {
    private var retainedMPVLayers: [MPVMetalLayer] = []

    override func tearDown() async throws {
        retainedMPVLayers.removeAll()
        try await super.tearDown()
    }

    private struct ProfileInput: Decodable {
        let path: String
        let sha256: String
    }

    private struct SampledRun {
        let startFrame: Int64
        var endFrame: Int64
        var wallSeconds = 0.0
        var publishedSnapshots = 0
        var firstSnapshotLatency = 0.0
        var maximumSnapshotInterval = 0.0
        var maximumAbsoluteClockDrift = 0.0
        var clockDriftSamples = 0
        var maximumDecodedAhead = 0.0
        var peakAppResident: UInt64
        var peakChildResident: UInt64 = 0
    }

    /// Explicit external inputs keep representative production playback out of
    /// ordinary regression and candidate-verifier runs.
    func testRepresentativeProductionPathWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let encodedInputs = environment["LIVE_AUDIO_METER_PROFILE_INPUTS"] else {
            throw XCTSkip("Set LIVE_AUDIO_METER_PROFILE_INPUTS to run the representative live-meter profile")
        }
        let inputs = try JSONDecoder().decode([ProfileInput].self, from: Data(encodedInputs.utf8))
        XCTAssertFalse(inputs.isEmpty)
        let observationSeconds = Double(environment["LIVE_AUDIO_METER_PROFILE_SECONDS"] ?? "5") ?? 0
        XCTAssertTrue((5...30).contains(observationSeconds))
        guard !inputs.isEmpty, (5...30).contains(observationSeconds) else { return }

        for (inputIndex, input) in inputs.enumerated() {
            let url = URL(fileURLWithPath: input.path)
            let metadata = try await MetadataService.shared.metadata(for: url)
            let duration = try XCTUnwrap(metadata.duration)
            let requiredDuration = max(20, observationSeconds + 10)
            XCTAssertGreaterThanOrEqual(duration, requiredDuration)
            guard duration >= requiredDuration else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let item = MediaItem(
                url: url,
                name: url.lastPathComponent,
                size: size,
                durationSeconds: duration,
                hasVideoStream: !metadata.videoStreams.isEmpty,
                metadata: metadata
            )

            let comparison = CompareSessionController()
            let player = PlayerController()
            defer {
                comparison.stop()
                player.teardown()
            }

            try await load(item, in: player, startTime: 0)
            let source = try player.liveAudioMeterSource(id: "A", label: "Source A")
            let selectedBackend = try XCTUnwrap(player.playbackBackend)
            let baselineChildren = try childResidentBytes()
            XCTAssertEqual(baselineChildren, 0, "The profile test host must not own unrelated child processes")
            let initialResident = try residentBytes()
            let session = LiveAudioMeterSession(
                primary: player,
                comparison: comparison,
                defaults: isolatedDefaults()
            )
            session.start()
            player.play()

            var observation = try await sample(
                player: player,
                session: session,
                startFrame: try source.request(at: 0).startSourceFrame,
                seconds: observationSeconds
            )
            XCTAssertGreaterThanOrEqual(observation.publishedSnapshots, 2)
            XCTAssertGreaterThan(observation.endFrame, observation.startFrame)
            XCTAssertGreaterThan(observation.peakChildResident, 0)
            guard session.coordinator.reducedSnapshot != nil else {
                XCTFail("Live meter lost its measured snapshot before the routing check: \(session.coordinator.status)")
                return
            }

            player.pause()
            try await waitUntil(timeout: 5, description: "paused meter state") {
                if case .paused = session.coordinator.status { return true }
                return false
            }
            let generationBeforeRouting = session.coordinator.generation
            let sourceBeforeRouting = session.selectedSourceID
            let snapshotBeforeRouting = try XCTUnwrap(session.coordinator.reducedSnapshot)
            let oldVolume = player.volume
            let oldMute = player.isMuted
            player.volume = oldVolume == 37 ? 63 : 37
            player.toggleMute()
            player.setAudioSuppressed(true)
            if player.selectedAudioChannelCount > 0 {
                player.toggleAudioChannelMute(0)
                player.toggleAudioChannelMute(0)
            }
            player.setAudioSuppressed(false)
            try await Task.sleep(for: .milliseconds(100))
            let routingInvariant = session.coordinator.generation == generationBeforeRouting
                && session.selectedSourceID == sourceBeforeRouting
                && session.coordinator.reducedSnapshot == snapshotBeforeRouting
            XCTAssertTrue(routingInvariant)
            player.volume = oldVolume
            if player.isMuted != oldMute { player.toggleMute() }
            // MPV reapplies the selected audible track asynchronously when
            // comparison-style suppression is removed. Let that output-only
            // operation settle before asking the transport to resume.
            try await Task.sleep(for: .milliseconds(500))
            player.play()
            try await waitUntil(timeout: 5, description: "meter resume after routing changes") {
                if (session.coordinator.reducedSnapshot?.measurement.endFrame
                    ?? snapshotBeforeRouting.measurement.endFrame)
                    > snapshotBeforeRouting.measurement.endFrame {
                    return true
                }
                if case .unavailable(let reason, let diagnostic) = session.coordinator.status {
                    throw NSError(
                        domain: "LiveAudioMeterPerformanceResume",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "\(reason) \(diagnostic ?? "")"]
                    )
                }
                return false
            }

            let cancellationStart = ContinuousClock.now
            session.close()
            try await waitUntil(timeout: 5, description: "meter FFmpeg cancellation") {
                try self.childResidentBytes() == baselineChildren
            }
            let cancellationLatency = seconds(cancellationStart.duration(to: .now))
            let childrenAfterCancellation = try childResidentBytes()
            XCTAssertLessThanOrEqual(cancellationLatency, 5)
            XCTAssertEqual(childrenAfterCancellation, 0)

            player.teardown()
            let eofWindow = min(6.0, max(4.0, duration / 2))
            let eofStartTime = max(0, duration - eofWindow)
            try await load(item, in: player, startTime: eofStartTime)
            let eofSource = try player.liveAudioMeterSource(id: "A", label: "Source A")
            XCTAssertEqual(eofSource.audioStreamOrderIndex, source.audioStreamOrderIndex)
            XCTAssertEqual(player.playbackBackend, selectedBackend)
            let eofSession = LiveAudioMeterSession(
                primary: player,
                comparison: comparison,
                defaults: isolatedDefaults()
            )
            defer { eofSession.close() }
            eofSession.start()
            player.play()
            let eofWallStart = ContinuousClock.now
            var eofRun = SampledRun(
                startFrame: try eofSource.request(at: eofStartTime).startSourceFrame,
                endFrame: try eofSource.request(at: eofStartTime).startSourceFrame,
                peakAppResident: try residentBytes()
            )
            try await sampleUntilEnded(player: player, session: eofSession, run: &eofRun, timeout: eofWindow + 30)
            let eofWallSeconds = seconds(eofWallStart.duration(to: .now))
            guard case .ended = eofSession.coordinator.status else {
                XCTFail("Production live meter did not reach EOF")
                return
            }
            let provenance = try XCTUnwrap(eofSession.coordinator.provenance)
            let finalSnapshot = try XCTUnwrap(eofSession.coordinator.snapshot)
            XCTAssertTrue(finalSnapshot.isFinal)
            XCTAssertGreaterThan(eofRun.peakChildResident, 0)

            observation.peakAppResident = max(observation.peakAppResident, initialResident)
            let stream = try XCTUnwrap(player.mediaItem?.metadata?.audioStreams.first {
                $0.index == eofSource.metadataStreamIndex
            })
            let report: [String: Any] = [
                "schemaVersion": 1,
                "inputIndex": inputIndex,
                "file": url.lastPathComponent,
                "inputSHA256": input.sha256,
                "durationSeconds": duration,
                "codec": stream.codec ?? "unknown",
                "declaredChannelLayout": stream.channelLayout ?? NSNull(),
                "channels": eofSource.format.channelCount,
                "sampleRate": eofSource.format.sampleRate,
                "metadataStreamIndex": eofSource.metadataStreamIndex
                    ?? eofSource.audioStreamOrderIndex,
                "audioStreamOrderIndex": eofSource.audioStreamOrderIndex,
                "backend": selectedBackend.rawValue,
                "observation": [
                    "startSourceFrame": observation.startFrame,
                    "endSourceFrame": observation.endFrame,
                    "publishedSnapshotCount": observation.publishedSnapshots,
                    "observationSeconds": observationSeconds,
                    "wallSeconds": observation.wallSeconds,
                    "firstSnapshotLatencySeconds": observation.firstSnapshotLatency,
                    "maximumSnapshotIntervalSeconds": observation.maximumSnapshotInterval,
                    "maximumAbsoluteClockDriftSeconds": observation.maximumAbsoluteClockDrift,
                    "clockDriftSampleCount": observation.clockDriftSamples,
                    "maximumDecodedAheadSeconds": observation.maximumDecodedAhead,
                    "initialAppResidentBytes": initialResident,
                    "peakAppResidentBytes": observation.peakAppResident,
                    "peakChildResidentBytes": observation.peakChildResident,
                    "monitorRoutingInvariant": routingInvariant,
                    "cancellationObserved": childrenAfterCancellation == baselineChildren,
                    "cancellationLatencySeconds": cancellationLatency,
                    "childResidentBytesAfterCancellation": childrenAfterCancellation,
                ],
                "eof": [
                    "observed": true,
                    "finalSnapshot": finalSnapshot.isFinal,
                    "startSourceFrame": provenance.request.startSourceFrame,
                    "endSourceFrame": finalSnapshot.endFrame,
                    "publishedSnapshotCount": eofRun.publishedSnapshots,
                    "wallSeconds": eofWallSeconds,
                    "decoderVersion": provenance.decoderVersion,
                    "timestampSource": provenance.timestampSource.rawValue,
                    "timestampTimeBase": provenance.timestampTimeBase,
                    "timestampFrameCount": provenance.timestampFrameCount,
                    "syntheticInitialSilenceFrameCount":
                        provenance.syntheticInitialSilenceFrameCount,
                    "dynamicRangeCompressionDisabled": provenance.dynamicRangeCompressionDisabled,
                    "codecNormalizationDisabled": provenance.codecNormalizationDisabled,
                    "maximumAbsoluteClockDriftSeconds": eofRun.maximumAbsoluteClockDrift,
                    "clockDriftSampleCount": eofRun.clockDriftSamples,
                    "maximumDecodedAheadSeconds": eofRun.maximumDecodedAhead,
                    "peakAppResidentBytes": eofRun.peakAppResident,
                    "peakChildResidentBytes": eofRun.peakChildResident,
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let line = "LIVE_AUDIO_METER_PROFILE " + String(decoding: data, as: UTF8.self)
            print(line)
            let attachment = XCTAttachment(string: line)
            attachment.name = "Live audio meter profile — \(inputIndex) — \(url.lastPathComponent)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func load(_ item: MediaItem, in player: PlayerController, startTime: TimeInterval) async throws {
        player.loadMedia(item, startTime: startTime)
        try await waitUntil(timeout: 15, description: "production playback backend construction") {
            player.playbackBackend != nil
        }
        if player.useMPV {
            let mpv = try XCTUnwrap(player.mpvPlayer)
            let size = CGSize(width: 320, height: 180)
            let layer = MPVMetalLayer()
            layer.frame = CGRect(origin: .zero, size: size)
            layer.drawableSize = size
            mpv.attachDrawable(layer)
            retainedMPVLayers.append(layer)
        }
        try await waitUntil(timeout: 30, description: "production playback readiness") {
            player.isReady && player.playbackBackend != nil
        }
        try await waitUntil(timeout: 15, description: "selected audio-track readiness") {
            (try? player.liveAudioMeterSource(id: "A", label: "Source A")) != nil
        }
    }

    private func sample(
        player: PlayerController,
        session: LiveAudioMeterSession,
        startFrame: Int64,
        seconds requestedSeconds: Double
    ) async throws -> SampledRun {
        let start = ContinuousClock.now
        var run = SampledRun(startFrame: startFrame, endFrame: startFrame, peakAppResident: try residentBytes())
        var previousCount = 0
        var previousSnapshotTime: ContinuousClock.Instant?
        while seconds(start.duration(to: .now)) < requestedSeconds {
            try updateSamples(player: player, session: session, start: start,
                              previousCount: &previousCount, previousSnapshotTime: &previousSnapshotTime, run: &run)
            try await Task.sleep(for: .milliseconds(20))
        }
        try updateSamples(player: player, session: session, start: start,
                          previousCount: &previousCount, previousSnapshotTime: &previousSnapshotTime, run: &run)
        run.wallSeconds = seconds(start.duration(to: .now))
        return run
    }

    private func sampleUntilEnded(
        player: PlayerController,
        session: LiveAudioMeterSession,
        run: inout SampledRun,
        timeout: Double
    ) async throws {
        let start = ContinuousClock.now
        var previousCount = 0
        var previousSnapshotTime: ContinuousClock.Instant?
        while seconds(start.duration(to: .now)) < timeout {
            try updateSamples(player: player, session: session, start: start,
                              previousCount: &previousCount, previousSnapshotTime: &previousSnapshotTime, run: &run)
            if case .ended = session.coordinator.status { return }
            if case .unavailable(let reason, let diagnostic) = session.coordinator.status {
                XCTFail("Live meter failed before EOF: \(reason) \(diagnostic ?? "")")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Live meter did not reach EOF before the \(timeout)-second deadline")
    }

    private func updateSamples(
        player: PlayerController,
        session: LiveAudioMeterSession,
        start: ContinuousClock.Instant,
        previousCount: inout Int,
        previousSnapshotTime: inout ContinuousClock.Instant?,
        run: inout SampledRun
    ) throws {
        run.peakAppResident = max(run.peakAppResident, try residentBytes())
        run.peakChildResident = max(run.peakChildResident, try childResidentBytes())
        let count = session.coordinator.publishedSnapshotCount
        if count != previousCount, let snapshot = session.coordinator.snapshot {
            let now = ContinuousClock.now
            if previousCount == 0 {
                run.firstSnapshotLatency = seconds(start.duration(to: now))
            }
            if let previousSnapshotTime {
                run.maximumSnapshotInterval = max(
                    run.maximumSnapshotInterval, seconds(previousSnapshotTime.duration(to: now))
                )
            }
            previousSnapshotTime = now
            previousCount = count
            run.publishedSnapshots = count
            run.endFrame = snapshot.endFrame
            let decodedTime = Double(snapshot.endFrame) / Double(snapshot.samplePeakDBFS.isEmpty
                ? 1 : session.coordinator.provenance?.request.format.sampleRate
                    ?? player.selectedAudioStream?.sampleRate ?? 1)
            run.maximumDecodedAhead = max(
                run.maximumDecodedAhead, max(0, decodedTime - player.playbackTimeSnapshot())
            )
        }
        if let drift = session.coordinator.clockDrift {
            run.maximumAbsoluteClockDrift = max(run.maximumAbsoluteClockDrift, abs(drift))
            run.clockDriftSamples += 1
        }
    }

    private func waitUntil(
        timeout: Double,
        description: String,
        condition: @escaping @MainActor () throws -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while seconds(start.duration(to: .now)) < timeout {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(
            domain: "LiveAudioMeterPerformanceTimeout",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(description)"]
        )
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LiveAudioMeterPerformanceTests.\(UUID().uuidString)")!
    }

    private func childResidentBytes() throws -> UInt64 {
        var pids = [pid_t](repeating: 0, count: 1_024)
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(getpid()), $0.baseAddress, capacity)
        }
        guard bytes >= 0, bytes < capacity else {
            throw NSError(domain: "LiveMeterProfileChildEnumeration", code: Int(bytes))
        }
        var resident: UInt64 = 0
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size {
                resident += info.pti_resident_size
            }
        }
        return resident
    }

    private func residentBytes() throws -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(result))
        }
        return UInt64(info.resident_size)
    }
}
