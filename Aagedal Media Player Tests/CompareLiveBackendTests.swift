// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

/// Real-decoder Compare Mode checks. The fixtures are deliberately small so
/// these can exercise Metal-backed MPV contexts and AVPlayer instances in the
/// normal macOS test run without turning the suite into a performance test.
///
/// Run with:
/// xcodebuild test \
///   -project "Aagedal Media Player.xcodeproj" \
///   -scheme "Aagedal Media Player" \
///   -destination "platform=macOS" \
///   -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests"
@MainActor
final class CompareLiveBackendTests: XCTestCase {
    func testMPVPairAlignsBySourceTimecodeAndSharesTransport() async throws {
        try await exercisePair(primaryBackend: .mpv, secondaryBackend: .mpv)
    }

    func testMPVPrimaryAndAVFoundationSecondaryShareTransport() async throws {
        try await exercisePair(primaryBackend: .mpv, secondaryBackend: .avFoundation)
    }

    func testAVFoundationPairAlignsBySourceTimecodeAndSharesTransport() async throws {
        try await exercisePair(primaryBackend: .avFoundation, secondaryBackend: .avFoundation)
    }

    func testAVFoundationPrimaryAndMPVSecondaryShareTransport() async throws {
        try await exercisePair(primaryBackend: .avFoundation, secondaryBackend: .mpv)
    }

    private func exercisePair(
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend
    ) async throws {
        let fixtures = try fixtureDirectory()
        let primaryURL = fixtures.appending(path: "compare/source-a.mov")
        let secondaryURL = fixtures.appending(path: "compare/source-b.mov")
        let primary = makeController(forcedBackend: primaryBackend)
        let secondary = makeController(forcedBackend: secondaryBackend)
        let session = CompareSessionController(secondaryController: secondary)

        defer {
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: primaryURL)
        try await attachMPVSurfaceIfNeeded(to: primary)
        let primaryBecameReady = await waitUntil { primary.isReady }
        XCTAssertTrue(
            primaryBecameReady,
            "Primary \(primaryBackend.rawValue) decoder did not become ready."
        )

        session.loadSecondary(secondaryURL, alignedWith: primary)
        let metadataFinishedLoading = await waitUntil { session.secondaryURL == secondaryURL }
        XCTAssertTrue(
            metadataFinishedLoading,
            "Comparison metadata did not finish loading."
        )
        try await attachMPVSurfaceIfNeeded(to: secondary)
        let secondaryBecameReady = await waitUntil { session.isSecondaryReady }
        XCTAssertTrue(
            secondaryBecameReady,
            "Secondary \(secondaryBackend.rawValue) decoder did not become ready: " +
                (session.loadError ?? "no backend diagnostic")
        )

        let mapping = try XCTUnwrap(session.mapping)
        XCTAssertEqual(mapping.mode, .sourceTimecode)
        XCTAssertEqual(mapping.offset, 1, accuracy: 1.0 / 24.0)

        session.seek(primary: primary, to: 1.25)
        let primaryReachedSeekTarget = await waitUntil(
            tolerance: 1.0 / 24.0,
            timeout: .seconds(8)
        ) {
            primary.playbackTimeSnapshot() - 1.25
        }
        XCTAssertTrue(
            primaryReachedSeekTarget,
            "Primary exact seek did not complete within one-frame tolerance."
        )
        let secondaryReachedSeekTarget = await waitUntil(
            tolerance: 1.0 / 24.0,
            timeout: .seconds(8)
        ) {
            secondary.playbackTimeSnapshot() - 2.25
        }
        XCTAssertTrue(
            secondaryReachedSeekTarget,
            "Secondary exact seek did not complete within one-frame tolerance."
        )

        session.play(primary: primary)
        let bothStartedPlaying = await waitUntil { primary.isPlaying && secondary.isPlaying }
        XCTAssertTrue(bothStartedPlaying)
        try await Task.sleep(for: .milliseconds(750))
        let driftConverged = await waitUntil(tolerance: 1.0 / 24.0) {
            let expectedSecondaryTime = session.secondaryTime(
                forPrimaryTime: primary.playbackTimeSnapshot()
            )
            return secondary.playbackTimeSnapshot() - expectedSecondaryTime
        }
        let finalExpectedSecondaryTime = session.secondaryTime(
            forPrimaryTime: primary.playbackTimeSnapshot()
        )
        let finalPlayingDrift = secondary.playbackTimeSnapshot() - finalExpectedSecondaryTime
        XCTAssertTrue(
            driftConverged,
            "1x playback drift did not converge within one primary frame; " +
                "final drift was \(finalPlayingDrift) seconds."
        )

        session.pause(primary: primary)
        let bothPaused = await waitUntil { !primary.isPlaying && !secondary.isPlaying }
        XCTAssertTrue(bothPaused)
        let pausedExpectedTime = session.secondaryTime(
            forPrimaryTime: primary.playbackTimeSnapshot()
        )
        let secondaryReachedPauseTarget = await waitUntil(
            tolerance: 1.0 / 24.0,
            timeout: .seconds(8)
        ) {
            secondary.playbackTimeSnapshot() - pausedExpectedTime
        }
        XCTAssertTrue(
            secondaryReachedPauseTarget,
            "Paused synchronization did not complete within one-frame tolerance."
        )
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    private func makeController(forcedBackend backend: PlaybackBackend) -> PlayerController {
        PlayerController(proResRAWDetector: { _, _ in
            backend == .avFoundation
        })
    }

    private func loadPrimary(_ controller: PlayerController, url: URL) async throws {
        let metadata = try await MetadataService.shared.metadata(for: url)
        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.metadata = metadata
        item.durationSeconds = metadata.duration ?? 0
        item.hasVideoStream = !metadata.videoStreams.isEmpty
        controller.loadMedia(item)
        controller.updateMetadata(item)
    }

    private func attachMPVSurfaceIfNeeded(to controller: PlayerController) async throws {
        guard await waitUntil({ controller.useMPV || controller.player != nil }) else {
            XCTFail("The forced playback backend was not constructed.")
            return
        }
        guard controller.useMPV else { return }
        let mpv = try XCTUnwrap(controller.mpvPlayer)
        let layer = MPVMetalLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        layer.drawableSize = CGSize(width: 320, height: 180)
        mpv.attachDrawable(layer)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: Duration = .seconds(8)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func waitUntil(
        tolerance: TimeInterval,
        timeout: Duration = .seconds(3),
        difference: @escaping @MainActor () -> TimeInterval
    ) async -> Bool {
        await waitUntil({ abs(difference()) <= tolerance }, timeout: timeout)
    }

    private func fixtureDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"],
           !override.isEmpty {
            return try validateFixtureDirectory(
                URL(fileURLWithPath: override, isDirectory: true)
            )
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        return try validateFixtureDirectory(
            repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        )
    }

    private func validateFixtureDirectory(_ url: URL) throws -> URL {
        let requiredFiles = [
            "MANIFEST.txt",
            "compare/source-a.mov",
            "compare/source-b.mov",
        ]
        guard requiredFiles.allSatisfy({
            FileManager.default.fileExists(atPath: url.appending(path: $0).path)
        }) else {
            throw XCTSkip(
                "Compare fixtures are unavailable. Run scripts/generate-test-fixtures.sh " +
                    "or set MEDIA_FIXTURE_DIR."
            )
        }
        return url
    }
}
