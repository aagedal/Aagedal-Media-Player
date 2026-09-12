// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LiveAudioMeterSessionTests: XCTestCase {
    func testStartsSelectedSourceAtCurrentClockAndFreezesWhenOpenedPaused() async throws {
        let player = PlayerController()
        player.mediaItem = mediaItem(url: URL(fileURLWithPath: "/tmp/source-a.mov"))
        player.currentPlaybackTime = 1.25
        player.refreshAudioTrackOptions(playerItem: nil)
        await eventually { player.liveAudioMeterSourceRevision > 0 }

        let recorder = MeterDecodeRecorder()
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: recorder.decode)
        let session = LiveAudioMeterSession(
            primary: player,
            comparison: CompareSessionController(),
            defaults: isolatedDefaults(),
            coordinator: coordinator
        )

        session.start()

        await eventually { await recorder.requestCountValue() == 1 }
        let request = await recorder.firstRequest()
        XCTAssertEqual(request?.url, player.mediaItem?.url)
        XCTAssertEqual(request?.startSourceFrame, 60_000)
        XCTAssertEqual(session.viewState.sourceOptions.map(\.id), ["A"])
        XCTAssertEqual(coordinator.status, .paused(frame: 60_000))

        player.currentPlaybackTime = 2
        session.retry()
        await eventually { await recorder.requestCountValue() == 2 }
        let retriedFrame = await recorder.lastRequestFrame()
        XCTAssertEqual(retriedFrame, 96_000)

        session.close()
        await eventually { await recorder.cancellationCountValue() == 2 }
    }

    func testSourceReplacementWaitsForTrackReadinessBeforeStartingNewIdentity() async throws {
        let player = PlayerController()
        let firstURL = URL(fileURLWithPath: "/tmp/first.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/second.mov")
        player.mediaItem = mediaItem(url: firstURL)
        player.refreshAudioTrackOptions(playerItem: nil)
        await eventually { player.liveAudioMeterSourceRevision > 0 }

        let recorder = MeterDecodeRecorder()
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: recorder.decode)
        let session = LiveAudioMeterSession(
            primary: player,
            comparison: CompareSessionController(),
            defaults: isolatedDefaults(),
            coordinator: coordinator
        )
        session.start()
        await eventually { await recorder.requestCountValue() == 1 }

        player.mediaItem = mediaItem(url: secondURL)
        player.publishLiveAudioMeterDiscontinuity(.sourceReplacement)
        try await Task.sleep(for: .milliseconds(30))
        let requestCountBeforeReadiness = await recorder.requestCountValue()
        XCTAssertEqual(requestCountBeforeReadiness, 1, "Must not mix a new URL with stale track options")

        let oldRevision = player.liveAudioMeterSourceRevision
        player.refreshAudioTrackOptions(playerItem: nil)
        await eventually { player.liveAudioMeterSourceRevision > oldRevision }
        await eventually { await recorder.requestCountValue() == 2 }
        let lastURL = await recorder.lastRequest()?.url
        XCTAssertEqual(lastURL, secondURL)

        session.close()
        await eventually { await recorder.cancellationCountValue() == 2 }
    }

    func testLateMetadataReopensSourceReadinessWithoutManualRetry() async throws {
        let player = PlayerController()
        let url = URL(fileURLWithPath: "/tmp/slow-metadata.mov")
        var unresolved = mediaItem(url: url)
        unresolved.metadata = nil
        player.mediaItem = unresolved
        player.refreshAudioTrackOptions(playerItem: nil)
        await eventually { player.liveAudioMeterSourceRevision > 0 }

        let recorder = MeterDecodeRecorder()
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: recorder.decode)
        let session = LiveAudioMeterSession(
            primary: player,
            comparison: CompareSessionController(),
            defaults: isolatedDefaults(),
            coordinator: coordinator
        )
        session.start()
        try await Task.sleep(for: .milliseconds(30))
        let requestCountBeforeMetadata = await recorder.requestCountValue()
        XCTAssertEqual(requestCountBeforeMetadata, 0)

        player.updateMetadata(mediaItem(url: url))

        await eventually { await recorder.requestCountValue() == 1 }
        let measuredURL = await recorder.lastRequest()?.url
        XCTAssertEqual(measuredURL, url)
        session.close()
        await eventually { await recorder.cancellationCountValue() == 1 }
    }

    func testReferenceChangesPersistWithoutRestartingMeasurement() async throws {
        let player = PlayerController()
        player.mediaItem = mediaItem(url: URL(fileURLWithPath: "/tmp/reference.mov"))
        player.refreshAudioTrackOptions(playerItem: nil)
        await eventually { player.liveAudioMeterSourceRevision > 0 }
        let recorder = MeterDecodeRecorder()
        let coordinator = LiveAudioMeterCoordinator(decodeOperation: recorder.decode)
        let defaults = isolatedDefaults()
        let session = LiveAudioMeterSession(
            primary: player,
            comparison: CompareSessionController(),
            defaults: defaults,
            coordinator: coordinator
        )
        session.start()
        await eventually { await recorder.requestCountValue() == 1 }
        let generation = coordinator.generation

        session.selectPreset(.custom)
        session.setCustomLoudnessTarget(-18)
        session.setCustomTruePeakCeiling(-2)

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(LiveAudioMeterPreferences(defaults: defaults), .init(
            preset: .custom, customLoudnessTarget: -18, customTruePeakCeiling: -2
        ))
        session.close()
    }

    private func mediaItem(url: URL) -> MediaItem {
        let stream = MediaMetadata.AudioStream(
            index: 1,
            languageCode: "eng",
            title: "Stereo mix",
            codec: "aac",
            codecLongName: nil,
            profile: nil,
            sampleRate: 48_000,
            channels: 2,
            channelLayout: "stereo",
            bitDepth: nil,
            bitRate: nil,
            isDefault: true
        )
        let metadata = MediaMetadata(
            duration: 60,
            formatName: "mov",
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [stream],
            subtitleStreams: [],
            chapters: []
        )
        return MediaItem(
            url: url, name: url.lastPathComponent, size: 0,
            durationSeconds: 60, hasVideoStream: false, metadata: metadata
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LiveAudioMeterSessionTests.\(UUID().uuidString)")!
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition not satisfied before timeout")
    }
}

private actor MeterDecodeRecorder {
    private var requests: [LiveAudioMeterDecodeRequest] = []
    private var cancellationCount = 0

    func requestCountValue() -> Int { requests.count }
    func cancellationCountValue() -> Int { cancellationCount }
    func firstRequest() -> LiveAudioMeterDecodeRequest? { requests.first }
    func lastRequest() -> LiveAudioMeterDecodeRequest? { requests.last }
    func lastRequestFrame() -> Int64? { requests.last?.startSourceFrame }

    func decode(
        _ request: LiveAudioMeterDecodeRequest,
        _ handle: SubprocessHandle,
        _ workerGate: LiveAudioMeterWorkerGate,
        _ onSnapshot: @escaping LiveAudioMeterPCMStreamProcessor.SnapshotHandler
    ) async throws -> LiveAudioMeterDecodeCompletion {
        _ = handle
        _ = workerGate
        _ = onSnapshot
        requests.append(request)
        do {
            while true { try await Task.sleep(for: .seconds(10)) }
        } catch {
            cancellationCount += 1
            throw error
        }
    }
}
