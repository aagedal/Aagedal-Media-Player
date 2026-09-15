// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class GeneratedMediaFixtureTests: XCTestCase {
    @MainActor
    func testCommonFrameRates() async throws {
        let directory = try fixtureDirectory()
        let expectedRates: [(String, Int, Int)] = [
            ("23.976", 24_000, 1_001), ("24", 24, 1), ("25", 25, 1),
            ("29.97", 30_000, 1_001), ("30", 30, 1), ("50", 50, 1),
            ("59.94", 60_000, 1_001), ("60", 60, 1)
        ]

        for (name, numerator, denominator) in expectedRates {
            let url = directory.appending(path: "rates/\(name).mp4")
            let metadata = try await MetadataService.shared.metadata(for: url)
            let actualRate = try XCTUnwrap(metadata.primaryVideoStream?.frameRate, name)
            XCTAssertEqual(actualRate.numerator, numerator, name)
            XCTAssertEqual(actualRate.denominator, denominator, name)
        }
    }

    @MainActor
    func testDropFrameSourcesPreserveExactRatesThroughReviewReportsAndEditorExports() async throws {
        let directory = try fixtureDirectory()
        for (name, numerator, frame, expectedLabel): (String, Int64, Int64, String) in [
            ("29.97-minute", 30_000, 2, "00:01:00;02"),
            ("59.94-minute", 60_000, 4, "00:01:00;04"),
        ] {
            let url = directory.appending(path: "drop-frame-boundaries/\(name).mov")
            let metadata = try await MetadataService.shared.metadata(for: url)
            let actualRate = try XCTUnwrap(metadata.primaryVideoStream?.frameRate, name)
            XCTAssertEqual(actualRate.numerator, Int(numerator), name)
            XCTAssertEqual(actualRate.denominator, 1_001, name)
            var item = PlayerWindowCoordinator.makeMediaItem(for: url)
            item.metadata = metadata
            item.durationSeconds = metadata.duration ?? 0
            let snapshot = CompareReviewReportSnapshot(
                primaryItem: item, secondaryItem: item, alignmentMode: .sourceTimecode,
                notes: [CompareReviewNote(
                    primaryFrame: frame, primaryTime: 0, secondaryFrame: frame, secondaryTime: 0,
                    primaryRateNumerator: numerator, primaryRateDenominator: 1_001,
                    secondaryRateNumerator: numerator, secondaryRateDenominator: 1_001,
                    text: "Generated source at the drop-frame minute boundary"
                )]
            )
            XCTAssertEqual(snapshot.rows.first?.primarySourceTimecode, expectedLabel, name)
            XCTAssertEqual(snapshot.rows.first?.secondarySourceTimecode, expectedLabel, name)
            XCTAssertEqual(snapshot.primaryRateNumerator, numerator, name)
            XCTAssertEqual(snapshot.primaryRateDenominator, 1_001, name)
            XCTAssertTrue(snapshot.primaryUsesDropFrame, name)
            for format: CompareReviewReportFormat in [.csv, .resolveMarkersEDL, .finalCutProXML, .avidMarkersText] {
                let exported = String(decoding: try CompareReviewReportExporter.data(for: format, snapshot: snapshot), as: UTF8.self)
                XCTAssertTrue(exported.contains(expectedLabel), "\(name) \(format)")
            }
            let legacySnapshot = CompareReviewReportSnapshot(
                primaryItem: item, secondaryItem: item, alignmentMode: .sourceTimecode,
                notes: [CompareReviewNote(
                    primaryFrame: frame, primaryTime: 0, secondaryFrame: frame, secondaryTime: 0,
                    primaryRateNumerator: numerator == 30_000 ? 29_970 : 59_940, primaryRateDenominator: 1_000,
                    secondaryRateNumerator: numerator, secondaryRateDenominator: 1_001,
                    text: "Legacy rounded review coordinates must not silently change timebase"
                )]
            )
            XCTAssertNil(legacySnapshot.rows.first?.primarySourceTimecode, name)
            XCTAssertThrowsError(try CompareReviewReportExporter.finalCutProXML(snapshot: legacySnapshot), name)
        }
    }

    @MainActor
    func testEmbeddedDropFrameBoundaryTimecodes() async throws {
        let directory = try fixtureDirectory()
        let expectedLabels: [(String, String)] = [
            ("29.97-minute", "00:00:59;28"),
            ("29.97-ten-minute", "00:09:59;28"),
            ("29.97-hour", "00:59:59;28"),
            ("29.97-day-wrap", "23:59:59;28"),
            ("59.94-minute", "00:00:59;56")
        ]

        for (name, expectedLabel) in expectedLabels {
            let url = directory.appending(path: "drop-frame-boundaries/\(name).mov")
            let metadata = try await MetadataService.shared.metadata(for: url)
            XCTAssertEqual(metadata.timecode, expectedLabel, name)
        }
    }

    @MainActor
    func testRotationAndPixelAspectRatio() async throws {
        let url = try fixtureDirectory().appending(path: "rotation-par.mp4")
        let metadata = try await MetadataService.shared.metadata(for: url)
        let stream = try XCTUnwrap(metadata.primaryVideoStream)

        XCTAssertEqual(stream.width, 720)
        XCTAssertEqual(stream.height, 576)
        XCTAssertEqual(stream.pixelAspectRatio?.reducedStringValue, "64:45")
        XCTAssertEqual(abs(stream.rotation ?? 0), 90)
        XCTAssertEqual(stream.displayAspectRatio?.reducedStringValue, "9:16")
    }

    @MainActor
    func testHDR10Metadata() async throws {
        let url = try fixtureDirectory().appending(path: "hdr10.mp4")
        let metadata = try await MetadataService.shared.metadata(for: url)
        let stream = try XCTUnwrap(metadata.primaryVideoStream)

        XCTAssertEqual(stream.bitDepth, 10)
        XCTAssertEqual(stream.colorPrimaries, "bt2020")
        XCTAssertEqual(stream.colorTransfer, "smpte2084")
        XCTAssertEqual(stream.colorSpace, "bt2020nc")
        XCTAssertEqual(stream.maxCLL, 1_000)
        XCTAssertEqual(stream.maxFALL, 400)
    }

    @MainActor
    func testMultichannelAudio() async throws {
        let url = try fixtureDirectory().appending(path: "multichannel-5.1.m4a")
        let metadata = try await MetadataService.shared.metadata(for: url)
        let stream = try XCTUnwrap(metadata.audioStreams.first)

        XCTAssertEqual(stream.sampleRate, 48_000)
        XCTAssertEqual(stream.channels, 6)
        XCTAssertEqual(stream.bitDepth, 24)
    }

    @MainActor
    func testBundledFFmpegStreamsMultichannelPCM() async throws {
        let url = try fixtureDirectory().appending(path: "multichannel-5.1.m4a")
        let accumulator = StreamingWaveformAccumulator(
            width: 100,
            channelCount: 6,
            expectedFrameCount: 1_000
        )

        try await FFmpegService.runStreamingOutput(arguments: [
            "-hide_banner", "-loglevel", "error",
            "-i", url.path,
            "-vn", "-map", "0:a:0",
            "-ar", "1000",
            "-f", "f32le", "-c:a", "pcm_f32le",
            "pipe:1",
        ]) { data in
            accumulator.consume(data)
        }

        let channels = try accumulator.finish()
        XCTAssertEqual(channels.count, 6)
        for channel in channels {
            XCTAssertTrue(channel.maxs.contains { $0 > 0 })
            XCTAssertTrue(channel.mins.contains { $0 < 0 })
        }
    }

    @MainActor
    func testMPVAppliesAndClearsMultichannelMonitoringRoute() async throws {
        let controller = PlayerController(proResRAWDetector: { _, _ in false })
        defer { controller.teardown() }

        try await loadMultichannelFixture(into: controller)
        let backendConstructed = await waitUntil { controller.useMPV }
        XCTAssertTrue(backendConstructed)
        let mpv = try XCTUnwrap(controller.mpvPlayer)
        let layer = MPVMetalLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        layer.drawableSize = layer.frame.size
        mpv.attachDrawable(layer)

        let channelsLoaded = await waitUntil { controller.selectedAudioChannelCount == 6 }
        XCTAssertTrue(channelsLoaded)
        controller.setSessionAudioChannelRouting(
            AudioChannelRouting(channelCount: 6, soloedChannels: [2])
        )
        XCTAssertTrue(mpv.isAudioChannelFilterActive)

        controller.setSessionAudioChannelRouting(nil)
        XCTAssertFalse(mpv.isAudioChannelFilterActive)
    }

    @MainActor
    func testAVFoundationAppliesAndClearsMultichannelMonitoringRoute() async throws {
        let controller = PlayerController(proResRAWDetector: { _, _ in true })
        defer { controller.teardown() }

        try await loadMultichannelFixture(into: controller)
        let channelsLoaded = await waitUntil {
            controller.isReady && controller.selectedAudioChannelCount == 6
        }
        XCTAssertTrue(channelsLoaded)

        controller.setSessionAudioChannelRouting(
            AudioChannelRouting(channelCount: 6, soloedChannels: [2])
        )
        XCTAssertNotNil(controller.player?.currentItem?.audioMix)

        controller.setSessionAudioChannelRouting(nil)
        XCTAssertNil(controller.player?.currentItem?.audioMix)
    }

    @MainActor
    func testLiveMeterProductionPathMeasuresCompressedSourceIndependentlyOfMonitoring() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let controller = PlayerController(proResRAWDetector: { _, _ in true })
        let comparison = CompareSessionController()
        let defaultsSuite = "GeneratedMediaFixtureTests.LiveMeter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let session = LiveAudioMeterSession(
            primary: controller,
            comparison: comparison,
            defaults: defaults
        )
        defer {
            session.close()
            comparison.stop()
            controller.teardown()
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        try await loadMultichannelFixture(into: controller)
        let ready = await waitUntil {
            controller.isReady && !controller.useMPV && controller.selectedAudioChannelCount == 6
        }
        XCTAssertTrue(ready)

        session.start()
        let openedPaused = await waitUntil {
            if case .paused = session.coordinator.status { return true }
            return false
        }
        XCTAssertTrue(openedPaused)
        let generation = session.coordinator.generation

        controller.volume = 0
        controller.isMuted = true
        controller.setSessionAudioChannelRouting(
            AudioChannelRouting(channelCount: 6, soloedChannels: [0])
        )
        XCTAssertEqual(session.coordinator.generation, generation)

        // Advance the coordinator through its typed player-completion boundary
        // without depending on wall-clock AVPlayer scheduling.
        // The full suite deliberately saturates the machine with DSP and live
        // backend tests, which can make a one-second player outrun its decoder
        // even though the source/decode integration is correct.
        let playerState = controller.liveAudioMeterPlaybackSnapshot()
        session.coordinator.handlePlaybackEvent(.ended(.init(
            time: 1,
            phase: playerState.phase,
            isPlaying: false,
            rate: playerState.rate,
            preparationID: playerState.preparationID
        )))
        let completed = await waitUntil(timeout: .seconds(15)) {
            if case .ended = session.coordinator.status { return true }
            return false
        }
        XCTAssertTrue(
            completed,
            "Meter did not complete: \(session.coordinator.status); " +
                "diagnostics: \(session.viewState.diagnostics.map(\.detail))"
        )
        XCTAssertEqual(session.coordinator.generation, generation)
        XCTAssertEqual(session.viewState.selectedSourceID, LiveAudioMeterSession.primarySourceID)
        XCTAssertEqual(
            session.viewState.channels.map(\.label),
            (1...6).map { "Channel \($0)" },
            "The file declares a nonstandard 5.1 layout, so the meter must not invent speaker roles"
        )
        XCTAssertTrue(
            session.viewState.channels.allSatisfy {
                ($0.samplePeak.maximum ?? -.infinity) > -1
            },
            "Expected source-level peaks for every channel: \(session.viewState.channels)"
        )
        XCTAssertEqual(session.coordinator.provenance?.request.url,
                       try fixtureDirectory().appending(path: "multichannel-5.1.m4a"))
        XCTAssertEqual(session.coordinator.provenance?.request.audioStreamOrderIndex, 0)
        XCTAssertEqual(session.coordinator.provenance?.timestampFrameCount, 48_000)
        XCTAssertEqual(session.coordinator.provenance?.timestampTimeBase, "1/48000")
    }

    @MainActor
    func testLiveMeterProductionPathRejectsGeneratedCompressedTimestampGap() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "live-meter-session-gap-\(UUID().uuidString).m4a"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=1",
            "-af", "aselect=not(between(t\\,0.4\\,0.5))",
            "-c:a", "aac", url.path,
        ])

        let metadata = try await MetadataService.shared.metadata(for: url)
        XCTAssertEqual(metadata.audioStreams.first?.sampleRate, 48_000)
        let controller = PlayerController(proResRAWDetector: { _, _ in true })
        let comparison = CompareSessionController()
        let defaultsSuite = "GeneratedMediaFixtureTests.LiveMeterGap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let session = LiveAudioMeterSession(
            primary: controller, comparison: comparison, defaults: defaults
        )
        defer {
            session.close()
            comparison.stop()
            controller.teardown()
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.metadata = metadata
        item.durationSeconds = metadata.duration ?? 0
        item.hasVideoStream = false
        controller.loadMedia(item)
        controller.updateMetadata(item)
        let ready = await waitUntil(timeout: .seconds(10)) {
            controller.isReady
                && (try? controller.liveAudioMeterSource(id: "A", label: "Source A")) != nil
        }
        XCTAssertTrue(ready, "Generated compressed source must be selected before metering")
        guard ready else { return }

        session.start()
        let generation = session.coordinator.generation
        XCTAssertGreaterThan(generation, 0)
        let playerState = controller.liveAudioMeterPlaybackSnapshot()
        // Drive the same typed EOF boundary used by playback, granting the
        // paced decoder enough source time to reach the deliberately missing packets.
        session.coordinator.handlePlaybackEvent(.ended(.init(
            time: 1,
            phase: playerState.phase,
            isPlaying: false,
            rate: playerState.rate,
            preparationID: playerState.preparationID
        )))
        let rejected = await waitUntil(timeout: .seconds(15)) {
            if case .unavailable(_, let diagnostic) = session.viewState.status {
                return diagnostic?.contains("timestamp expected frame") == true
            }
            return false
        }
        XCTAssertTrue(
            rejected,
            "Expected actionable timestamp failure: \(session.coordinator.status); " +
                "diagnostics: \(session.viewState.diagnostics.map(\.detail))"
        )
        XCTAssertEqual(session.coordinator.generation, generation)
        XCTAssertNil(session.coordinator.snapshot)
        XCTAssertNil(session.coordinator.reducedSnapshot)
        XCTAssertNil(session.coordinator.provenance)
        XCTAssertTrue(session.viewState.canRetry)
    }

    @MainActor
    func testSubtitlesChaptersAndLongGOPFixture() async throws {
        let url = try fixtureDirectory().appending(path: "chapters-subtitles-long-gop.mkv")
        let metadata = try await MetadataService.shared.metadata(for: url)

        XCTAssertEqual(metadata.frameCount, 125)
        XCTAssertEqual(metadata.subtitleStreams.count, 1)
        XCTAssertEqual(metadata.subtitleStreams.first?.languageCode, "eng")
        XCTAssertEqual(metadata.subtitleStreams.first?.isDefault, true)
        XCTAssertEqual(metadata.chapters.map(\.title), ["Opening", "Closing"])
        XCTAssertEqual(metadata.chapters.map(\.startTime), [0, 2.5])
    }

    @MainActor
    private func fixtureDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"],
           !override.isEmpty {
            return try validateFixtureDirectory(URL(fileURLWithPath: override, isDirectory: true))
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        return try validateFixtureDirectory(
            repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        )
    }

    @MainActor
    private func validateFixtureDirectory(_ url: URL) throws -> URL {
        let manifest = url.appending(path: "MANIFEST.txt")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip(
                "Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh " +
                "or set MEDIA_FIXTURE_DIR."
            )
        }
        return url
    }

    @MainActor
    private func loadMultichannelFixture(into controller: PlayerController) async throws {
        let url = try fixtureDirectory().appending(path: "multichannel-5.1.m4a")
        let metadata = try await MetadataService.shared.metadata(for: url)
        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.metadata = metadata
        item.durationSeconds = metadata.duration ?? 0
        item.hasVideoStream = false
        controller.loadMedia(item)
        controller.updateMetadata(item)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
