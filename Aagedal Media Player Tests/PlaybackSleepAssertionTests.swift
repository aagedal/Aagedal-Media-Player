// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

@MainActor
final class PlaybackSleepAssertionTests: XCTestCase {
    func testRequiredLevelPolicyForMediaKindsAndPlaybackStates() {
        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: false,
                isReversing: false,
                hasMediaItem: true,
                presentationKind: .video,
                hasVideoStream: true
            ),
            .none
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: true,
                isReversing: false,
                hasMediaItem: false,
                presentationKind: .video,
                hasVideoStream: true
            ),
            .none
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: true,
                isReversing: false,
                hasMediaItem: true,
                presentationKind: .video,
                hasVideoStream: true
            ),
            .preventDisplaySleep
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: false,
                isReversing: true,
                hasMediaItem: true,
                presentationKind: .video,
                hasVideoStream: true
            ),
            .preventDisplaySleep
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: true,
                isReversing: false,
                hasMediaItem: true,
                presentationKind: .audioOnly,
                hasVideoStream: false
            ),
            .preventSystemSleep
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: true,
                isReversing: false,
                hasMediaItem: true,
                presentationKind: .unresolved,
                hasVideoStream: true
            ),
            .preventDisplaySleep
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: true,
                isReversing: false,
                hasMediaItem: true,
                presentationKind: .unresolved,
                hasVideoStream: false
            ),
            .preventSystemSleep
        )

        XCTAssertEqual(
            PlaybackSleepAssertionLevel.required(
                isPlaying: true,
                isReversing: false,
                hasMediaItem: true,
                presentationKind: .noPlayableStreams,
                hasVideoStream: false
            ),
            .none
        )
    }

    func testCoordinatorHoldsSingleAssertionAcrossMultipleWindowsAndTransitionsWithoutGap() {
        let backend = SpySleepAssertionBackend()
        let coordinator = PlaybackSleepAssertionCoordinator(backend: backend)
        let windowA = UUID()
        let windowB = UUID()

        coordinator.update(sourceID: windowA, level: .preventDisplaySleep)
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)
        XCTAssertEqual(coordinator.activeSourceCount, 1)
        XCTAssertEqual(backend.events, [.begin(id: 1, level: .preventDisplaySleep, reason: "Playing video")])
        XCTAssertEqual(backend.liveTokenIDs, [1])

        // A second playing window must not churn or duplicate the OS assertion.
        coordinator.update(sourceID: windowB, level: .preventSystemSleep)
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)
        XCTAssertEqual(coordinator.activeSourceCount, 2)
        XCTAssertEqual(backend.events.count, 1)

        // Pausing the video window downgrades seamlessly to audio-only system sleep prevention:
        // replacement is acquired before the previous assertion is released.
        coordinator.update(sourceID: windowA, level: .none)
        XCTAssertEqual(coordinator.activeLevel, .preventSystemSleep)
        XCTAssertEqual(coordinator.activeSourceCount, 1)
        XCTAssertEqual(backend.events, [
            .begin(id: 1, level: .preventDisplaySleep, reason: "Playing video"),
            .begin(id: 2, level: .preventSystemSleep, reason: "Playing audio"),
            .end(id: 1),
        ])
        XCTAssertEqual(backend.liveTokenIDs, [2])

        // Removing the last source releases all assertions.
        coordinator.removeSource(windowB)
        XCTAssertEqual(coordinator.activeLevel, .none)
        XCTAssertEqual(coordinator.activeSourceCount, 0)
        XCTAssertTrue(backend.liveTokenIDs.isEmpty)
        XCTAssertEqual(backend.events.last, .end(id: 2))
    }

    func testPlayerControllerAcquiresAndReleasesDisplaySleepAssertionAcrossPlaybackLifecycle() {
        let backend = SpySleepAssertionBackend()
        let coordinator = PlaybackSleepAssertionCoordinator(backend: backend)
        let controller = PlayerController(
            proResRAWDetector: { _, _ in false },
            sleepAssertionCoordinator: coordinator
        )

        var videoItem = MediaItem(
            url: URL(fileURLWithPath: "/tmp/sleep-test.mov"),
            name: "sleep-test",
            size: 1024,
            durationSeconds: 10,
            hasVideoStream: true
        )
        controller.mediaItem = videoItem
        controller.markPlaybackReady(isBuffering: false)
        XCTAssertEqual(coordinator.activeLevel, .none)

        // Timer-based reverse playback (no backend needed) keeps the display awake.
        controller.startReverse()
        XCTAssertTrue(controller.isReversing)
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)
        XCTAssertEqual(backend.liveTokenIDs.count, 1)

        // Metadata resolving as audio-only downgrades to system-sleep prevention only.
        videoItem.metadata = MediaMetadata(
            duration: 10,
            formatName: "wav",
            containerLongName: nil,
            sizeBytes: 1024,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [
                MediaMetadata.AudioStream(
                    index: 0,
                    languageCode: nil,
                    title: nil,
                    codec: "pcm_s16le",
                    codecLongName: nil,
                    profile: nil,
                    sampleRate: 48_000,
                    channels: 2,
                    channelLayout: "stereo",
                    bitDepth: 16,
                    bitRate: nil,
                    isDefault: true
                ),
            ],
            subtitleStreams: [],
            chapters: []
        )
        videoItem.hasVideoStream = false
        controller.updateMetadata(videoItem)
        XCTAssertEqual(coordinator.activeLevel, .preventSystemSleep)

        // Pausing releases the assertion.
        controller.pause()
        XCTAssertEqual(coordinator.activeLevel, .none)
        XCTAssertTrue(backend.liveTokenIDs.isEmpty)

        // Teardown while reversing releases the assertion immediately.
        videoItem.hasVideoStream = true
        videoItem.metadata = nil
        controller.mediaItem = videoItem
        controller.startReverse()
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)

        controller.teardown()
        XCTAssertEqual(coordinator.activeLevel, .none)
        XCTAssertTrue(backend.liveTokenIDs.isEmpty)

        // Playback failure also releases the assertion.
        controller.markPlaybackReady(isBuffering: false)
        controller.startReverse()
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)

        controller.reportPlaybackFailure(
            backend: .mpv,
            stage: .playback,
            message: "Simulated decoder failure"
        )
        XCTAssertEqual(coordinator.activeLevel, .none)
        XCTAssertTrue(backend.liveTokenIDs.isEmpty)
    }

    func testTwoPlayerControllersKeepDisplayAwakeUntilBothStop() {
        let backend = SpySleepAssertionBackend()
        let coordinator = PlaybackSleepAssertionCoordinator(backend: backend)
        let primary = PlayerController(
            proResRAWDetector: { _, _ in false },
            sleepAssertionCoordinator: coordinator
        )
        let secondary = PlayerController(
            proResRAWDetector: { _, _ in false },
            sleepAssertionCoordinator: coordinator
        )

        let itemA = MediaItem(
            url: URL(fileURLWithPath: "/tmp/window-a.mov"),
            name: "window-a",
            size: 1024,
            durationSeconds: 10,
            hasVideoStream: true
        )
        let itemB = MediaItem(
            url: URL(fileURLWithPath: "/tmp/window-b.mov"),
            name: "window-b",
            size: 1024,
            durationSeconds: 10,
            hasVideoStream: true
        )

        primary.mediaItem = itemA
        primary.markPlaybackReady(isBuffering: false)
        secondary.mediaItem = itemB
        secondary.markPlaybackReady(isBuffering: false)

        primary.startReverse()
        secondary.startReverse()
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)
        XCTAssertEqual(coordinator.activeSourceCount, 2)
        XCTAssertEqual(backend.liveTokenIDs.count, 1)

        // Stopping one window must keep the display awake while the other plays.
        secondary.teardown()
        XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)
        XCTAssertEqual(coordinator.activeSourceCount, 1)
        XCTAssertEqual(backend.liveTokenIDs.count, 1)

        // Stopping the remaining window releases the assertion.
        primary.pause()
        XCTAssertEqual(coordinator.activeLevel, .none)
        XCTAssertEqual(coordinator.activeSourceCount, 0)
        XCTAssertTrue(backend.liveTokenIDs.isEmpty)
    }

    func testPlayerControllerDeinitReleasesHeldAssertion() async {
        let backend = SpySleepAssertionBackend()
        let coordinator = PlaybackSleepAssertionCoordinator(backend: backend)

        do {
            let controller = PlayerController(
                proResRAWDetector: { _, _ in false },
                sleepAssertionCoordinator: coordinator
            )
            controller.mediaItem = MediaItem(
                url: URL(fileURLWithPath: "/tmp/deinit-sleep-test.mov"),
                name: "deinit-sleep-test",
                size: 1024,
                durationSeconds: 10,
                hasVideoStream: true
            )
            controller.markPlaybackReady(isBuffering: false)
            controller.startReverse()
            XCTAssertEqual(coordinator.activeLevel, .preventDisplaySleep)
        }

        // Wait for the deinit main-actor cleanup task to execute.
        for _ in 0..<20 where coordinator.activeLevel != .none {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.activeLevel, .none)
        XCTAssertTrue(backend.liveTokenIDs.isEmpty)
    }
}

@MainActor
private final class SpySleepAssertionBackend: PlaybackSleepAssertionBackend {
    enum Event: Equatable {
        case begin(id: Int, level: PlaybackSleepAssertionLevel, reason: String)
        case end(id: Int)
    }

    private final class Token {
        let id: Int
        init(id: Int) { self.id = id }
    }

    private var nextID = 1
    private(set) var events: [Event] = []
    private(set) var liveTokenIDs: Set<Int> = []

    func beginAssertion(level: PlaybackSleepAssertionLevel, reason: String) -> AnyObject {
        let id = nextID
        nextID += 1
        liveTokenIDs.insert(id)
        events.append(.begin(id: id, level: level, reason: reason))
        return Token(id: id)
    }

    func endAssertion(_ token: AnyObject) {
        guard let token = token as? Token else {
            XCTFail("Unexpected token type")
            return
        }
        XCTAssertTrue(liveTokenIDs.remove(token.id) != nil, "Assertion token ended twice")
        events.append(.end(id: token.id))
    }
}
