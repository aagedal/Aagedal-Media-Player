// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareSessionLifecycleTests: XCTestCase {
    func testRapidReplacementIgnoresStaleMetadataCompletion() async throws {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let session = makeSession(loader: loader)
        let firstURL = URL(fileURLWithPath: "/tmp/compare-first.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/compare-second.mov")

        session.loadSecondary(firstURL, alignedWith: primary)
        let requestedFirst = await waitUntil { loader.hasRequest(for: firstURL) }
        XCTAssertTrue(requestedFirst)

        session.loadSecondary(secondURL, alignedWith: primary)
        let requestedSecond = await waitUntil { loader.hasRequest(for: secondURL) }
        XCTAssertTrue(requestedSecond)

        loader.succeed(secondURL, metadata: metadata(duration: 12))
        let loadedSecond = await waitUntil { session.secondaryURL == secondURL }
        XCTAssertTrue(loadedSecond)

        loader.succeed(firstURL, metadata: metadata(duration: 24))
        await settleMainActorTasks()

        XCTAssertEqual(session.secondaryURL, secondURL)
        XCTAssertEqual(session.mapping?.secondaryDuration, 12)
        XCTAssertFalse(session.isLoading)
        session.stop()
    }

    func testStopDuringMetadataLoadRejectsLateCompletionAndRestoresAudioSafety() async {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let secondary = PlayerController()
        let session = makeSession(loader: loader, secondary: secondary)
        let url = URL(fileURLWithPath: "/tmp/compare-stopped.mov")

        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        XCTAssertTrue(requested)

        session.stop()
        loader.succeed(url, metadata: metadata(duration: 10))
        await settleMainActorTasks()

        XCTAssertNil(session.secondaryURL)
        XCTAssertNil(session.mapping)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isLoading)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    func testDecoderFailureRemainsMoreSpecificThanReadinessTimeout() async {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let session = makeSession(loader: loader)
        let url = URL(fileURLWithPath: "/tmp/compare-failed.mov")

        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        XCTAssertTrue(requested)
        loader.succeed(url, metadata: metadata(duration: 10))
        let loaded = await waitUntil { session.secondaryURL == url }
        XCTAssertTrue(loaded)

        let failure = PlaybackFailure(
            backend: .mpv,
            stage: .loading,
            message: "Decoder rejected the comparison stream.",
            mediaURL: url
        )
        session.handleSecondaryPlaybackPhase(.failed(failure))
        session.handleSecondaryReadinessTimeout(primary: primary)

        XCTAssertEqual(
            session.loadError,
            "The comparison file could not be played: Decoder rejected the comparison stream."
        )
        XCTAssertEqual(session.audioSource, .primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(session.secondaryController.isAudioSuppressed)
        session.stop()
    }

    private func makeSession(
        loader: ControlledCompareMetadataLoader,
        secondary: PlayerController = PlayerController()
    ) -> CompareSessionController {
        CompareSessionController(
            secondaryController: secondary,
            metadataLoader: { url in
                try await loader.load(url)
            }
        )
    }

    private func metadata(duration: TimeInterval) -> MediaMetadata {
        MediaMetadata(
            duration: duration,
            formatName: "mov",
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [],
            subtitleStreams: [],
            chapters: []
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }

    private func settleMainActorTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
private final class ControlledCompareMetadataLoader {
    private var requestedURLs: Set<URL> = []
    private var continuations: [URL: CheckedContinuation<MediaMetadata, Error>] = [:]

    func load(_ url: URL) async throws -> MediaMetadata {
        requestedURLs.insert(url)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[url] = continuation
        }
    }

    func hasRequest(for url: URL) -> Bool {
        requestedURLs.contains(url)
    }

    func succeed(_ url: URL, metadata: MediaMetadata) {
        continuations.removeValue(forKey: url)?.resume(returning: metadata)
    }
}
