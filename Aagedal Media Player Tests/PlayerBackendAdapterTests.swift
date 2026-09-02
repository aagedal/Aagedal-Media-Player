// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import AVFoundation
import XCTest

@MainActor
final class PlayerBackendAdapterTests: XCTestCase {
    func testProResRAWFourCCTagsUseAVFoundation() {
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "aprn", pixelFormat: nil),
            .avFoundation
        )
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "ProRes APRH", pixelFormat: nil),
            .avFoundation
        )
    }

    func testBayerPixelFormatsUseAVFoundation() {
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "prores", pixelFormat: "BAYER_RGGB16LE"),
            .avFoundation
        )
    }

    func testOrdinaryAndAudioOnlyMediaUseMPV() {
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "hevc", pixelFormat: "yuv420p10le"),
            .mpv
        )
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: nil, pixelFormat: nil),
            .mpv
        )
    }

    func testAVPlaybackObservationIdentityRequiresSamePreparationPlayerAndItem() {
        let firstItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/first.mov"))
        let replacementItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/replacement.mov"))
        let firstPlayer = AVPlayer(playerItem: firstItem)
        let replacementPlayer = AVPlayer(playerItem: replacementItem)
        let identity = AVPlaybackObservationIdentity(
            preparationID: 7,
            player: firstPlayer,
            playerItem: firstItem
        )

        XCTAssertTrue(identity.matches(
            preparationID: 7,
            player: firstPlayer,
            playerItem: firstItem
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 8,
            player: firstPlayer,
            playerItem: firstItem
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 7,
            player: replacementPlayer,
            playerItem: replacementItem
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 7,
            player: firstPlayer,
            playerItem: replacementItem
        ))
    }

    func testMPVPlaybackObservationIdentityRequiresSamePreparationAndPlayer() {
        let firstPlayer = MPVPlayer()
        let replacementPlayer = MPVPlayer()
        let identity = MPVPlaybackObservationIdentity(
            preparationID: 11,
            player: firstPlayer
        )

        XCTAssertTrue(identity.matches(
            preparationID: 11,
            player: firstPlayer
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 12,
            player: firstPlayer
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 11,
            player: replacementPlayer
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 11,
            player: nil
        ))
    }

    func testScopeCaptureIdentityRequiresSameGenerationAndPlayer() {
        let firstPlayer = MPVPlayer()
        let replacementPlayer = MPVPlayer()
        let identity = ScopeCaptureIdentity(
            generation: 13,
            player: firstPlayer
        )

        XCTAssertTrue(identity.matches(
            generation: 13,
            player: firstPlayer
        ))
        XCTAssertFalse(identity.matches(
            generation: 14,
            player: firstPlayer
        ))
        XCTAssertFalse(identity.matches(
            generation: 13,
            player: replacementPlayer
        ))
        XCTAssertFalse(identity.matches(
            generation: 13,
            player: nil
        ))
    }

    func testTeardownRejectsSuspendedBackendSelectionCompletion() async {
        let detector = SuspendedProResRAWDetector()
        let controller = PlayerController { _, _ in
            await detector.result()
        }
        let item = MediaItem(
            url: URL(fileURLWithPath: "/tmp/pending.mov"),
            name: "pending",
            size: 0
        )

        controller.loadMedia(item)
        await detector.waitUntilStarted()
        let activePreparationID = controller.preparationID
        XCTAssertEqual(controller.playbackPhase, .preparing)

        controller.teardown()
        XCTAssertGreaterThan(controller.preparationID, activePreparationID)
        XCTAssertEqual(controller.playbackPhase, .idle)

        detector.resume(returning: false)
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(controller.playbackPhase, .idle)
        XCTAssertFalse(controller.isReady)
    }
}

@MainActor
private final class SuspendedProResRAWDetector {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var didStart = false

    func result() async -> Bool {
        didStart = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func resume(returning value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
