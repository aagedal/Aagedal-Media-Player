// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import AVKit
import Foundation
import SwiftUI
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
    private static let driftSamplingInterval: Duration = .milliseconds(25)
    private static let driftRecoveryMeasurementTolerance: TimeInterval = 0.025

    private final class AVFoundationRenderSurface {
        let hostView: NSView
        let playerLayer: AVPlayerLayer

        init(player: AVPlayer, size: CGSize) {
            let frame = CGRect(origin: .zero, size: size)
            let hostView = NSView(frame: frame)
            hostView.wantsLayer = true
            hostView.layer = CALayer()

            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = frame
            playerLayer.videoGravity = .resizeAspect
            hostView.layer?.addSublayer(playerLayer)

            self.hostView = hostView
            self.playerLayer = playerLayer
        }
    }

    private enum RetainedPlaybackSurface {
        case mpv(MPVMetalLayer)
        case avFoundation(AVFoundationRenderSurface)
    }

    private final class ScopeRenderProbe {
        private(set) var renderCount = 0
        private(set) var renderedSources = Set<CompareScopeSource>()

        func record(source: CompareScopeSource) {
            renderCount += 1
            renderedSources.insert(source)
        }
    }

    private var retainedPlaybackSurfaces: [RetainedPlaybackSurface] = []

    override func setUp() async throws {
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["COMPARE_PROFILE_REPORT"] == "1" else { return }
        let expectsReflection = ProcessInfo.processInfo.environment["COMPARE_PROFILE_REFLECTED"] == "1"
        let fixtures = try fixtureDirectory()
        for source in ["source-a.mov", "source-b.mov"] {
            let reflected = await MPVDisplayTransform.requiresReflectionCorrection(
                url: fixtures.appending(path: "compare/\(source)")
            )
            XCTAssertEqual(reflected, expectsReflection,
                           "The profile must exercise the requested display-transform path: \(source)")
        }
    }

    override func tearDown() {
        for case .avFoundation(let surface) in retainedPlaybackSurfaces {
            surface.playerLayer.player = nil
        }
        retainedPlaybackSurfaces.removeAll()
        super.tearDown()
    }

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

    private struct VisualModeObservation {
        let updateCount: Int
        let coveredModeCount: Int
        let coveredGuideStateCount: Int
        let maximumSchedulingDelay: TimeInterval
        let canvasPixelSize: CGSize
    }

    private struct ScopeObservation {
        let renderUpdateCount: Int
        let coveredSourceCount: Int
        let renderedSources: String
        let maximumSchedulingDelay: TimeInterval
        let primaryCaptureAdvance: UInt64
        let secondaryCaptureAdvance: UInt64
    }

    func testMPVLoupeCapturesOrientedAsymmetricPixels() async throws {
        try await exerciseOrientedLoupePixels(backend: .mpv)
    }

    func testAVFoundationLoupeCapturesOrientedAsymmetricPixels() async throws {
        try await exerciseOrientedLoupePixels(backend: .avFoundation)
    }

    private func exerciseOrientedLoupePixels(backend: PlaybackBackend) async throws {
        // Expected colors are in display order: top-left, top-right,
        // bottom-left, bottom-right. Positive container rotation is CCW.
        let cases: [(String, [String])] = [
            ("landscape", ["red", "green", "blue", "yellow"]),
            ("portrait", ["red", "green", "blue", "yellow"]),
            ("par", ["red", "green", "blue", "yellow"]),
            ("rotate-90-par", ["green", "yellow", "red", "blue"]),
            ("rotate-180", ["yellow", "blue", "green", "red"]),
            ("rotate-270", ["blue", "red", "yellow", "green"]),
            ("mirror", ["green", "red", "yellow", "blue"]),
            ("mirror-90", ["yellow", "green", "blue", "red"]),
            ("mirror-270", ["red", "blue", "green", "yellow"]),
            ("mirror-vertical", ["blue", "yellow", "red", "green"]),
        ]
        let fixtures = try fixtureDirectory(requiredFiles: cases.map { "loupe/\($0.0).mp4" })
        for (name, expected) in cases {
            let controller = makeController(forcedBackend: backend)
            let capture = LoupeFrameCapture()
            defer { capture.stop(); controller.teardown() }
            let url = fixtures.appending(path: "loupe/\(name).mp4")
            let reflectionDetected = await MPVDisplayTransform.requiresReflectionCorrection(url: url)
            XCTAssertEqual(reflectionDetected, name.hasPrefix("mirror"), name)
            let metadata = try await MetadataService.shared.metadata(for: url)
            let stream = try XCTUnwrap(metadata.primaryVideoStream)
            let isPortrait = ["portrait", "rotate-90-par", "rotate-270", "mirror-90", "mirror-270"].contains(name)
            XCTAssertEqual(stream.displayAspectRatio?.reducedStringValue,
                           isPortrait ? "9:16" : "16:9", name)
            if name.contains("par") {
                XCTAssertEqual(stream.width, 240, name)
                XCTAssertEqual(stream.height, 180, name)
                XCTAssertEqual(stream.pixelAspectRatio?.reducedStringValue, "4:3", name)
            }
            try await loadPrimary(controller, url: url)
            try await attachRenderSurface(to: controller)
            guard await waitUntil({ controller.isReady }) else {
                XCTFail("\(backend.rawValue)/\(name): decoder did not become ready")
                continue
            }
            controller.pause()
            capture.start(controller: controller)
            guard await waitUntil({ capture.image != nil }) else {
                XCTFail("\(backend.rawValue)/\(name): paused loupe produced no image")
                continue
            }
            let image = try XCTUnwrap(capture.image)
            // MPV screenshots include PAR correction, while AV retains the
            // oriented coded raster and lets the loupe view apply display aspect.
            let expectedAspect: Double = if backend == .avFoundation && name.contains("par") {
                isPortrait ? 3.0 / 4.0 : 4.0 / 3.0
            } else {
                isPortrait ? 9.0 / 16.0 : 16.0 / 9.0
            }
            XCTAssertEqual(Double(image.width) / Double(image.height), expectedAspect,
                           accuracy: 0.01, "\(backend.rawValue)/\(name) captured aspect")
            let bitmap = NSBitmapImageRep(cgImage: image)
            let positions: [(Double, Double)] = [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            for (index, point) in positions.enumerated() {
                let color = try XCTUnwrap(bitmap.colorAt(
                    x: Int(Double(image.width) * point.0),
                    y: Int(Double(image.height) * point.1)
                )?.usingColorSpace(.deviceRGB))
                // Wide thresholds allow codec/color-management variation, while
                // each quadrant remains distinct from every other quadrant.
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                let target: [CGFloat] = switch expected[index] {
                case "red": [1, 0, 0]
                case "green": [0, 1, 0]
                case "blue": [0, 0, 1]
                default: [1, 1, 0]
                }
                for channel in 0..<3 {
                    XCTAssertEqual(channels[channel], target[channel], accuracy: 0.25,
                        "\(backend.rawValue)/\(name) quadrant \(index) expected \(expected[index]), got \(channels)")
                }
            }
            XCTAssertFalse(controller.isPlaying, "Capturing oriented pixels must preserve pause")
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

    func testMPVPrimaryAndAVFoundationSecondaryKeepSurfacesAcrossVisualModes() async throws {
        try await exerciseVisualModes(
            primaryBackend: .mpv,
            secondaryBackend: .avFoundation
        )
    }

    func testAVFoundationPrimaryAndMPVSecondaryKeepSurfacesAcrossVisualModes() async throws {
        try await exerciseVisualModes(
            primaryBackend: .avFoundation,
            secondaryBackend: .mpv
        )
    }

    func testMPVPrimaryAndAVFoundationSecondaryRenderLiveComparisonScopes() async throws {
        try await exerciseLiveScopes(
            primaryBackend: .mpv,
            secondaryBackend: .avFoundation
        )
    }

    func testAVFoundationPrimaryAndMPVSecondaryRenderLiveComparisonScopes() async throws {
        try await exerciseLiveScopes(
            primaryBackend: .avFoundation,
            secondaryBackend: .mpv
        )
    }

    func testMPVPrimaryAndAVFoundationSecondaryCapturePausedLoupesAlongsideScopes() async throws {
        try await exerciseLiveLoupes(primaryBackend: .mpv, secondaryBackend: .avFoundation)
    }

    func testAVFoundationPrimaryAndMPVSecondaryCapturePausedLoupesAlongsideScopes() async throws {
        try await exerciseLiveLoupes(primaryBackend: .avFoundation, secondaryBackend: .mpv)
    }

    func testMPVPrimaryAndAVFoundationSecondaryKeepReducedSurfacesAcrossVisualModes() async throws {
        try await exerciseVisualModes(
            primaryBackend: .mpv,
            secondaryBackend: .avFoundation,
            frameResolution: .reduced
        )
    }

    func testMPVPrimaryAndAVFoundationSecondaryUseRelativeAlignmentForMismatchedMasters() async throws {
        try await exerciseRelativeAlignment(
            primaryBackend: .mpv,
            secondaryBackend: .avFoundation
        )
    }

    func testAVFoundationPrimaryAndMPVSecondaryUseRelativeAlignmentForMismatchedMasters() async throws {
        try await exerciseRelativeAlignment(
            primaryBackend: .avFoundation,
            secondaryBackend: .mpv
        )
    }

    func testMPVPrimaryAndAVFoundationSecondaryApplyManualAlignmentDuringTransport() async throws {
        try await exerciseManualAlignment(primaryBackend: .mpv, secondaryBackend: .avFoundation)
    }

    func testAVFoundationPrimaryAndMPVSecondaryApplyManualAlignmentDuringTransport() async throws {
        try await exerciseManualAlignment(primaryBackend: .avFoundation, secondaryBackend: .mpv)
    }

    func testSupportedFrameRatesUseRelativeAlignmentAndPairedSeek() async throws {
        let fixtures = try fixtureDirectory(requiredFiles: [
            "rates/23.976.mp4",
            "rates/24.mp4",
            "rates/25.mp4",
            "rates/29.97.mp4",
            "rates/30.mp4",
            "rates/50.mp4",
            "rates/59.94.mp4",
            "rates/60.mp4",
        ])
        let rates: [(name: String, value: Double)] = [
            ("23.976", 24_000.0 / 1_001.0),
            ("24", 24),
            ("25", 25),
            ("29.97", 30_000.0 / 1_001.0),
            ("30", 30),
            ("50", 50),
            ("59.94", 60_000.0 / 1_001.0),
            ("60", 60),
        ]

        for rate in rates {
            let url = fixtures.appending(path: "rates/\(rate.name).mp4")
            try await exercisePreparedPair(
                primaryURL: url,
                secondaryURL: url,
                primaryBackend: .mpv,
                secondaryBackend: .avFoundation,
                seekTarget: 0.2,
                tolerance: 1 / rate.value,
                description: "\(rate.name) fps"
            ) { primary, secondary, session in
                XCTAssertEqual(session.mapping?.mode, .relative, rate.name)
                let primaryRate = try XCTUnwrap(
                    primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value,
                    rate.name
                )
                let secondaryRate = try XCTUnwrap(
                    secondary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value,
                    rate.name
                )
                XCTAssertEqual(
                    primaryRate,
                    rate.value,
                    accuracy: 0.001,
                    rate.name
                )
                XCTAssertEqual(
                    secondaryRate,
                    rate.value,
                    accuracy: 0.001,
                    rate.name
                )
                XCTAssertEqual(
                    CompareDriftPolicy(primaryFrameRate: rate.value).frameDuration,
                    1 / rate.value,
                    accuracy: 0.000_001,
                    rate.name
                )
            }
        }
    }

    func testRotatedAnamorphicAndPortraitPairShareDisplayGeometry() async throws {
        let fixtures = try fixtureDirectory(requiredFiles: [
            "rotation-par.mp4",
            "portrait.mp4",
        ])

        try await exercisePreparedPair(
            primaryURL: fixtures.appending(path: "rotation-par.mp4"),
            secondaryURL: fixtures.appending(path: "portrait.mp4"),
            primaryBackend: .mpv,
            secondaryBackend: .avFoundation,
            seekTarget: 0.75,
            tolerance: 1.0 / 25.0,
            description: "rotated/anamorphic and portrait"
        ) { primary, secondary, session in
            let primaryItem = try XCTUnwrap(primary.mediaItem)
            let secondaryItem = try XCTUnwrap(secondary.mediaItem)
            let primaryAspect = try XCTUnwrap(primaryItem.videoDisplayAspectRatio)
            let secondaryAspect = try XCTUnwrap(secondaryItem.videoDisplayAspectRatio)
            XCTAssertEqual(session.mapping?.mode, .relative)
            XCTAssertEqual(primaryAspect, 9.0 / 16.0, accuracy: 0.001)
            XCTAssertEqual(secondaryAspect, 9.0 / 16.0, accuracy: 0.001)

            let geometry = CompareDisplayGeometry(
                canvasSize: CGSize(width: 1_600, height: 900),
                primaryAspectRatio: primary.videoAspectRatio,
                secondaryAspectRatio: secondary.videoAspectRatio
            )
            XCTAssertTrue(geometry.displayAspectsMatch)
            XCTAssertEqual(
                geometry.primaryReferenceRect,
                CGRect(x: 546.875, y: 0, width: 506.25, height: 900)
            )
            XCTAssertTrue(
                CompareMediaComparison.mismatches(
                    primary: primaryItem,
                    secondary: secondaryItem
                ).contains { $0.kind == .raster }
            )
        }
    }

    func testSDRAndHDRPairExposeColorMismatchAndScopeTransferFunctions() async throws {
        let fixtures = try fixtureDirectory(requiredFiles: [
            "sdr-bt709.mp4",
            "hdr10.mp4",
        ])

        try await exercisePreparedPair(
            primaryURL: fixtures.appending(path: "sdr-bt709.mp4"),
            secondaryURL: fixtures.appending(path: "hdr10.mp4"),
            primaryBackend: .mpv,
            secondaryBackend: .avFoundation,
            seekTarget: 0.75,
            tolerance: 1.0 / 24.0,
            description: "SDR/HDR"
        ) { primary, secondary, session in
            let primaryItem = try XCTUnwrap(primary.mediaItem)
            let secondaryItem = try XCTUnwrap(secondary.mediaItem)
            XCTAssertEqual(session.mapping?.mode, .relative)

            let mismatchKinds = CompareMediaComparison.mismatches(
                primary: primaryItem,
                secondary: secondaryItem
            ).map(\.kind)
            XCTAssertTrue(mismatchKinds.contains(.transferFunction))
            XCTAssertTrue(mismatchKinds.contains(.colorPrimaries))

            guard case .sdr = primary.frameCapture.transferFunction else {
                XCTFail("The BT.709 primary did not configure SDR scope capture.")
                return
            }
            guard case .pq = secondary.frameCapture.transferFunction else {
                XCTFail("The HDR10 secondary did not configure PQ scope capture.")
                return
            }
            XCTAssertEqual(secondary.frameCapture.contentPeakNits, 1_000)
        }
    }

    func testDisjointSourceTimecodesClampToFirstSecondaryFrame() async throws {
        let fixtures = try fixtureDirectory(requiredFiles: [
            "compare/source-a.mov",
            "compare/disjoint-b.mov",
        ])
        let primaryURL = fixtures.appending(path: "compare/source-a.mov")
        let secondaryURL = fixtures.appending(path: "compare/disjoint-b.mov")
        let primary = makeController(forcedBackend: .avFoundation)
        let secondary = makeController(forcedBackend: .mpv)
        let session = CompareSessionController(secondaryController: secondary)

        defer {
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: primaryURL)
        let primaryBecameReady = await waitUntil { primary.isReady }
        guard primaryBecameReady else {
            XCTFail("Primary AVFoundation decoder did not become ready.")
            return
        }

        session.loadSecondary(secondaryURL, alignedWith: primary)
        let metadataFinishedLoading = await waitUntil {
            session.secondaryURL == secondaryURL
        }
        guard metadataFinishedLoading else {
            XCTFail("Disjoint comparison metadata did not finish loading.")
            return
        }
        try await attachRenderSurface(to: secondary)
        let secondaryBecameReady = await waitUntil { session.isSecondaryReady }
        guard secondaryBecameReady else {
            XCTFail("Secondary MPV decoder did not become ready.")
            return
        }

        let mapping = try XCTUnwrap(session.mapping)
        XCTAssertEqual(mapping.mode, .sourceTimecode)
        XCTAssertEqual(mapping.offset, -3_600, accuracy: 1.0 / 24.0)
        XCTAssertNil(
            mapping.primaryOverlapRange(
                primaryDuration: primary.mediaItem?.durationSeconds ?? 0
            )
        )

        // Move B away from the expected clamp point first so this assertion
        // cannot pass before the paired seek reaches the secondary backend.
        secondary.seekTo(2)
        let secondaryReachedSetupPosition = await waitUntil(tolerance: 1.0 / 24.0) {
            secondary.playbackTimeSnapshot() - 2
        }
        guard secondaryReachedSetupPosition else {
            XCTFail("Secondary setup seek did not complete.")
            return
        }

        session.seek(primary: primary, to: 2)
        let primaryReachedTarget = await waitUntil(tolerance: 1.0 / 24.0) {
            primary.playbackTimeSnapshot() - 2
        }
        XCTAssertTrue(primaryReachedTarget)
        let secondaryReturnedToFirstFrame = await waitUntil(tolerance: 1.0 / 24.0) {
            secondary.playbackTimeSnapshot()
        }
        XCTAssertTrue(secondaryReturnedToFirstFrame)

        let primaryPlaybackStart = primary.playbackTimeSnapshot()
        session.play(primary: primary)
        let primaryAdvanced = await waitUntil({
            primary.playbackTimeSnapshot() - primaryPlaybackStart >= 0.25
        }, timeout: .seconds(3))
        XCTAssertTrue(primaryAdvanced, "Primary did not advance across the disjoint range.")
        XCTAssertTrue(primary.isPlaying)
        XCTAssertFalse(
            secondary.isPlaying,
            "Secondary playback must stay paused before its source-timecode range."
        )
        XCTAssertEqual(
            secondary.playbackTimeSnapshot(),
            0,
            accuracy: 1.0 / 24.0,
            "Secondary playback moved away from its first-frame clamp."
        )
        session.pause(primary: primary)
    }

    func testMixedBackendsIsolateMatchingMultichannelAudioAndRestoreOnStop() async throws {
        let url = try fixtureDirectory(requiredFiles: [
            "multichannel-5.1.m4a",
        ]).appending(path: "multichannel-5.1.m4a")
        let primary = makeController(forcedBackend: .mpv)
        let secondary = makeController(forcedBackend: .avFoundation)
        let session = CompareSessionController(secondaryController: secondary)

        defer {
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: url)
        try await attachRenderSurface(to: primary)
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
        try await attachRenderSurface(to: primary)
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
        try await attachRenderSurface(to: secondary)
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

        // Keep playback active while the user drags for longer than the drift
        // correction cooldown. The session must give scrubbing exclusive
        // ownership of both clocks, then restart paired correction on release.
        for target in stride(from: 1.5, through: 2.1, by: 0.1) {
            session.scrub(primary: primary, to: target)
            try await Task.sleep(for: .milliseconds(50))
        }
        session.endScrubbing(primary: primary, at: 2.25)
        let activeScrubKeptPlaying = await waitUntil {
            primary.isPlaying && secondary.isPlaying
        }
        XCTAssertTrue(activeScrubKeptPlaying, "Active scrub did not resume paired playback.")
        let activeScrubConverged = await waitUntil(
            tolerance: driftPolicy.correctionThreshold,
            timeout: .seconds(2)
        ) {
            let expected = session.secondaryTime(
                forPrimaryTime: primary.playbackTimeSnapshot()
            )
            return secondary.playbackTimeSnapshot() - expected
        }
        XCTAssertTrue(
            activeScrubConverged,
            "Active scrub did not restore one-frame paired synchronization."
        )

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
            1 + Self.driftRecoveryMeasurementTolerance,
            "Drift correction did not recover within one second plus one sampling interval. " +
                observationDescription
        )
        XCTAssertLessThanOrEqual(
            observation.lastInToleranceAge,
            1 + Self.driftRecoveryMeasurementTolerance,
            "Drift did not reconverge during the final second plus one sampling interval. " +
                observationDescription
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

        session.seek(primary: primary, to: 1)
        let primaryReachedStepStart = await waitUntil(tolerance: frameDuration) {
            primary.playbackTimeSnapshot() - 1
        }
        XCTAssertTrue(primaryReachedStepStart, "Primary frame-step setup seek failed.")
        let secondaryReachedStepStart = await waitUntil(tolerance: frameDuration) {
            secondary.playbackTimeSnapshot() - 2
        }
        XCTAssertTrue(secondaryReachedStepStart, "Secondary frame-step setup seek failed.")

        session.seekByFrames(primary: primary, frameCount: 1)
        let steppedPrimaryTime = 1 + frameDuration
        let steppedSecondaryTime = 2 + frameDuration
        let primarySteppedOneFrame = await waitUntil(tolerance: frameDuration) {
            primary.playbackTimeSnapshot() - steppedPrimaryTime
        }
        XCTAssertTrue(primarySteppedOneFrame, "Primary frame step did not complete.")
        let secondarySteppedOneFrame = await waitUntil(tolerance: frameDuration) {
            secondary.playbackTimeSnapshot() - steppedSecondaryTime
        }
        XCTAssertTrue(secondarySteppedOneFrame, "Secondary frame step did not complete.")

        session.scrub(primary: primary, to: 1.5)
        session.endScrubbing(primary: primary, at: 1.5)
        let primaryCompletedScrub = await waitUntil(tolerance: frameDuration) {
            primary.playbackTimeSnapshot() - 1.5
        }
        XCTAssertTrue(primaryCompletedScrub, "Primary scrub did not complete.")
        let secondaryCompletedScrub = await waitUntil(tolerance: frameDuration) {
            secondary.playbackTimeSnapshot() - 2.5
        }
        XCTAssertTrue(secondaryCompletedScrub, "Secondary scrub did not complete.")

        session.fastForward(primary: primary)
        let shuttleStarted = await waitUntil {
            primary.isPlaying && secondary.isPlaying
        }
        XCTAssertTrue(shuttleStarted, "Paired forward shuttle did not start.")
        session.fastForward(primary: primary)
        let shuttleAccelerated = await waitUntil {
            primary.currentPlaybackSpeed > 1 && secondary.currentPlaybackSpeed > 1
        }
        XCTAssertTrue(shuttleAccelerated, "Paired forward shuttle did not accelerate.")
        session.pause(primary: primary)
        let shuttlePaused = await waitUntil {
            !primary.isPlaying && !secondary.isPlaying
        }
        XCTAssertTrue(shuttlePaused, "Paired forward shuttle did not pause.")

        session.setLoopPlayback(true, primary: primary)
        let loopSetupTime = max(0, (primary.mediaItem?.durationSeconds ?? 0) - 0.25)
        session.seek(primary: primary, to: loopSetupTime)
        let reachedLoopStart = await waitUntil(tolerance: frameDuration) {
            primary.playbackTimeSnapshot() - loopSetupTime
        }
        XCTAssertTrue(reachedLoopStart, "Primary loop setup seek failed.")
        session.play(primary: primary)
        let primaryWrapped = await waitUntil({
            primary.isPlaying && primary.playbackTimeSnapshot() < 0.5
        }, timeout: .seconds(3))
        XCTAssertTrue(primaryWrapped, "Primary did not loop back to its first frame.")
        // Decoder position and playing state arrive independently. Wait for
        // both within the same deadline: a settled seek alone can precede the
        // asynchronous resume notification, particularly after MPV reaches EOF.
        let secondaryFollowedLoop = await waitUntil({
            let expected = session.secondaryTime(
                forPrimaryTime: primary.playbackTimeSnapshot()
            )
            return secondary.isPlaying
                && abs(secondary.playbackTimeSnapshot() - expected) <= driftPolicy.correctionThreshold
        }, timeout: .seconds(2))
        XCTAssertTrue(
            secondaryFollowedLoop,
            "Secondary did not resume at the mapped frame after A looped. "
                + "A=\(primary.playbackTimeSnapshot()), B=\(secondary.playbackTimeSnapshot()), "
                + "B playing=\(secondary.isPlaying), tolerance=\(driftPolicy.correctionThreshold)"
        )
        session.setLoopPlayback(false, primary: primary)
        session.pause(primary: primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    private func exerciseManualAlignment(
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend
    ) async throws {
        let fixtures = try fixtureDirectory()
        let tolerance = 1.0 / 24.0
        try await exercisePreparedPair(
            primaryURL: fixtures.appending(path: "compare/source-a.mov"),
            secondaryURL: fixtures.appending(path: "compare/source-b.mov"),
            primaryBackend: primaryBackend,
            secondaryBackend: secondaryBackend,
            seekTarget: 2,
            tolerance: tolerance,
            description: "manual alignment \(primaryBackend.rawValue)/\(secondaryBackend.rawValue)"
        ) { primary, secondary, session in
            let automaticMapping = try XCTUnwrap(session.mapping)
            XCTAssertEqual(automaticMapping.mode, .sourceTimecode)
            session.pause(primary: primary)
            session.seek(primary: primary, to: 2)
            guard await self.waitUntil(tolerance: tolerance, difference: {
                primary.playbackTimeSnapshot() - 2
            }) else {
                XCTFail("Primary setup seek did not settle.")
                return
            }

            for offset in [0.5, -0.5] {
                session.setManualOffset(offset, primary: primary)
                XCTAssertEqual(session.mapping?.mode, .manual)
                let secondaryAligned = await self.waitUntil(tolerance: tolerance) {
                    secondary.playbackTimeSnapshot() - (2 + offset)
                }
                XCTAssertTrue(secondaryAligned, "Paused offset \(offset) did not reach B's decoder.")
                XCTAssertFalse(primary.isPlaying)
                XCTAssertFalse(secondary.isPlaying)
                XCTAssertEqual(primary.playbackTimeSnapshot(), 2, accuracy: tolerance)
            }

            session.play(primary: primary)
            let bothPlaying = await self.waitUntil { primary.isPlaying && secondary.isPlaying }
            XCTAssertTrue(bothPlaying)

            // Changing alignment can move the entire pair outside overlap.
            // A must keep advancing while B stays at the corresponding edge.
            let secondaryDuration = try XCTUnwrap(secondary.mediaItem).durationSeconds
            for offset in [-20.0, secondaryDuration] {
                session.setManualOffset(offset, primary: primary)
                XCTAssertEqual(
                    session.overlapStatus(primaryDuration: primary.mediaItem?.durationSeconds ?? 0),
                    .none
                )
                let boundary = offset < 0 ? 0 : secondaryDuration
                let reachedBoundary = await self.waitUntil(tolerance: tolerance + 0.001) {
                    secondary.playbackTimeSnapshot() - boundary
                }
                XCTAssertTrue(reachedBoundary, "B did not reach boundary for offset \(offset).")
                let primaryStart = primary.playbackTimeSnapshot()
                let primaryAdvanced = await self.waitUntil({
                    primary.playbackTimeSnapshot() - primaryStart >= 0.15
                }, timeout: .seconds(2))
                XCTAssertTrue(primaryAdvanced, "Alignment change stopped A.")
                XCTAssertFalse(secondary.isPlaying)
                XCTAssertEqual(secondary.playbackTimeSnapshot(), boundary, accuracy: tolerance + 0.001)

                session.setManualOffset(0.5, primary: primary)
                let resumedAndAligned = await self.waitUntil({
                    primary.isPlaying && secondary.isPlaying
                        && abs(secondary.playbackTimeSnapshot()
                               - session.secondaryTime(forPrimaryTime: primary.playbackTimeSnapshot()))
                            <= tolerance + 0.001
                }, timeout: .seconds(3))
                XCTAssertTrue(resumedAndAligned, "B did not resume at the edited mapping.")
            }

            session.setManualOffset(nil, primary: primary)
            XCTAssertEqual(session.mapping, automaticMapping)
            let restoredWhilePlaying = await self.waitUntil({
                primary.isPlaying && secondary.isPlaying
                    && abs(secondary.playbackTimeSnapshot()
                           - session.secondaryTime(forPrimaryTime: primary.playbackTimeSnapshot()))
                        <= tolerance + 0.001
            }, timeout: .seconds(3))
            XCTAssertTrue(restoredWhilePlaying, "Automatic alignment did not restore during playback.")
            session.pause(primary: primary)
        }
    }

    private func exerciseRelativeAlignment(
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend
    ) async throws {
        let fixtures = try fixtureDirectory(requiredFiles: [
            "compare/relative-a.mov",
            "compare/relative-b.mov",
        ])
        let primaryURL = fixtures.appending(path: "compare/relative-a.mov")
        let secondaryURL = fixtures.appending(path: "compare/relative-b.mov")
        let primary = makeController(forcedBackend: primaryBackend)
        let secondary = makeController(forcedBackend: secondaryBackend)
        let session = CompareSessionController(secondaryController: secondary)

        defer {
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: primaryURL)
        try await attachRenderSurface(to: primary)
        let primaryBecameReady = await waitUntil { primary.isReady }
        guard primaryBecameReady else {
            XCTFail("Primary \(primaryBackend.rawValue) decoder did not become ready.")
            return
        }

        session.loadSecondary(secondaryURL, alignedWith: primary)
        let metadataFinishedLoading = await waitUntil {
            session.secondaryURL == secondaryURL
        }
        guard metadataFinishedLoading else {
            XCTFail("Relative-alignment comparison metadata did not finish loading.")
            return
        }
        try await attachRenderSurface(to: secondary)
        let secondaryBecameReady = await waitUntil { session.isSecondaryReady }
        guard secondaryBecameReady else {
            XCTFail("Secondary \(secondaryBackend.rawValue) decoder did not become ready.")
            return
        }

        let mapping = try XCTUnwrap(session.mapping)
        XCTAssertEqual(mapping.mode, .relative)
        XCTAssertEqual(mapping.offset, 0)
        let primaryItem = try XCTUnwrap(primary.mediaItem)
        let secondaryItem = try XCTUnwrap(secondary.mediaItem)
        let primaryMetadata = try XCTUnwrap(primaryItem.metadata)
        let secondaryMetadata = try XCTUnwrap(secondaryItem.metadata)
        XCTAssertNil(primaryMetadata.timecode)
        XCTAssertNil(secondaryMetadata.timecode)
        let primaryVideo = try XCTUnwrap(primaryMetadata.primaryVideoStream)
        let secondaryVideo = try XCTUnwrap(secondaryMetadata.primaryVideoStream)
        XCTAssertEqual(primaryVideo.codec, "avc1")
        XCTAssertEqual(secondaryVideo.codec, "hvc1")
        XCTAssertEqual(primaryVideo.frameRate?.value, 24)
        XCTAssertEqual(secondaryVideo.frameRate?.value, 25)
        XCTAssertEqual(primaryVideo.width, 320)
        XCTAssertEqual(secondaryVideo.width, 240)
        XCTAssertEqual(primaryItem.durationSeconds, 5, accuracy: 0.05)
        XCTAssertEqual(secondaryItem.durationSeconds, 6, accuracy: 0.05)
        XCTAssertEqual(primaryMetadata.audioStreams.first?.codec, "mp4a")
        XCTAssertEqual(secondaryMetadata.audioStreams.first?.codec, "alac")

        session.seek(primary: primary, to: 1.25)
        let tolerance = 1.0 / 24.0
        let primaryReachedTarget = await waitUntil(tolerance: tolerance) {
            primary.playbackTimeSnapshot() - 1.25
        }
        XCTAssertTrue(primaryReachedTarget)
        let secondaryReachedTarget = await waitUntil(tolerance: tolerance) {
            secondary.playbackTimeSnapshot() - 1.25
        }
        XCTAssertTrue(secondaryReachedTarget)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    private func exerciseVisualModes(
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend,
        frameResolution: CompareFrameResolution = .full
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
        try await attachRenderSurface(to: primary)
        guard await waitUntil({ primary.isReady }) else {
            XCTFail("Primary decoder did not become ready for visual-mode validation.")
            return
        }

        session.loadSecondary(secondaryURL, alignedWith: primary)
        guard await waitUntil({ session.secondaryURL == secondaryURL }) else {
            XCTFail("Comparison metadata did not load for visual-mode validation.")
            return
        }
        try await attachRenderSurface(to: secondary)
        guard await waitUntil({ session.isSecondaryReady }) else {
            XCTFail(
                "Secondary decoder did not become ready for visual-mode validation: " +
                    (session.loadError ?? "no backend diagnostic")
            )
            return
        }

        let primaryItem = try XCTUnwrap(primary.mediaItem)
        let hostingView = NSHostingView(
            rootView: ComparePlayerView(
                primaryController: primary,
                compareSession: session,
                primaryWaveformGenerator: AudioWaveformGenerator(),
                primaryItem: primaryItem,
                showsAudioWaveform: false,
                isEditingTimecode: .constant(false),
                isTimelineFocused: .constant(false),
                isOverlayControlFocused: false,
                isTextInputActive: false,
                timecodeActivationTrigger: .constant(nil)
            )
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: visualCanvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()

        defer {
            window.contentView = nil
            window.close()
        }

        let mountedSurfaces = await waitUntil {
            self.metalLayers(in: hostingView).count == 1 &&
                self.avPlayerViews(in: hostingView).count == 1
        }
        guard mountedSurfaces else {
            XCTFail("The hosted comparison canvas did not mount both native surfaces.")
            return
        }

        if frameResolution != .full {
            let primaryPreparationBeforeReload = primary.preparationID
            let secondaryPreparationBeforeReload = secondary.preparationID
            session.setFrameResolution(frameResolution, primary: primary)

            guard await waitUntil({
                primary.preparationID > primaryPreparationBeforeReload &&
                    secondary.preparationID > secondaryPreparationBeforeReload &&
                    primary.isReady && secondary.isReady
            }) else {
                XCTFail("Both decoders did not become ready after the resolution reload.")
                return
            }
        }
        XCTAssertEqual(session.frameResolution, frameResolution)

        let primaryPreparationID = primary.preparationID
        let secondaryPreparationID = secondary.preparationID
        let primaryMPV = primary.mpvPlayer
        let primaryAVPlayer = primary.player
        let secondaryMPV = secondary.mpvPlayer
        let secondaryAVPlayer = secondary.player

        XCTAssertEqual(primary.preparationID, primaryPreparationID)
        XCTAssertEqual(secondary.preparationID, secondaryPreparationID)
        XCTAssertTrue(primary.mpvPlayer === primaryMPV)
        XCTAssertTrue(primary.player === primaryAVPlayer)
        XCTAssertTrue(secondary.mpvPlayer === secondaryMPV)
        XCTAssertTrue(secondary.player === secondaryAVPlayer)

        let metalLayer = try XCTUnwrap(metalLayers(in: hostingView).first)
        let avPlayerView = try XCTUnwrap(avPlayerViews(in: hostingView).first)
        let metalLayerIdentity = ObjectIdentifier(metalLayer)
        let avPlayerViewIdentity = ObjectIdentifier(avPlayerView)
        let expectedSurfaceSize = frameResolution.surfaceSize(for: visualCanvasSize)
        XCTAssertEqual(
            metalLayer.bounds.width,
            expectedSurfaceSize.width,
            accuracy: 1
        )
        XCTAssertEqual(
            metalLayer.bounds.height,
            expectedSurfaceSize.height,
            accuracy: 1
        )
        XCTAssertEqual(
            avPlayerView.bounds.width,
            expectedSurfaceSize.width,
            accuracy: 1
        )
        XCTAssertEqual(
            avPlayerView.bounds.height,
            expectedSurfaceSize.height,
            accuracy: 1
        )

        session.play(primary: primary)
        guard await waitUntil({ primary.isPlaying && secondary.isPlaying }) else {
            XCTFail("Both decoders did not start for visual-mode validation.")
            return
        }
        let primaryStart = primary.playbackTimeSnapshot()
        let secondaryStart = secondary.playbackTimeSnapshot()

        if isCompareProfile {
            try await Task.sleep(for: .milliseconds(750))
            let frameRate = primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
            let driftPolicy = CompareDriftPolicy(primaryFrameRate: frameRate)
            let visualTask = Task { @MainActor in
                await self.observeSustainedVisualModes(
                    session: session,
                    hostingView: hostingView,
                    window: window,
                    duration: self.sustainedPlaybackDuration
                )
            }
            let driftObservation = await observeSustainedDrift(
                primary: primary,
                secondary: secondary,
                session: session,
                driftTolerance: driftPolicy.correctionThreshold,
                duration: sustainedPlaybackDuration
            )
            let visualObservation = await visualTask.value
            let pairDescription = "\(primaryBackend.rawValue)/\(secondaryBackend.rawValue)"
            let driftDescription = driftObservationDescription(
                driftObservation,
                backendPair: pairDescription
            )
            let visualDescription = visualModeObservationDescription(
                visualObservation,
                backendPair: pairDescription
            )
            print("COMPARE_PROFILE_VISUAL \(visualDescription), \(driftDescription)")
            let attachment = XCTAttachment(
                string: "COMPARE_PROFILE_VISUAL \(visualDescription), \(driftDescription)"
            )
            attachment.name = "Compare Mode visual profile"
            attachment.lifetime = .keepAlways
            add(attachment)

            XCTAssertEqual(
                visualObservation.coveredModeCount,
                CompareViewMode.allCases.count,
                visualDescription
            )
            XCTAssertEqual(
                visualObservation.coveredGuideStateCount,
                CompareSafeAreaGuide.allCases.count * CompareAspectRatioGuide.allCases.count,
                visualDescription
            )
            XCTAssertGreaterThanOrEqual(
                visualObservation.updateCount,
                Int(sustainedPlaybackDuration * 4),
                "Visual controls did not remain interactive. \(visualDescription)"
            )
            XCTAssertLessThanOrEqual(
                visualObservation.maximumSchedulingDelay,
                0.25,
                "Visual updates stalled the main actor. \(visualDescription)"
            )
            XCTAssertTrue(
                primary.isPlaying && secondary.isPlaying,
                "A decoder stopped during sustained visual playback. \(driftDescription)"
            )
            assertSustainedPlayback(
                driftObservation,
                duration: sustainedPlaybackDuration,
                driftTolerance: driftPolicy.correctionThreshold,
                description: driftDescription
            )
        } else {
            for mode in CompareViewMode.allCases {
                session.viewMode = mode
                if mode.isWipe {
                    session.moveWipe(by: 0.1)
                }
                hostingView.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(120))

                XCTAssertEqual(session.viewMode, mode, mode.label)
                assertStableVisualSurfaces(
                    primary: primary,
                    secondary: secondary,
                    hostingView: hostingView,
                    primaryPreparationID: primaryPreparationID,
                    secondaryPreparationID: secondaryPreparationID,
                    primaryMPV: primaryMPV,
                    primaryAVPlayer: primaryAVPlayer,
                    secondaryMPV: secondaryMPV,
                    secondaryAVPlayer: secondaryAVPlayer,
                    metalLayerIdentity: metalLayerIdentity,
                    avPlayerViewIdentity: avPlayerViewIdentity,
                    description: mode.label
                )
                XCTAssertTrue(primary.isPlaying && secondary.isPlaying, mode.label)
            }

            XCTAssertEqual(session.wipePosition, 0.7, accuracy: 0.000_001)
        }

        assertStableVisualSurfaces(
            primary: primary,
            secondary: secondary,
            hostingView: hostingView,
            primaryPreparationID: primaryPreparationID,
            secondaryPreparationID: secondaryPreparationID,
            primaryMPV: primaryMPV,
            primaryAVPlayer: primaryAVPlayer,
            secondaryMPV: secondaryMPV,
            secondaryAVPlayer: secondaryAVPlayer,
            metalLayerIdentity: metalLayerIdentity,
            avPlayerViewIdentity: avPlayerViewIdentity,
            description: "final visual state"
        )
        XCTAssertGreaterThan(primary.playbackTimeSnapshot() - primaryStart, 0.5)
        XCTAssertGreaterThan(secondary.playbackTimeSnapshot() - secondaryStart, 0.5)
    }

    private func exerciseLiveLoupes(
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend
    ) async throws {
        let fixtures = try fixtureDirectory()
        let primaryURL = fixtures.appending(path: "compare/source-a.mov")
        let secondaryURL = fixtures.appending(path: "compare/source-b.mov")
        let primary = makeController(forcedBackend: primaryBackend)
        let secondary = makeController(forcedBackend: secondaryBackend)
        let session = CompareSessionController(secondaryController: secondary)
        let primaryLoupe = LoupeFrameCapture()
        let secondaryLoupe = LoupeFrameCapture()

        defer {
            primaryLoupe.stop()
            secondaryLoupe.stop()
            primary.frameCapture.stopCapture(rebuildPipeline: false)
            secondary.frameCapture.stopCapture(rebuildPipeline: false)
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: primaryURL)
        try await attachRenderSurface(to: primary)
        guard await waitUntil({ primary.isReady }) else {
            XCTFail("Primary decoder did not become ready for loupe validation.")
            return
        }
        session.loadSecondary(secondaryURL, alignedWith: primary)
        guard await waitUntil({ session.secondaryURL == secondaryURL }) else {
            XCTFail("Comparison metadata did not load for loupe validation.")
            return
        }
        try await attachRenderSurface(to: secondary)
        guard await waitUntil({ session.isSecondaryReady }) else {
            XCTFail("Secondary decoder did not become ready for loupe validation.")
            return
        }
        session.pause(primary: primary)
        session.seek(primary: primary, to: 1)
        guard await waitUntil({
            abs(primary.playbackTimeSnapshot() - 1) < 0.03 &&
                abs(secondary.playbackTimeSnapshot() - 2) < 0.03
        }) else {
            XCTFail("Paused loupe setup seek did not complete.")
            return
        }

        primary.frameCapture.startCapture()
        secondary.frameCapture.startCapture()
        let avItem = try XCTUnwrap(
            primaryBackend == .avFoundation
                ? primary.player?.currentItem : secondary.player?.currentItem
        )
        let scopeOutputCount = avItem.outputs.count
        let primaryPreparationID = primary.preparationID
        let secondaryPreparationID = secondary.preparationID
        primaryLoupe.start(controller: primary)
        secondaryLoupe.start(controller: secondary)
        guard await waitUntil({ primaryLoupe.image != nil && secondaryLoupe.image != nil }) else {
            XCTFail("Both paused decoders must provide loupe images without starting playback.")
            return
        }
        XCTAssertFalse(primary.isPlaying)
        XCTAssertFalse(secondary.isPlaying)
        for image in [try XCTUnwrap(primaryLoupe.image), try XCTUnwrap(secondaryLoupe.image)] {
            XCTAssertEqual(image.width, 320)
            XCTAssertEqual(image.height, 180)
        }
        XCTAssertEqual(avItem.outputs.count, scopeOutputCount + 1)
        let initialPrimaryPixels = try XCTUnwrap(loupePixels(primaryLoupe.image))
        let initialSecondaryPixels = try XCTUnwrap(loupePixels(secondaryLoupe.image))

        session.seek(primary: primary, to: 3)
        guard await waitUntil({
            self.loupePixels(primaryLoupe.image).map { $0 != initialPrimaryPixels } == true &&
                self.loupePixels(secondaryLoupe.image).map { $0 != initialSecondaryPixels } == true
        }) else {
            XCTFail("Paired paused seeks must refresh the pixels in both loupes.")
            return
        }
        // A fresh screenshot can arrive before the MPV time observation used
        // by relative frame stepping. Wait for the decoder and published clocks
        // so the next action starts from the requested frame on both backends.
        guard await waitUntil({
            abs(primary.playbackTimeSnapshot() - 3) < 0.001 &&
                abs(secondary.playbackTimeSnapshot() - 4) < 0.001 &&
                abs(primary.currentPlaybackTime - 3) < 0.001 &&
                abs(secondary.currentPlaybackTime - 4) < 0.001
        }) else {
            XCTFail("Paused seek clocks did not settle: " +
                "A=\(primary.playbackTimeSnapshot())/\(primary.currentPlaybackTime), " +
                "B=\(secondary.playbackTimeSnapshot())/\(secondary.currentPlaybackTime).")
            return
        }
        let soughtPrimaryPixels = try XCTUnwrap(loupePixels(primaryLoupe.image))
        let soughtSecondaryPixels = try XCTUnwrap(loupePixels(secondaryLoupe.image))
        session.seekByFrames(primary: primary, frameCount: 1)
        let steppedClocks = await waitUntil({
            abs(primary.playbackTimeSnapshot() - (3 + 1.0 / 24.0)) < 0.001 &&
                abs(secondary.playbackTimeSnapshot() - (4 + 1.0 / 24.0)) < 0.001
        })
        XCTAssertTrue(steppedClocks, "A paused frame step must advance both backend clocks.")
        let steppedImages = await waitUntil({
            self.loupePixels(primaryLoupe.image).map { $0 != soughtPrimaryPixels } == true &&
                self.loupePixels(secondaryLoupe.image).map { $0 != soughtSecondaryPixels } == true
        })
        XCTAssertTrue(steppedImages, "A paused frame step must refresh both loupe images: " +
            "A(\(primaryBackend.rawValue)) changed=\(loupePixels(primaryLoupe.image) != soughtPrimaryPixels), " +
            "clock=\(primary.playbackTimeSnapshot())/\(primary.currentPlaybackTime); " +
            "B(\(secondaryBackend.rawValue)) changed=\(loupePixels(secondaryLoupe.image) != soughtSecondaryPixels), " +
            "clock=\(secondary.playbackTimeSnapshot())/\(secondary.currentPlaybackTime).")
        let simultaneousScopeSamples = await waitUntil({
            primary.frameCapture.currentSample != nil && secondary.frameCapture.currentSample != nil
        })
        XCTAssertTrue(simultaneousScopeSamples, "Both scope captures must receive frames alongside the loupes.")

        let pausedPrimaryPixels = try XCTUnwrap(loupePixels(primaryLoupe.image))
        let pausedSecondaryPixels = try XCTUnwrap(loupePixels(secondaryLoupe.image))
        session.play(primary: primary)
        let liveImages = await waitUntil({
            self.loupePixels(primaryLoupe.image).map { $0 != pausedPrimaryPixels } == true &&
                self.loupePixels(secondaryLoupe.image).map { $0 != pausedSecondaryPixels } == true
        })
        XCTAssertTrue(liveImages, "Normal playback must refresh both loupe previews alongside scopes.")
        session.pause(primary: primary)

        primaryLoupe.stop()
        secondaryLoupe.stop()
        XCTAssertNil(primaryLoupe.image)
        XCTAssertNil(secondaryLoupe.image)
        XCTAssertEqual(avItem.outputs.count, scopeOutputCount)
        XCTAssertTrue(primary.frameCapture.isCapturing)
        XCTAssertTrue(secondary.frameCapture.isCapturing)
        let primarySequence = primary.frameCapture.currentSample?.sequence ?? 0
        let secondarySequence = secondary.frameCapture.currentSample?.sequence ?? 0
        session.play(primary: primary)
        let scopesContinued = await waitUntil({
            (primary.frameCapture.currentSample?.sequence ?? 0) > primarySequence &&
                (secondary.frameCapture.currentSample?.sequence ?? 0) > secondarySequence
        })
        XCTAssertTrue(scopesContinued, "Stopping loupes must leave both scope captures running.")
        XCTAssertNil(primaryLoupe.image, "Stopped captures must reject pending images.")
        XCTAssertNil(secondaryLoupe.image, "Stopped captures must reject pending images.")
        session.pause(primary: primary)

        primaryLoupe.start(controller: primary)
        secondaryLoupe.start(controller: secondary)
        let restarted = await waitUntil({ primaryLoupe.image != nil && secondaryLoupe.image != nil })
        XCTAssertTrue(restarted, "Both loupe captures must restart after being stopped.")
        XCTAssertEqual(primary.preparationID, primaryPreparationID)
        XCTAssertEqual(secondary.preparationID, secondaryPreparationID)
        XCTAssertEqual(avItem.outputs.count, scopeOutputCount + 1)

        session.stop()
        primary.teardown()
        let clearedAfterTeardown = await waitUntil({
            primaryLoupe.image == nil && secondaryLoupe.image == nil
        }, timeout: .seconds(2))
        XCTAssertTrue(clearedAfterTeardown, "Controller teardown must invalidate displayed loupe images.")
        primaryLoupe.start(controller: primary)
        secondaryLoupe.start(controller: secondary)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(primaryLoupe.image, "A torn-down controller must not resume loupe capture.")
        XCTAssertNil(secondaryLoupe.image, "A torn-down controller must not resume loupe capture.")
    }

    /// Normalize pixels before comparison so row padding and backend pixel
    /// formats cannot make an unchanged decoded frame appear fresh.
    private func loupePixels(_ image: CGImage?) -> Data? {
        guard let image else { return nil }
        var pixels = Data(count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return rendered ? pixels : nil
    }

    private func exerciseLiveScopes(
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend
    ) async throws {
        let fixtures = try fixtureDirectory()
        let primaryURL = fixtures.appending(path: "compare/source-a.mov")
        let secondaryURL = fixtures.appending(path: "compare/source-b.mov")
        let primary = makeController(forcedBackend: primaryBackend)
        let secondary = makeController(forcedBackend: secondaryBackend)
        let session = CompareSessionController(secondaryController: secondary)
        let renderProbe = ScopeRenderProbe()

        defer {
            primary.frameCapture.stopCapture(rebuildPipeline: false)
            secondary.frameCapture.stopCapture(rebuildPipeline: false)
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: primaryURL)
        try await attachRenderSurface(to: primary)
        guard await waitUntil({ primary.isReady }) else {
            XCTFail("Primary decoder did not become ready for live-scope validation.")
            return
        }

        session.loadSecondary(secondaryURL, alignedWith: primary)
        guard await waitUntil({ session.secondaryURL == secondaryURL }) else {
            XCTFail("Comparison metadata did not load for live-scope validation.")
            return
        }
        try await attachRenderSurface(to: secondary)
        guard await waitUntil({ session.isSecondaryReady }) else {
            XCTFail(
                "Secondary decoder did not become ready for live-scope validation: " +
                    (session.loadError ?? "no backend diagnostic")
            )
            return
        }

        let primaryPreparationID = primary.preparationID
        let secondaryPreparationID = secondary.preparationID
        let primaryMPV = primary.mpvPlayer
        let primaryAVPlayer = primary.player
        let secondaryMPV = secondary.mpvPlayer
        let secondaryAVPlayer = secondary.player
        let hostingView = NSHostingView(
            rootView: ScopeView(
                primaryController: primary,
                secondaryController: secondary,
                primaryFrameCapture: primary.frameCapture,
                secondaryFrameCapture: secondary.frameCapture,
                compareSession: session,
                onRender: { renderProbe.record(source: $0) }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()

        defer {
            window.contentView = nil
            window.close()
        }

        primary.frameCapture.startCapture()
        secondary.frameCapture.startCapture()
        session.play(primary: primary)
        guard await waitUntil({
            primary.isPlaying && secondary.isPlaying &&
                primary.frameCapture.currentSample != nil &&
                secondary.frameCapture.currentSample != nil
        }) else {
            XCTFail("Both decoders and frame captures did not start for live-scope validation.")
            return
        }

        let frameRate = primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
        let driftPolicy = CompareDriftPolicy(primaryFrameRate: frameRate)
        let scopeTask = Task { @MainActor in
            await self.observeSustainedScopes(
                session: session,
                renderProbe: renderProbe,
                primaryFrameCapture: primary.frameCapture,
                secondaryFrameCapture: secondary.frameCapture,
                hostingView: hostingView,
                window: window,
                duration: self.sustainedPlaybackDuration
            )
        }
        let driftObservation = await observeSustainedDrift(
            primary: primary,
            secondary: secondary,
            session: session,
            driftTolerance: driftPolicy.correctionThreshold,
            duration: sustainedPlaybackDuration
        )
        let scopeObservation = await scopeTask.value
        let pairDescription = "\(primaryBackend.rawValue)/\(secondaryBackend.rawValue)"
        let driftDescription = driftObservationDescription(
            driftObservation,
            backendPair: pairDescription
        )
        let scopeDescription = scopeObservationDescription(
            scopeObservation,
            backendPair: pairDescription
        )

        if isCompareProfile {
            print("COMPARE_PROFILE_SCOPE \(scopeDescription), \(driftDescription)")
            let attachment = XCTAttachment(
                string: "COMPARE_PROFILE_SCOPE \(scopeDescription), \(driftDescription)"
            )
            attachment.name = "Compare Mode live-scope profile"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertEqual(
            scopeObservation.coveredSourceCount,
            CompareScopeSource.allCases.count,
            "Every comparison scope source must produce live output. \(scopeDescription)"
        )
        XCTAssertGreaterThanOrEqual(
            scopeObservation.renderUpdateCount,
            CompareScopeSource.allCases.count,
            "Live scopes did not publish fresh output for every source. \(scopeDescription)"
        )
        XCTAssertGreaterThan(
            scopeObservation.primaryCaptureAdvance,
            0,
            "Source A scope capture stalled. \(scopeDescription)"
        )
        XCTAssertGreaterThan(
            scopeObservation.secondaryCaptureAdvance,
            0,
            "Source B scope capture stalled. \(scopeDescription)"
        )
        XCTAssertLessThanOrEqual(
            scopeObservation.maximumSchedulingDelay,
            0.25,
            "Live scope updates stalled the main actor. \(scopeDescription)"
        )
        XCTAssertEqual(primary.preparationID, primaryPreparationID)
        XCTAssertEqual(secondary.preparationID, secondaryPreparationID)
        XCTAssertTrue(primary.mpvPlayer === primaryMPV)
        XCTAssertTrue(primary.player === primaryAVPlayer)
        XCTAssertTrue(secondary.mpvPlayer === secondaryMPV)
        XCTAssertTrue(secondary.player === secondaryAVPlayer)
        XCTAssertTrue(
            primary.isPlaying && secondary.isPlaying,
            "A decoder stopped during live-scope playback. \(driftDescription)"
        )
        if isCompareProfile {
            // Release profiling owns the one-second recovery contract. Debug
            // instrumentation can lengthen AVFoundation's initial live-scope
            // pipeline transition without representing release playback.
            assertSustainedPlayback(
                driftObservation,
                duration: sustainedPlaybackDuration,
                driftTolerance: driftPolicy.correctionThreshold,
                description: driftDescription
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                driftObservation.primaryAdvance,
                sustainedPlaybackDuration - 1,
                "The primary clock stalled during live scopes. \(driftDescription)"
            )
            XCTAssertGreaterThanOrEqual(
                driftObservation.secondaryAdvance,
                sustainedPlaybackDuration - 1,
                "The secondary clock stalled during live scopes. \(driftDescription)"
            )
            XCTAssertLessThanOrEqual(
                driftObservation.finalEffectiveDrift,
                driftPolicy.correctionThreshold,
                "Live-scope drift did not finish within one frame. \(driftDescription)"
            )
        }
    }

    private func assertStableVisualSurfaces(
        primary: PlayerController,
        secondary: PlayerController,
        hostingView: NSView,
        primaryPreparationID: Int,
        secondaryPreparationID: Int,
        primaryMPV: MPVPlayer?,
        primaryAVPlayer: AVPlayer?,
        secondaryMPV: MPVPlayer?,
        secondaryAVPlayer: AVPlayer?,
        metalLayerIdentity: ObjectIdentifier,
        avPlayerViewIdentity: ObjectIdentifier,
        description: String
    ) {
        XCTAssertEqual(primary.preparationID, primaryPreparationID, description)
        XCTAssertEqual(secondary.preparationID, secondaryPreparationID, description)
        XCTAssertTrue(primary.mpvPlayer === primaryMPV, description)
        XCTAssertTrue(primary.player === primaryAVPlayer, description)
        XCTAssertTrue(secondary.mpvPlayer === secondaryMPV, description)
        XCTAssertTrue(secondary.player === secondaryAVPlayer, description)
        XCTAssertEqual(
            metalLayers(in: hostingView).first.map(ObjectIdentifier.init),
            Optional(metalLayerIdentity),
            description
        )
        XCTAssertEqual(
            avPlayerViews(in: hostingView).first.map(ObjectIdentifier.init),
            Optional(avPlayerViewIdentity),
            description
        )
    }

    private func exercisePreparedPair(
        primaryURL: URL,
        secondaryURL: URL,
        primaryBackend: PlaybackBackend,
        secondaryBackend: PlaybackBackend,
        seekTarget: TimeInterval,
        tolerance: TimeInterval,
        description: String,
        assertions: (
            _ primary: PlayerController,
            _ secondary: PlayerController,
            _ session: CompareSessionController
        ) async throws -> Void
    ) async throws {
        let primary = makeController(forcedBackend: primaryBackend)
        let secondary = makeController(forcedBackend: secondaryBackend)
        let session = CompareSessionController(secondaryController: secondary)

        defer {
            session.stop()
            primary.teardown()
        }

        try await loadPrimary(primary, url: primaryURL)
        try await attachRenderSurface(to: primary)
        guard await waitUntil({ primary.isReady }) else {
            XCTFail("Primary decoder did not become ready for \(description).")
            return
        }

        session.loadSecondary(secondaryURL, alignedWith: primary)
        guard await waitUntil({ session.secondaryURL == secondaryURL }) else {
            XCTFail("Comparison metadata did not load for \(description).")
            return
        }
        try await attachRenderSurface(to: secondary)
        guard await waitUntil({ session.isSecondaryReady }) else {
            XCTFail(
                "Secondary decoder did not become ready for \(description): " +
                    (session.loadError ?? "no backend diagnostic")
            )
            return
        }

        try await assertions(primary, secondary, session)

        session.seek(primary: primary, to: seekTarget)
        let primaryReachedTarget = await waitUntil(tolerance: tolerance) {
            primary.playbackTimeSnapshot() - seekTarget
        }
        XCTAssertTrue(primaryReachedTarget, "Primary seek failed for \(description).")
        let expectedSecondaryTime = session.secondaryTime(forPrimaryTime: seekTarget)
        let secondaryReachedTarget = await waitUntil(tolerance: tolerance) {
            secondary.playbackTimeSnapshot() - expectedSecondaryTime
        }
        XCTAssertTrue(secondaryReachedTarget, "Secondary seek failed for \(description).")
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

    private func attachRenderSurface(to controller: PlayerController) async throws {
        guard await waitUntil({ controller.useMPV || controller.player != nil }) else {
            XCTFail("The forced playback backend was not constructed.")
            return
        }
        let size = renderSurfaceSize
        let frame = CGRect(origin: .zero, size: size)

        if controller.useMPV {
            let mpv = try XCTUnwrap(controller.mpvPlayer)
            let layer = MPVMetalLayer()
            layer.frame = frame
            layer.drawableSize = size
            mpv.attachDrawable(layer)

            XCTAssertEqual(layer.frame.size, size)
            XCTAssertEqual(layer.drawableSize, size)
            retainedPlaybackSurfaces.append(.mpv(layer))
        } else {
            let player = try XCTUnwrap(controller.player)
            let surface = AVFoundationRenderSurface(player: player, size: size)

            XCTAssertTrue(surface.playerLayer.player === player)
            XCTAssertTrue(surface.playerLayer.superlayer === surface.hostView.layer)
            XCTAssertEqual(surface.playerLayer.frame.size, size)
            retainedPlaybackSurfaces.append(.avFoundation(surface))
        }
    }

    private func metalLayers(in view: NSView) -> [MPVMetalLayer] {
        descendantViews(in: view).compactMap { $0.layer as? MPVMetalLayer }
    }

    private func avPlayerViews(in view: NSView) -> [AVPlayerView] {
        descendantViews(in: view).compactMap { $0 as? AVPlayerView }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendantViews(in:))
    }

    private var renderSurfaceSize: CGSize {
        let fallback = CGSize(width: 320, height: 180)
        guard let rawValue = ProcessInfo.processInfo.environment[
            "COMPARE_PROFILE_RENDER_SIZE"
        ], !rawValue.isEmpty else { return fallback }

        let dimensions = rawValue.lowercased().split(separator: "x")
        guard dimensions.count == 2,
              let width = Int(dimensions[0]),
              let height = Int(dimensions[1]),
              width > 0,
              height > 0 else {
            XCTFail("COMPARE_PROFILE_RENDER_SIZE must use WIDTHxHEIGHT with positive integers.")
            return fallback
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    private var visualCanvasSize: CGSize {
        guard isCompareProfile else { return CGSize(width: 960, height: 540) }
        let backingScale = max(1, NSScreen.main?.backingScaleFactor ?? 1)
        return CGSize(
            width: renderSurfaceSize.width / backingScale,
            height: renderSurfaceSize.height / backingScale
        )
    }

    private var isCompareProfile: Bool {
        ProcessInfo.processInfo.environment["COMPARE_PROFILE_REPORT"] == "1"
    }

    private func observeSustainedVisualModes(
        session: CompareSessionController,
        hostingView: NSView,
        window: NSWindow,
        duration: TimeInterval
    ) async -> VisualModeObservation {
        let clock = ContinuousClock()
        let cadence: Duration = .milliseconds(100)
        let cadenceSeconds = 0.1
        let start = clock.now
        let deadline = start.advanced(by: .seconds(duration))
        var expectedUpdate = start
        var updateCount = 0
        var coveredModes = Set<CompareViewMode>()
        var coveredGuideStates = Set<String>()
        var maximumSchedulingDelay: TimeInterval = 0

        while clock.now < deadline {
            let now = clock.now
            maximumSchedulingDelay = max(
                maximumSchedulingDelay,
                max(0, durationSeconds(from: expectedUpdate, to: now))
            )

            let mode = CompareViewMode.allCases[updateCount % CompareViewMode.allCases.count]
            coveredModes.insert(mode)
            session.viewMode = mode
            let safeAreaGuide = CompareSafeAreaGuide.allCases[
                updateCount % CompareSafeAreaGuide.allCases.count
            ]
            let aspectRatioGuide = CompareAspectRatioGuide.allCases[
                (updateCount / CompareSafeAreaGuide.allCases.count) %
                    CompareAspectRatioGuide.allCases.count
            ]
            session.safeAreaGuide = safeAreaGuide
            session.aspectRatioGuide = aspectRatioGuide
            coveredGuideStates.insert("\(safeAreaGuide.rawValue)/\(aspectRatioGuide.rawValue)")
            switch mode {
            case .verticalWipe, .horizontalWipe:
                session.setWipePosition(Double(updateCount % 11) / 10)
            case .overlay:
                session.setOverlayBlend(Double(updateCount % 11) / 10)
            case .difference:
                let gainRange = CompareSessionController.maximumDifferenceGain -
                    CompareSessionController.minimumDifferenceGain
                session.setDifferenceGain(
                    CompareSessionController.minimumDifferenceGain +
                        gainRange * Double(updateCount % 11) / 10
                )
            case .sideBySide, .primary, .secondary:
                break
            }
            hostingView.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            updateCount += 1

            expectedUpdate = expectedUpdate.advanced(by: cadence)
            let remaining = clock.now.duration(to: expectedUpdate)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            } else if durationSeconds(from: expectedUpdate, to: clock.now) > cadenceSeconds {
                expectedUpdate = clock.now
            }
        }

        let canvasPixelSize = hostingView.convertToBacking(hostingView.bounds).size
        return VisualModeObservation(
            updateCount: updateCount,
            coveredModeCount: coveredModes.count,
            coveredGuideStateCount: coveredGuideStates.count,
            maximumSchedulingDelay: maximumSchedulingDelay,
            canvasPixelSize: canvasPixelSize
        )
    }

    private func observeSustainedScopes(
        session: CompareSessionController,
        renderProbe: ScopeRenderProbe,
        primaryFrameCapture: FrameCapture,
        secondaryFrameCapture: FrameCapture,
        hostingView: NSView,
        window: NSWindow,
        duration: TimeInterval
    ) async -> ScopeObservation {
        let clock = ContinuousClock()
        let cadence: Duration = .milliseconds(100)
        let sourceHoldTicks = 12
        let start = clock.now
        let deadline = start.advanced(by: .seconds(duration))
        let primaryStartSequence = primaryFrameCapture.currentSample?.sequence ?? 0
        let secondaryStartSequence = secondaryFrameCapture.currentSample?.sequence ?? 0
        var expectedUpdate = start
        var tickCount = 0
        var maximumSchedulingDelay: TimeInterval = 0

        while clock.now < deadline {
            let now = clock.now
            maximumSchedulingDelay = max(
                maximumSchedulingDelay,
                max(0, durationSeconds(from: expectedUpdate, to: now))
            )

            if tickCount % sourceHoldTicks == 0 {
                let sourceIndex = (tickCount / sourceHoldTicks) % CompareScopeSource.allCases.count
                let source = CompareScopeSource.allCases[sourceIndex]
                session.scopeSource = source
                if source == .difference {
                    let gainRange = CompareSessionController.maximumDifferenceGain -
                        CompareSessionController.minimumDifferenceGain
                    session.setDifferenceGain(
                        CompareSessionController.minimumDifferenceGain +
                            gainRange * Double((tickCount / sourceHoldTicks) % 5) / 4
                    )
                }
            }

            hostingView.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            tickCount += 1

            expectedUpdate = expectedUpdate.advanced(by: cadence)
            let remaining = clock.now.duration(to: expectedUpdate)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            } else if durationSeconds(from: expectedUpdate, to: clock.now) > 0.1 {
                expectedUpdate = clock.now
            }
        }

        let primaryEndSequence = primaryFrameCapture.currentSample?.sequence ?? 0
        let secondaryEndSequence = secondaryFrameCapture.currentSample?.sequence ?? 0
        return ScopeObservation(
            renderUpdateCount: renderProbe.renderCount,
            coveredSourceCount: renderProbe.renderedSources.count,
            renderedSources: renderProbe.renderedSources
                .map(\.rawValue)
                .sorted()
                .joined(separator: ","),
            maximumSchedulingDelay: maximumSchedulingDelay,
            primaryCaptureAdvance: primaryEndSequence >= primaryStartSequence
                ? primaryEndSequence - primaryStartSequence : 0,
            secondaryCaptureAdvance: secondaryEndSequence >= secondaryStartSequence
                ? secondaryEndSequence - secondaryStartSequence : 0
        )
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

            try? await Task.sleep(for: Self.driftSamplingInterval)
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

    private func visualModeObservationDescription(
        _ observation: VisualModeObservation,
        backendPair: String
    ) -> String {
        "pair=\(backendPair), " +
            "canvas=\(Int(observation.canvasPixelSize.width))x" +
            "\(Int(observation.canvasPixelSize.height)), " +
            "visualUpdates=\(observation.updateCount), " +
            "coveredModes=\(observation.coveredModeCount)/\(CompareViewMode.allCases.count), " +
            "coveredGuideStates=\(observation.coveredGuideStateCount)/" +
            "\(CompareSafeAreaGuide.allCases.count * CompareAspectRatioGuide.allCases.count), " +
            "maxMainActorDelay=" +
            "\(String(format: "%.3f", observation.maximumSchedulingDelay))s"
    }

    private func scopeObservationDescription(
        _ observation: ScopeObservation,
        backendPair: String
    ) -> String {
        "pair=\(backendPair), " +
            "scopeRenders=\(observation.renderUpdateCount), " +
            "coveredSources=\(observation.coveredSourceCount)/\(CompareScopeSource.allCases.count), " +
            "renderedSourceNames=\(observation.renderedSources), " +
            "captureAdvance=\(observation.primaryCaptureAdvance)/" +
            "\(observation.secondaryCaptureAdvance), " +
            "maxMainActorDelay=" +
            "\(String(format: "%.3f", observation.maximumSchedulingDelay))s"
    }

    private func assertSustainedPlayback(
        _ observation: DriftObservation,
        duration: TimeInterval,
        driftTolerance: TimeInterval,
        description: String
    ) {
        XCTAssertGreaterThanOrEqual(
            observation.primaryAdvance,
            duration - 1,
            "The primary clock stalled or reached EOF. \(description)"
        )
        XCTAssertGreaterThanOrEqual(
            observation.secondaryAdvance,
            duration - 1,
            "The secondary clock stalled or reached EOF. \(description)"
        )
        XCTAssertLessThanOrEqual(
            observation.longestExcursion,
            1 + Self.driftRecoveryMeasurementTolerance,
            "Drift correction did not recover within one second plus one sampling interval. " +
                description
        )
        XCTAssertLessThanOrEqual(
            observation.lastInToleranceAge,
            1 + Self.driftRecoveryMeasurementTolerance,
            "Drift did not reconverge during the final second plus one sampling interval. " +
                description
        )
        XCTAssertLessThanOrEqual(
            observation.finalEffectiveDrift,
            driftTolerance,
            "Drift finished outside one-frame tolerance. \(description)"
        )
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

    private func fixtureDirectory(
        requiredFiles: [String] = [
            "compare/source-a.mov",
            "compare/source-b.mov",
        ]
    ) throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"],
           !override.isEmpty {
            return try validateFixtureDirectory(
                URL(fileURLWithPath: override, isDirectory: true),
                requiredFiles: requiredFiles
            )
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        return try validateFixtureDirectory(
            repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory),
            requiredFiles: requiredFiles
        )
    }

    private func validateFixtureDirectory(
        _ url: URL,
        requiredFiles: [String]
    ) throws -> URL {
        let requiredFiles = ["MANIFEST.txt"] + requiredFiles
        let manifestURL = url.appending(path: "MANIFEST.txt")
        let manifest = try? String(contentsOf: manifestURL, encoding: .utf8)
        guard manifest?.split(whereSeparator: \.isNewline).contains("schema=5") == true,
              requiredFiles.allSatisfy({
            FileManager.default.fileExists(atPath: url.appending(path: $0).path)
        }) else {
            throw XCTSkip(
                "Compare fixtures are unavailable or stale (schema 5). Run " +
                    "scripts/generate-test-fixtures.sh or set MEDIA_FIXTURE_DIR " +
                    "to a schema=5 fixture tree."
            )
        }
        return url
    }

}
