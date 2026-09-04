// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

/// Real-decoder Compare Mode checks. The fixtures are deliberately low
/// resolution so these can exercise Metal-backed MPV contexts and AVPlayer
/// instances in the normal macOS test run without turning the suite into a
/// hardware performance test.
///
/// Run with:
/// xcodebuild test \
///   -project "Aagedal Media Player.xcodeproj" \
///   -scheme "Aagedal Media Player" \
///   -destination "platform=macOS" \
///   -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests"
@MainActor
final class CompareLiveBackendTests: XCTestCase {
    private struct DriftObservation {
        let sampleCount: Int
        let inToleranceCount: Int
        let worstDrift: TimeInterval
        let longestExcursion: TimeInterval
        let lastInToleranceAge: TimeInterval
        let primaryAdvance: TimeInterval
        let secondaryAdvance: TimeInterval
        let firstSignedDrift: TimeInterval
        let lastSignedDrift: TimeInterval
        let finalEffectiveDrift: TimeInterval
        let minimumSecondaryRate: Float
        let maximumSecondaryRate: Float

        var inToleranceFraction: Double {
            guard sampleCount > 0 else { return 0 }
            return Double(inToleranceCount) / Double(sampleCount)
        }
    }

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

    func testMixedBackendsIsolateMatchingMultichannelAudioAndRestoreOnStop() async throws {
        let url = try fixtureDirectory().appending(path: "multichannel-5.1.m4a")
        let primary = makeController(forcedBackend: .mpv)
        let secondary = makeController(forcedBackend: .avFoundation)
        let session = CompareSessionController(secondaryController: secondary)

        defer {
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: url)
        try await attachMPVSurfaceIfNeeded(to: primary)
        let primaryReady = await waitUntil {
            primary.isReady && primary.selectedAudioChannelCount == 6
        }
        XCTAssertTrue(primaryReady)
        primary.toggleAudioChannelMute(5)
        XCTAssertEqual(primary.audioChannelRouting.mutedChannels, [5])

        session.loadSecondary(url, alignedWith: primary)
        let metadataLoaded = await waitUntil { session.secondaryURL == url }
        XCTAssertTrue(metadataLoaded)
        let secondaryReady = await waitUntil {
            session.isSecondaryReady && secondary.selectedAudioChannelCount == 6
        }
        XCTAssertTrue(secondaryReady)

        let center = try XCTUnwrap(
            session.availableComparedAudioChannels(primary: primary).first {
                $0.label == "Center"
            }
        )
        session.selectComparedAudioChannel(center, primary: primary)

        XCTAssertEqual(session.comparedAudioChannel?.label, "Center")
        XCTAssertEqual(primary.audioChannelRouting.soloedChannels, [2])
        XCTAssertEqual(secondary.audioChannelRouting.soloedChannels, [2])
        XCTAssertEqual(primary.mpvPlayer?.isAudioChannelFilterActive, true)
        XCTAssertNotNil(secondary.player?.currentItem?.audioMix)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)

        session.selectAudioSource(.secondary, primary: primary)
        XCTAssertTrue(primary.isAudioSuppressed)
        XCTAssertFalse(secondary.isAudioSuppressed)

        session.stop()
        XCTAssertNil(session.comparedAudioChannel)
        XCTAssertEqual(primary.audioChannelRouting.mutedChannels, [5])
        XCTAssertEqual(primary.audioChannelRouting.soloedChannels, [])
        XCTAssertFalse(primary.isAudioSuppressed)
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
        let frameRate = primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
        let driftPolicy = CompareDriftPolicy(primaryFrameRate: frameRate)
        let frameDuration = driftPolicy.frameDuration
        XCTAssertEqual(mapping.mode, .sourceTimecode)
        XCTAssertEqual(mapping.offset, 1, accuracy: frameDuration)

        session.seek(primary: primary, to: 1.25)
        let primaryReachedSeekTarget = await waitUntil(
            tolerance: frameDuration,
            timeout: .seconds(8)
        ) {
            primary.playbackTimeSnapshot() - 1.25
        }
        XCTAssertTrue(
            primaryReachedSeekTarget,
            "Primary exact seek did not complete within one-frame tolerance."
        )
        let secondaryReachedSeekTarget = await waitUntil(
            tolerance: frameDuration,
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
        if secondaryBackend == .mpv {
            XCTAssertEqual(
                secondary.mpvPlayer?.isAudioTrackSelectionDisabled,
                true,
                "Suppressed MPV source B unexpectedly re-enabled an audio track."
            )
        }
        let driftTolerance = driftPolicy.correctionThreshold
        let observation = await observeSustainedDrift(
            primary: primary,
            secondary: secondary,
            session: session,
            driftTolerance: driftTolerance,
            duration: sustainedPlaybackDuration
        )
        let pairDescription = "\(primaryBackend.rawValue)/\(secondaryBackend.rawValue)"
        let observationDescription = driftObservationDescription(
            observation,
            backendPair: pairDescription
        )
        if ProcessInfo.processInfo.environment["COMPARE_PROFILE_REPORT"] == "1" {
            print("COMPARE_PROFILE \(observationDescription)")
            let attachment = XCTAttachment(
                string: "COMPARE_PROFILE \(observationDescription)"
            )
            attachment.name = "Compare Mode drift profile"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(
            primary.isPlaying && secondary.isPlaying,
            "A decoder stopped during sustained playback. \(observationDescription)"
        )
        XCTAssertGreaterThanOrEqual(
            observation.primaryAdvance,
            sustainedPlaybackDuration - 1,
            "The primary clock stalled or reached EOF. \(observationDescription)"
        )
        XCTAssertGreaterThanOrEqual(
            observation.secondaryAdvance,
            sustainedPlaybackDuration - 1,
            "The secondary clock stalled or reached EOF. \(observationDescription)"
        )
        XCTAssertLessThanOrEqual(
            observation.longestExcursion,
            1,
            "Drift correction did not recover within one second. \(observationDescription)"
        )
        XCTAssertLessThanOrEqual(
            observation.lastInToleranceAge,
            1,
            "Drift did not reconverge during the final second. \(observationDescription)"
        )
        XCTAssertLessThanOrEqual(
            observation.finalEffectiveDrift,
            driftTolerance,
            "Drift finished outside one-frame tolerance. \(observationDescription)"
        )

        session.pause(primary: primary)
        let bothPaused = await waitUntil { !primary.isPlaying && !secondary.isPlaying }
        XCTAssertTrue(bothPaused)
        let pausedExpectedTime = session.secondaryTime(
            forPrimaryTime: primary.playbackTimeSnapshot()
        )
        let secondaryReachedPauseTarget = await waitUntil(
            tolerance: frameDuration,
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

    private func observeSustainedDrift(
        primary: PlayerController,
        secondary: PlayerController,
        session: CompareSessionController,
        driftTolerance: TimeInterval,
        duration: TimeInterval
    ) async -> DriftObservation {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: .seconds(duration))
        let primaryStart = primary.playbackTimeSnapshot()
        let secondaryStart = secondary.playbackTimeSnapshot()
        var sampleCount = 0
        var inToleranceCount = 0
        var worstDrift: TimeInterval = 0
        var excursionStart: ContinuousClock.Instant?
        var longestExcursion: TimeInterval = 0
        var lastInTolerance = start
        var firstSignedDrift: TimeInterval?
        var lastSignedDrift: TimeInterval = 0
        var finalEffectiveDrift: TimeInterval = 0
        var minimumSecondaryRate = Float.greatestFiniteMagnitude
        var maximumSecondaryRate: Float = 0
        var primaryAdvanceAtDeadline: TimeInterval?
        var secondaryAdvanceAtDeadline: TimeInterval?

        while primary.isPlaying, secondary.isPlaying {
            let loopTime = clock.now
            let isWithinRequestedObservation = loopTime < deadline
            if !isWithinRequestedObservation, primaryAdvanceAtDeadline == nil {
                primaryAdvanceAtDeadline = primary.playbackTimeSnapshot() - primaryStart
                secondaryAdvanceAtDeadline = secondary.playbackTimeSnapshot() - secondaryStart
            }
            let isAwaitingFinalRecovery = excursionStart.map {
                durationSeconds(from: $0, to: loopTime) <= 1
            } ?? false
            guard isWithinRequestedObservation || isAwaitingFinalRecovery else { break }

            // Bracket the secondary clock read with primary reads so main-actor
            // scheduling time is removed from the effective drift measurement.
            let primaryBefore = primary.playbackTimeSnapshot()
            let secondaryTime = secondary.playbackTimeSnapshot()
            let primaryAfter = primary.playbackTimeSnapshot()
            let primaryTime = (primaryBefore + primaryAfter) / 2
            let expectedSecondaryTime = session.secondaryTime(forPrimaryTime: primaryTime)
            let signedDrift = secondaryTime - expectedSecondaryTime
            let readUncertainty = abs(primaryAfter - primaryBefore) / 2
            let effectiveDrift = max(
                0,
                abs(signedDrift) - readUncertainty
            )
            let sampleTime = clock.now
            let secondaryRate = secondary.mpvPlayer?.rate ?? secondary.player?.rate ?? 0

            sampleCount += 1
            firstSignedDrift = firstSignedDrift ?? signedDrift
            lastSignedDrift = signedDrift
            finalEffectiveDrift = effectiveDrift
            minimumSecondaryRate = min(minimumSecondaryRate, secondaryRate)
            maximumSecondaryRate = max(maximumSecondaryRate, secondaryRate)
            worstDrift = max(worstDrift, effectiveDrift)
            if effectiveDrift <= driftTolerance {
                inToleranceCount += 1
                lastInTolerance = sampleTime
                if let currentExcursionStart = excursionStart {
                    longestExcursion = max(
                        longestExcursion,
                        durationSeconds(from: currentExcursionStart, to: sampleTime)
                    )
                    excursionStart = nil
                }
            } else if excursionStart == nil {
                excursionStart = sampleTime
            }

            try? await Task.sleep(for: .milliseconds(25))
        }

        let end = clock.now
        if let excursionStart {
            longestExcursion = max(
                longestExcursion,
                durationSeconds(from: excursionStart, to: end)
            )
        }
        return DriftObservation(
            sampleCount: sampleCount,
            inToleranceCount: inToleranceCount,
            worstDrift: worstDrift,
            longestExcursion: longestExcursion,
            lastInToleranceAge: durationSeconds(from: lastInTolerance, to: end),
            primaryAdvance: primaryAdvanceAtDeadline
                ?? primary.playbackTimeSnapshot() - primaryStart,
            secondaryAdvance: secondaryAdvanceAtDeadline
                ?? secondary.playbackTimeSnapshot() - secondaryStart,
            firstSignedDrift: firstSignedDrift ?? 0,
            lastSignedDrift: lastSignedDrift,
            finalEffectiveDrift: finalEffectiveDrift,
            minimumSecondaryRate: minimumSecondaryRate.isFinite ? minimumSecondaryRate : 0,
            maximumSecondaryRate: maximumSecondaryRate
        )
    }

    private func durationSeconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> TimeInterval {
        let duration = start.duration(to: end)
        return Double(duration.components.seconds) +
            Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func driftObservationDescription(
        _ observation: DriftObservation,
        backendPair: String
    ) -> String {
        let percent = observation.inToleranceFraction * 100
        return "pair=\(backendPair), samples=\(observation.sampleCount), " +
            "withinFrame=\(String(format: "%.1f", percent))%, " +
            "worstDrift=\(String(format: "%.3f", observation.worstDrift))s, " +
            "longestExcursion=\(String(format: "%.3f", observation.longestExcursion))s, " +
            "signedDrift=\(String(format: "%.3f", observation.firstSignedDrift))s→" +
            "\(String(format: "%.3f", observation.lastSignedDrift))s, " +
            "finalDrift=\(String(format: "%.3f", observation.finalEffectiveDrift))s, " +
            "secondaryRate=\(String(format: "%.2f", observation.minimumSecondaryRate))–" +
            "\(String(format: "%.2f", observation.maximumSecondaryRate)), " +
            "primaryAdvance=\(String(format: "%.3f", observation.primaryAdvance))s, " +
            "secondaryAdvance=\(String(format: "%.3f", observation.secondaryAdvance))s"
    }

    /// The regular suite intentionally keeps this short. The Compare Mode
    /// profiler opts into a longer run while exercising this exact same
    /// assertion path.
    private var sustainedPlaybackDuration: TimeInterval {
        guard let rawValue = ProcessInfo.processInfo.environment[
            "COMPARE_SUSTAINED_PLAYBACK_SECONDS"
        ],
        let requested = TimeInterval(rawValue),
        requested.isFinite else { return 8 }
        return min(max(requested, 2), 3_600)
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
        let manifestURL = url.appending(path: "MANIFEST.txt")
        let manifest = try? String(contentsOf: manifestURL, encoding: .utf8)
        guard manifest?.split(whereSeparator: \.isNewline).contains("schema=3") == true,
              requiredFiles.allSatisfy({
            FileManager.default.fileExists(atPath: url.appending(path: $0).path)
        }) else {
            throw XCTSkip(
                "Compare fixtures are unavailable or stale. Run " +
                    "scripts/generate-test-fixtures.sh or set MEDIA_FIXTURE_DIR " +
                    "to a schema=3 fixture tree."
            )
        }
        return url
    }

}
