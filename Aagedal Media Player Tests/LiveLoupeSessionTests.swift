// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LiveLoupeSessionTests: XCTestCase {
    private var controllers: [PlayerController] = []
    private var sessions: [LiveLoupeSession] = []
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        sessions.forEach { $0.stop() }
        controllers.forEach { $0.teardown() }
        windows.forEach { $0.close() }
        sessions.removeAll(); controllers.removeAll(); windows.removeAll()
        try await super.tearDown()
    }

    func testViewportRejectsNativeProofAndInvalidSizesAndKeepsEdgesCentered() throws {
        XCTAssertNil(LoupeVideoViewport(pictureSize: .zero, lensSize: CGSize(width: 180, height: 140),
            normalizedPoint: .zero, magnification: .twoTimes))
        XCTAssertNil(LoupeVideoViewport(pictureSize: CGSize(width: 320, height: 180),
            lensSize: CGSize(width: 180, height: 140), normalizedPoint: .zero, magnification: .nativePixels))
        for point in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)] {
            let viewport = try XCTUnwrap(LoupeVideoViewport(pictureSize: CGSize(width: 320, height: 180),
                lensSize: CGSize(width: 160, height: 120), normalizedPoint: point, magnification: .fourTimes))
            XCTAssertEqual(viewport.zoom, 3, accuracy: 0.0001)
            XCTAssertEqual(viewport.panX, 0.5 - Double(point.x))
            XCTAssertEqual(viewport.panY, 0.5 - Double(point.y))
        }
    }

    func testLoopClockMeasuresPhaseAndRejectsBracketsAcrossEOF() throws {
        let sample = try XCTUnwrap(LiveLoupeClock.sample(readPrimary: { 0.01 },
            readSecondary: { 1.99 }, loopDuration: 2))
        XCTAssertEqual(sample.signedDrift, -0.02, accuracy: 0.0001)
        var readings = [1.99, 0.01].makeIterator()
        XCTAssertNil(LiveLoupeClock.sample(readPrimary: { readings.next()! },
            readSecondary: { 1.99 }, loopDuration: 2))
    }

    func testFollowerTracksTemporarySourceRateWithoutChangingTransportSpeed() async throws {
        let pair = try await makePair(url: fixture("landscape"))
        let primary = try XCTUnwrap(pair.controller.mpvPlayer)
        let child = try XCTUnwrap(pair.session.player)
        pair.controller.play()
        let running = await waitUntil { pair.session.isReady && child.isPlaying }
        XCTAssertTrue(running)
        // Compare Mode changes only the backend rate during clock recovery.
        // Repeating both directions also checks restoration of the base rate.
        for rate in [Float(1.5), 1, 0.5, 1, 1.5, 1] {
            pair.controller.setSynchronizationPlaybackRate(rate)
            try await Task.sleep(for: .milliseconds(175))
            XCTAssertEqual(pair.controller.currentPlaybackSpeed, 1)
            XCTAssertEqual(child.rate, rate, accuracy: rate * 0.051,
                "The follower must apply its correction around the source's effective rate")
            XCTAssertTrue(pair.session.isReady)
            let loopDuration = primary.duration
            let drift = await Task.detached {
                LiveLoupeClock.sample(readPrimary: { primary.playbackTimeSnapshot() ?? .nan },
                    readSecondary: { child.playbackTimeSnapshot() ?? .nan }, loopDuration: loopDuration)
            }.value
            XCTAssertLessThanOrEqual(try XCTUnwrap(drift).effectiveDrift, 0.1)
        }
        XCTAssertTrue(pair.session.player === child)
    }

    func testResizingLensUpdatesOutputWithoutReloadingPrimary() async throws {
        let pair = try await makePair(url: fixture("landscape"))
        let primary = try XCTUnwrap(pair.controller.mpvPlayer)
        let child = try XCTUnwrap(pair.session.player)
        let view = try XCTUnwrap(pair.window.contentView?.subviews.compactMap {
            $0 as? LiveLoupeVideoSurface.SurfaceView
        }.first)
        view.setFrameSize(CGSize(width: 160, height: 100))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        var correctSize = false
        for _ in 0..<30 {
            let current = pair.session.player
            let raw = await Task.detached { current?.screenshotRaw(scaledToWindow: true) }.value
            if raw?.width == Int(pair.liveLayer.drawableSize.width),
               raw?.height == Int(pair.liveLayer.drawableSize.height) { correctSize = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(correctSize, "The output must follow the lens even when its zoom factor is unchanged")
        let centered = await waitForColor(.red, player: try XCTUnwrap(pair.session.player), x: 0.5, y: 0.5)
        XCTAssertTrue(centered)
        XCTAssertNil(child.playbackTimeSnapshot(), "The obsolete follower must be destroyed after resizing")
        XCTAssertTrue(pair.controller.mpvPlayer === primary)
    }

    func testFileReplacementAndSurfaceRebindingReleaseOnlyObsoletePlayers() async throws {
        let pair = try await makePair(url: fixture("landscape"))
        let originalPrimary = try XCTUnwrap(pair.controller.mpvPlayer)
        let originalChild = try XCTUnwrap(pair.session.player)
        pair.controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: try fixture("portrait")))
        XCTAssertFalse(pair.session.isReady(for: pair.controller), "The old file's viewer must be rejected immediately")
        let replaced = await waitUntil {
            pair.controller.mpvPlayer != nil && pair.controller.mpvPlayer !== originalPrimary
        }
        XCTAssertTrue(replaced)
        try XCTUnwrap(pair.controller.mpvPlayer).attachDrawable(pair.mainLayer)
        let ready = await waitUntil { pair.controller.isReady && pair.session.isReady }
        XCTAssertTrue(ready)
        XCTAssertNil(originalChild.playbackTimeSnapshot())
        let previousChild = try XCTUnwrap(pair.session.player)
        let replacement = LiveLoupeVideoSurface.SurfaceView(frame: CGRect(x: 660, y: 160, width: 160, height: 120))
        replacement.session = pair.session
        pair.window.contentView?.addSubview(replacement)
        pair.session.attachSurface(replacement.metalLayer)
        pair.session.detachSurface(pair.liveLayer)
        let rebound = await waitUntil { pair.session.isReady && pair.session.player !== previousChild }
        XCTAssertTrue(rebound)
        XCTAssertNil(previousChild.playbackTimeSnapshot())
        XCTAssertNotNil(pair.controller.mpvPlayer?.playbackTimeSnapshot())
        pair.session.stop()
    }

    func testGPUViewportMatchesSelectedQuadrantsIncludingRotationReflectionAndEdges() async throws {
        let cases: [(String, [NSColor])] = [
            ("landscape", [.red, .green, .blue, .yellow]),
            ("rotate-90-par", [.green, .yellow, .red, .blue]),
            ("mirror", [.green, .red, .yellow, .blue]),
            ("mirror-vertical", [.blue, .yellow, .red, .green])
        ]
        for (name, colors) in cases {
            let pair = try await makePair(url: fixture(name))
            let child = try XCTUnwrap(pair.session.player)
            XCTAssertTrue(child.isAudioTrackSelectionDisabled)
            XCTAssertTrue(child.isMuted)
            XCTAssertFalse(child.canInspectDecoderRaster)
            for magnification in [LoupeMagnification.twoTimes, .fourTimes, .eightTimes, .sixteenTimes] {
                for (index, point) in [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.25),
                                       CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.75, y: 0.75)].enumerated() {
                    configure(pair, point: point, magnification: magnification)
                    let matched = await waitForColor(colors[index], player: child, x: 0.5, y: 0.5)
                    XCTAssertTrue(matched, "\(name), \(magnification), \(point)")
                }
            }
            configure(pair, point: .zero, magnification: .twoTimes)
            let blackOutside = await waitForColor(.black, player: child, x: 0.2, y: 0.2)
            XCTAssertTrue(blackOutside, name)
            let inside = await waitForColor(colors[0], player: child, x: 0.8, y: 0.8)
            XCTAssertTrue(inside, name)
            pair.session.stop()
            XCTAssertNil(child.playbackTimeSnapshot(), "Closing the loupe must destroy its MPV context")
            pair.controller.teardown()
            pair.window.close()
        }
    }

    func testOverlayStopsReadbackDuringLivePlaybackAndRestoresMainFrameOnPause() async throws {
        let pair = try await makePair(url: fixture("landscape"))
        pair.session.stop()
        let state = InspectionLoupeState()
        state.isEnabled = true
        let capture = LoupeFrameCapture(), secondaryCapture = LoupeFrameCapture()
        let secondary = PlayerController(proResRAWDetector: { _, _ in false })
        defer { capture.stop(); secondaryCapture.stop(); secondary.teardown() }
        let overlay = InspectionLoupeOverlay(state: state, primary: pair.controller, secondary: secondary,
            primaryCapture: capture, secondaryCapture: secondaryCapture, isComparing: false,
            geometry: CompareDisplayGeometry(canvasSize: CGSize(width: 640, height: 360),
                primaryAspectRatio: 16.0 / 9, secondaryAspectRatio: 16.0 / 9), mode: .primary)
        let host = NSHostingView(rootView: AnyView(overlay))
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        pair.window.contentView?.addSubview(host)
        pair.controller.play()
        let live = await waitUntil {
            pair.controller.isPlaying && capture.captureRequestCount > 0 && capture.image == nil
                && self.liveSurface(in: host)?.session?.isReady == true
        }
        XCTAssertTrue(live)
        // Allow the readiness-triggered SwiftUI update to stop an already
        // submitted startup capture before sampling the steady-state count.
        try await Task.sleep(for: .milliseconds(250))
        let count = capture.captureRequestCount
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(capture.captureRequestCount, count, "The live loupe must not take background screenshots")
        pair.controller.pause()
        let paused = await waitUntil {
            !pair.controller.isPlaying && capture.captureRequestCount > count && capture.image != nil
        }
        XCTAssertTrue(paused, "Pausing with live video enabled must restore the main player's captured frame")
        XCTAssertFalse(LiveLoupeSession.supportsPlayback(pair.controller))
        if ProcessInfo.processInfo.environment["AAGEDAL_MPV_DECODER_RASTER_CANDIDATE"] == "1" {
            let verified = await waitUntil { capture.hasVerifiedSourceRaster(for: pair.controller) }
            XCTAssertTrue(verified, "The paused loupe must use the main player's current decoded raster")
            let pausedImage = try XCTUnwrap(capture.image)
            pair.controller.seekTo(0.75)
            let sought = await waitUntil {
                abs((pair.controller.mpvPlayer?.playbackTimeSnapshot() ?? .nan) - 0.75) < 0.05
                    && capture.image !== pausedImage
                    && capture.hasVerifiedSourceRaster(for: pair.controller)
            }
            XCTAssertTrue(sought, "A paused seek must replace the loupe with the main player's new frame")
        }
        pair.controller.play()
        let resumed = await waitUntil {
            pair.controller.isPlaying && capture.image == nil
                && self.liveSurface(in: host)?.session?.isReady == true
        }
        XCTAssertTrue(resumed)
        let resumedCount = capture.captureRequestCount
        state.usesLiveVideo = false
        let fallback = await waitUntil { capture.captureRequestCount > resumedCount && capture.image != nil }
        XCTAssertTrue(fallback)
        pair.controller.pause()
        host.rootView = AnyView(EmptyView())
        let stopped = await waitUntil { capture.image == nil }
        XCTAssertTrue(stopped)
    }

    func testPlaybackViewerKeepsTransportAndReleasesDecoder() async throws {
        struct Case: Decodable { let name: String, input: String, hardwareDecoder: String }
        struct Manifest: Decodable { let cases: [Case] }
        let manifestPath = ProcessInfo.processInfo.environment["LIVE_LOUPE_CASES"]
        let cases: [Case]
        if let manifestPath {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: manifestPath)))
            let names = ["uhd-h264-hardware", "pq-hevc-hardware", "hlg-hevc-hardware", "pq-hevc-software"]
            cases = manifest.cases.filter { names.contains($0.name) }
            XCTAssertEqual(cases.count, 4)
        } else { cases = [Case(name: "landscape", input: try fixture("landscape").path, hardwareDecoder: "videotoolbox")] }
        for testCase in cases {
            let previous = ProcessInfo.processInfo.environment["AAGEDAL_MPV_DECODER_RASTER_HWDEC"]
            setenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC", testCase.hardwareDecoder, 1)
            defer {
                if let previous { setenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC", previous, 1) }
                else { unsetenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC") }
            }
            let pair = try await makePair(url: URL(fileURLWithPath: testCase.input))
            let primary = try XCTUnwrap(pair.controller.mpvPlayer)
            let child = try XCTUnwrap(pair.session.player)
            pair.controller.play()
            let running = await waitUntil { pair.controller.isPlaying && pair.session.isReady && child.isPlaying }
            XCTAssertTrue(running, testCase.name)
            try await Task.sleep(for: .seconds(1))
            let began = ProcessInfo.processInfo.systemUptime
            let loopDuration = primary.duration
            let mainFrames = pair.mainLayer.presentedFrames, loupeFrames = pair.liveLayer.presentedFrames
            var maximumDrift: Double = 0
            for _ in 0..<30 {
                let drift = await Task.detached {
                    LiveLoupeClock.sample(readPrimary: { primary.playbackTimeSnapshot() ?? .nan },
                        readSecondary: { child.playbackTimeSnapshot() ?? .nan }, loopDuration: loopDuration)?.effectiveDrift
                }.value
                if let drift { maximumDrift = max(maximumDrift, drift) }
                try await Task.sleep(for: .milliseconds(100))
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            let primaryFPS = Double(pair.mainLayer.presentedFrames - mainFrames) / elapsed
            let loupeFPS = Double(pair.liveLayer.presentedFrames - loupeFrames) / elapsed
            let output = await Task.detached { (primary.videoOutputSnapshot(), child.videoOutputSnapshot()) }.value
            let mainOutput = try XCTUnwrap(output.0), loupeOutput = try XCTUnwrap(output.1)
            XCTAssertEqual(loupeOutput.hardwareDecoder, "videotoolbox")
            XCTAssertNotNil(mainOutput.targetTransfer)
            XCTAssertEqual(mainOutput.targetTransfer, loupeOutput.targetTransfer)
            XCTAssertEqual(mainOutput.targetPrimaries, loupeOutput.targetPrimaries)
            XCTAssertEqual(pair.liveLayer.wantsExtendedDynamicRangeContent,
                pair.mainLayer.wantsExtendedDynamicRangeContent)
            XCTAssertLessThanOrEqual(maximumDrift, 0.1, testCase.name)
            XCTAssertGreaterThanOrEqual(primaryFPS, manifestPath == nil ? 18 : 45, testCase.name)
            XCTAssertGreaterThanOrEqual(loupeFPS, manifestPath == nil ? 18 : 45, testCase.name)
            XCTAssertNil(pair.session.error)
            print("MPV_LIVE_LOUPE_CASE: \(testCase.name), mainFPS=\(primaryFPS), loupeFPS=\(loupeFPS), maximumClockDrift=\(maximumDrift), target=\(loupeOutput.targetPrimaries ?? "nil")/\(loupeOutput.targetTransfer ?? "nil"), hwdec=\(loupeOutput.hardwareDecoder ?? "nil")")
            primary.seek(to: 0.5)
            try await Task.sleep(for: .milliseconds(500))
            pair.controller.playForSynchronization(atRate: 2)
            let speedMatched = await waitUntil { abs(child.rate - 2) < 0.11 && pair.session.isReady }
            XCTAssertTrue(speedMatched)
            pair.controller.pause()
            let paused = await waitUntil { !pair.controller.isPlaying && !child.isPlaying }
            XCTAssertTrue(paused)
            let capture = LoupeFrameCapture()
            capture.start(controller: pair.controller)
            let captured = await waitUntil { capture.image != nil }
            XCTAssertTrue(captured)
            if ProcessInfo.processInfo.environment["AAGEDAL_MPV_DECODER_RASTER_CANDIDATE"] == "1" {
                let verified = await waitUntil { capture.hasVerifiedSourceRaster(for: pair.controller) }
                XCTAssertTrue(verified)
            }
            capture.stop()
            pair.session.stop()
            XCTAssertNil(pair.session.player)
            XCTAssertNil(child.playbackTimeSnapshot())
            XCTAssertNotNil(primary.playbackTimeSnapshot(), "Stopping the follower must preserve the main context")
            pair.controller.teardown(); pair.window.close()
        }
        print("MPV_LIVE_LOUPE_ACCEPTANCE: \(cases.count) cases")
    }

    /// Hosts the production comparison canvas and overlay together, using different
    /// UHD60 files. Presentation counters belong to the loupe surfaces only.
    func testComparisonCanvasKeepsPairedLiveLoupesAndRestoresPausedInspection() async throws {
        guard let path = ProcessInfo.processInfo.environment["LIVE_LOUPE_COMPARISON_CASES"] else {
            throw XCTSkip("Run validate-mpv-native-app.py --comparison to qualify the UHD60 comparison canvas")
        }
        try await qualifyComparisonManifest(path: path)
        print("MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen")
    }

    func testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LIVE_LOUPE_COMPARISON_CASES"],
              environment["LIVE_LOUPE_COMPARISON_SOAK_SECONDS"] != nil else {
            throw XCTSkip("Run validate-mpv-native-app.py --comparison --soak-seconds for sustained comparison")
        }
        guard let seconds = environment["LIVE_LOUPE_COMPARISON_SOAK_SECONDS"].flatMap(Int.init),
              (10...3600).contains(seconds),
              let cycles = environment["LIVE_LOUPE_COMPARISON_SOAK_CYCLES"].flatMap(Int.init),
              (3...100).contains(cycles) else {
            return XCTFail("Comparison soak requires 10–3600 seconds per mode and 3–100 cycles")
        }
        var footprints: [UInt64] = []
        for cycle in 1...cycles {
            try await qualifyComparisonManifest(path: path, secondsPerMode: seconds, cycle: cycle)
            // Both pair helpers have returned, releasing hosts, layers and players.
            try await Task.sleep(for: .seconds(1))
            let footprint = try physicalFootprint()
            footprints.append(footprint)
            XCTAssertLessThanOrEqual(footprint, footprints[0] + 256 * 1024 * 1024,
                "Comparison cycle-end growth exceeded 256 MiB above warmup")
            print("MPV_COMPARISON_LOUPE_SOAK_CYCLE: cycle=\(cycle), physicalFootprintBytes=\(footprint)")
        }
        print("MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: \(cycles) cycles, 2 pairs, 3 modes, \(seconds) seconds per mode, baselineBytes=\(footprints[0]), maximumCycleEndBytes=\(footprints.max()!), growthLimitBytes=268435456")
    }

    private func qualifyComparisonManifest(path: String, secondsPerMode: Int = 3, cycle: Int = 1) async throws {
        struct Case: Decodable { let name: String, input: String }
        struct Manifest: Decodable { let cases: [Case] }
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard Set(manifest.cases.map(\.name)).count == manifest.cases.count else {
            return XCTFail("Comparison requires distinct workload identities")
        }
        for names in [["uhd-h264-hardware", "pq-hevc-hardware"],
                      ["pq-hevc-hardware", "hlg-hevc-hardware"]] {
            let inputs = try names.map { name in
                try XCTUnwrap(manifest.cases.first { $0.name == name }).input
            }
            XCTAssertNotEqual(inputs[0], inputs[1])
            try await qualifyComparison(inputs: inputs, name: names.joined(separator: "/"),
                secondsPerMode: secondsPerMode, cycle: cycle)
        }
    }

    private struct ComparisonHost: View {
        @ObservedObject var primary: PlayerController
        @ObservedObject var comparison: CompareSessionController
        @ObservedObject var state: InspectionLoupeState
        let primaryCapture: LoupeFrameCapture, secondaryCapture: LoupeFrameCapture
        let item: MediaItem
        let waveform = AudioWaveformGenerator()

        var body: some View {
            ZStack {
                ComparePlayerView(primaryController: primary, compareSession: comparison,
                    primaryWaveformGenerator: waveform, primaryItem: item, showsAudioWaveform: false,
                    isEditingTimecode: .constant(false), isTimelineFocused: .constant(false),
                    isOverlayControlFocused: false, isTextInputActive: false,
                    timecodeActivationTrigger: .constant(nil))
                if state.isEnabled {
                    InspectionLoupeOverlay(state: state, primary: primary,
                        secondary: comparison.secondaryController, primaryCapture: primaryCapture,
                        secondaryCapture: secondaryCapture, isComparing: comparison.isActive,
                        geometry: CompareDisplayGeometry(canvasSize: CGSize(width: 960, height: 540),
                            primaryAspectRatio: primary.videoAspectRatio ?? 16.0 / 9,
                            secondaryAspectRatio: comparison.secondaryController.videoAspectRatio ?? 16.0 / 9),
                        mode: comparison.viewMode)
                }
            }
        }
    }

    private func qualifyComparison(inputs: [String], name: String, secondsPerMode: Int, cycle: Int) async throws {
        let primary = PlayerController(proResRAWDetector: { _, _ in false })
        let secondary = PlayerController(proResRAWDetector: { _, _ in false })
        let comparison = CompareSessionController(secondaryController: secondary)
        let state = InspectionLoupeState()
        let a = LoupeFrameCapture(), b = LoupeFrameCapture()
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 960, height: 540),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            a.stop(); b.stop(); comparison.stop(); primary.teardown(); secondary.teardown()
            window.close()
        }
        primary.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: URL(fileURLWithPath: inputs[0])))
        let constructed = await waitUntil { primary.mpvPlayer != nil }
        XCTAssertTrue(constructed)
        let host = NSHostingView(rootView: ComparisonHost(primary: primary, comparison: comparison,
            state: state, primaryCapture: a, secondaryCapture: b, item: try XCTUnwrap(primary.mediaItem)))
        window.contentView = host
        window.orderFront(nil)
        let primaryReady = await waitUntil { primary.isReady }
        XCTAssertTrue(primaryReady)
        comparison.loadSecondary(URL(fileURLWithPath: inputs[1]), alignedWith: primary)
        let ready = await waitUntil { comparison.isSecondaryReady }
        XCTAssertTrue(ready, comparison.loadError ?? name)
        state.isEnabled = true
        primary.updateLoopPlayback(true)
        secondary.updateLoopPlayback(true)
        comparison.play(primary: primary)
        let live = await waitUntil {
            let surfaces = self.liveSurfaces(in: host)
            return surfaces.count == 2 && surfaces.allSatisfy { $0.session?.isReady == true }
        }
        XCTAssertTrue(live, name)
        for mode in [CompareViewMode.sideBySide, .verticalWipe, .overlay] {
            comparison.viewMode = mode
            // Geometry changes can replace follower contexts to resize their output.
            try await Task.sleep(for: .seconds(1))
            let surfaces = liveSurfaces(in: host)
            guard surfaces.count == 2 else {
                return XCTFail("Comparison must mount both live lenses: \(name), \(mode)")
            }
            let followers = try surfaces.map { try XCTUnwrap($0.session?.player) }
            let sources = [try XCTUnwrap(primary.mpvPlayer), try XCTUnwrap(secondary.mpvPlayer)]
            for index in sources.indices {
                XCTAssertEqual(sources[index].videoSourceSize, CGSize(width: 3840, height: 2160))
                XCTAssertEqual(followers[index].videoSourceSize, sources[index].videoSourceSize)
                let output = try XCTUnwrap(followers[index].videoOutputSnapshot())
                let sourceOutput = try XCTUnwrap(sources[index].videoOutputSnapshot())
                XCTAssertEqual(output.hardwareDecoder, "videotoolbox")
                XCTAssertEqual(sourceOutput.hardwareDecoder, "videotoolbox")
                XCTAssertTrue(surfaces[index].session?.isReady(for: [primary, secondary][index]) == true)
                XCTAssertNotNil(sourceOutput.targetTransfer)
                XCTAssertNotNil(sourceOutput.targetPrimaries)
                XCTAssertEqual(output.targetTransfer, sourceOutput.targetTransfer)
                XCTAssertEqual(output.targetPrimaries, sourceOutput.targetPrimaries)
                XCTAssertTrue(followers[index].isMuted)
                XCTAssertFalse(followers[index].canInspectDecoderRaster)
            }
            let modeBegan = ProcessInfo.processInfo.systemUptime
            var windows = 0
            repeat {
                windows += 1
                let counts = surfaces.map { $0.metalLayer.presentedFrames }
                let captures = [a.captureRequestCount, b.captureRequestCount]
                let began = ProcessInfo.processInfo.systemUptime
                var valid = [0, 0], maxDrift = [0.0, 0.0]
                for _ in 0..<30 {
                    // MPV snapshots can wait for the decoder. Keep measurement
                    // off the main actor, as the live follower's own sampler does.
                    let loopDurations = sources.map { $0.duration }
                    let drifts = await Task.detached {
                        sources.indices.map { index in
                            LiveLoupeClock.sample(
                                readPrimary: { sources[index].playbackTimeSnapshot() ?? .nan },
                                readSecondary: { followers[index].playbackTimeSnapshot() ?? .nan },
                                loopDuration: loopDurations[index])?.effectiveDrift
                        }
                    }.value
                    for index in sources.indices {
                        if let drift = drifts[index] {
                            valid[index] += 1
                            maxDrift[index] = max(maxDrift[index], drift)
                        }
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - began
                for index in surfaces.indices {
                    let fps = Double(surfaces[index].metalLayer.presentedFrames - counts[index]) / elapsed
                    XCTAssertGreaterThanOrEqual(fps, 45, "\(name), \(mode), source=\(index)")
                    XCTAssertGreaterThanOrEqual(valid[index], 29)
                    XCTAssertLessThanOrEqual(maxDrift[index], 0.1)
                    print("MPV_COMPARISON_LOUPE_WINDOW: cycle=\(cycle), window=\(windows), pair=\(name), mode=\(mode), source=\(index), fps=\(fps), maxDrift=\(maxDrift[index]), validSamples=\(valid[index])/30")
                }
                XCTAssertEqual([a.captureRequestCount, b.captureRequestCount], captures,
                    "Paired live playback must suppress both screenshot workers")
                let footprint = try physicalFootprint()
                print("MPV_COMPARISON_LOUPE_MEMORY: cycle=\(cycle), pair=\(name), mode=\(mode), elapsed=\(ProcessInfo.processInfo.systemUptime - modeBegan), physicalFootprintBytes=\(footprint)")
            } while ProcessInfo.processInfo.systemUptime - modeBegan < Double(secondsPerMode)

        }
        comparison.pause(primary: primary)
        let paused = await waitUntil {
            !primary.isPlaying && !secondary.isPlaying && a.hasVerifiedSourceRaster(for: primary)
                && b.hasVerifiedSourceRaster(for: secondary)
        }
        XCTAssertTrue(paused, name)
        let oldA = a.image, oldB = b.image
        comparison.seek(primary: primary, to: 1)
        let sought = await waitUntil {
            abs(primary.playbackTimeSnapshot() - 1) < 0.05
                && abs(secondary.playbackTimeSnapshot() - 1) < 0.05
                && a.image !== oldA && b.image !== oldB
                && a.hasVerifiedSourceRaster(for: primary) && b.hasVerifiedSourceRaster(for: secondary)
        }
        XCTAssertTrue(sought, "Both paused lenses must replace their native image after paired seek")
        comparison.play(primary: primary)
        let resumed = await waitUntil {
            let surfaces = self.liveSurfaces(in: host)
            return a.image == nil && b.image == nil && surfaces.count == 2
                && surfaces.allSatisfy { $0.session?.isReady == true }
        }
        XCTAssertTrue(resumed)
        let obsolete = liveSurfaces(in: host).compactMap { $0.session?.player }
        XCTAssertEqual(obsolete.count, 2)
        state.isEnabled = false
        let closed = await waitUntil {
            obsolete.allSatisfy { $0.playbackTimeSnapshot() == nil }
        }
        XCTAssertTrue(closed, "Closing the paired overlay must destroy both followers")
        XCTAssertNotNil(primary.mpvPlayer?.playbackTimeSnapshot())
        XCTAssertNotNil(secondary.mpvPlayer?.playbackTimeSnapshot())
        state.isEnabled = true
        let reopened = await waitUntil {
            let surfaces = self.liveSurfaces(in: host)
            return surfaces.count == 2 && surfaces.allSatisfy { $0.session?.isReady == true }
        }
        XCTAssertTrue(reopened)
    }

    private func liveSurfaces(in view: NSView) -> [LiveLoupeVideoSurface.SurfaceView] {
        if let surface = view as? LiveLoupeVideoSurface.SurfaceView { return [surface] }
        return view.subviews.flatMap { liveSurfaces(in: $0) }
    }

    /// Opt-in qualification: two independent source/loupe pairs exercise the
    /// four-decoder comparison load without claiming comparison UI acceptance.
    func testSustainedConcurrentViewersKeepCadenceAndBoundMemory() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let manifestPath = environment["LIVE_LOUPE_SOAK_CASES"] else {
            throw XCTSkip("Run validate-mpv-native-app.py --live-viewer --soak-seconds to qualify sustained playback")
        }
        guard let seconds = environment["LIVE_LOUPE_SOAK_SECONDS"].flatMap(Int.init),
              (10...3600).contains(seconds),
              let cycles = environment["LIVE_LOUPE_SOAK_CYCLES"].flatMap(Int.init),
              (3...100).contains(cycles) else {
            return XCTFail("Soak requires 10–3600 seconds per workload and 3–100 cycles")
        }
        struct Case: Decodable { let name: String, input: String, hardwareDecoder: String }
        struct Manifest: Decodable { let cases: [Case] }
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: manifestPath)))
        let names = ["uhd-h264-hardware", "pq-hevc-hardware", "hlg-hevc-hardware", "pq-hevc-software"]
        let cases = names.compactMap { name in manifest.cases.first { $0.name == name } }
        guard cases.count == names.count,
              Set(manifest.cases.map(\.name)).count == manifest.cases.count else {
            return XCTFail("Soak requires all four distinct UHD60 workload identities")
        }
        let previous = environment["AAGEDAL_MPV_DECODER_RASTER_HWDEC"]
        defer {
            if let previous { setenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC", previous, 1) }
            else { unsetenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC") }
        }
        var footprints: [UInt64] = []
        for cycle in 1...cycles {
            for testCase in cases {
                setenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC", testCase.hardwareDecoder, 1)
                try await qualifyConcurrentViewers(url: URL(fileURLWithPath: testCase.input),
                    name: testCase.name, primaryHardware: testCase.hardwareDecoder,
                    seconds: seconds, cycle: cycle)
            }
            // Helpers have returned and released their player/layer references.
            // Allow asynchronous MPV/Metal teardown to retire before measuring.
            try await Task.sleep(for: .seconds(1))
            let footprint = try physicalFootprint()
            footprints.append(footprint)
            print("MPV_LIVE_LOUPE_SOAK_CYCLE: \(cycle), physicalFootprintBytes=\(footprint)")
            let baseline = try XCTUnwrap(footprints.first)
            XCTAssertLessThanOrEqual(footprint, baseline + 256 * 1024 * 1024,
                "Cycle-end growth above the first complete warmup cycle exceeded 256 MiB")
        }
        print("MPV_LIVE_LOUPE_SOAK_ACCEPTANCE: \(cycles) cycles, \(cases.count) cases, 2 pairs, \(seconds) seconds per case, baselineBytes=\(footprints[0]), maximumCycleEndBytes=\(footprints.max()!), growthLimitBytes=268435456")
    }

    private func qualifyConcurrentViewers(url: URL, name: String, primaryHardware: String,
                                           seconds: Int, cycle: Int) async throws {
        var pairs: [Pair] = []
        defer {
            for pair in pairs {
                pair.session.stop()
                pair.controller.teardown()
                pair.window.close()
                sessions.removeAll { $0 === pair.session }
                controllers.removeAll { $0 === pair.controller }
                windows.removeAll { $0 === pair.window }
            }
        }
        for index in 0..<2 {
            let pair = try await makePair(url: url)
            pairs.append(pair)
            if let screen = NSScreen.main {
                pair.window.setFrameOrigin(CGPoint(x: screen.visibleFrame.minX + 20,
                    y: screen.visibleFrame.minY + 20 + CGFloat(index) * 420))
            }
        }
        let primaries = try pairs.map { try XCTUnwrap($0.controller.mpvPlayer) }
        let children = try pairs.map { try XCTUnwrap($0.session.player) }
        for pair in pairs { pair.controller.play() }
        let ready = await waitUntil {
            pairs.allSatisfy { $0.controller.isPlaying && $0.session.isReady }
                && children.allSatisfy { $0.isPlaying }
        }
        XCTAssertTrue(ready, name)
        try await Task.sleep(for: .seconds(1))
        for index in pairs.indices {
            let primary = primaries[index], child = children[index]
            let output = await Task.detached { (primary.videoOutputSnapshot(), child.videoOutputSnapshot()) }.value
            let main = try XCTUnwrap(output.0), loupe = try XCTUnwrap(output.1)
            XCTAssertEqual(primary.videoSourceSize, CGSize(width: 3840, height: 2160), name)
            XCTAssertEqual(child.videoSourceSize, CGSize(width: 3840, height: 2160), name)
            XCTAssertEqual(main.hardwareDecoder, primaryHardware)
            XCTAssertEqual(loupe.hardwareDecoder, "videotoolbox")
            XCTAssertNotNil(main.targetTransfer)
            XCTAssertNotNil(main.targetPrimaries)
            XCTAssertEqual(main.targetTransfer, loupe.targetTransfer)
            XCTAssertEqual(main.targetPrimaries, loupe.targetPrimaries)
            XCTAssertEqual(pairs[index].mainLayer.wantsExtendedDynamicRangeContent,
                pairs[index].liveLayer.wantsExtendedDynamicRangeContent)
            XCTAssertFalse(child.canInspectDecoderRaster)
            XCTAssertTrue(child.isMuted)
        }
        let loopDurations = primaries.map { $0.duration }
        let began = ProcessInfo.processInfo.systemUptime
        var windowStart = began
        var mainFrames = pairs.map { $0.mainLayer.presentedFrames }
        var loupeFrames = pairs.map { $0.liveLayer.presentedFrames }
        var maximumDrift = [Double](repeating: 0, count: pairs.count)
        var validSamples = [Int](repeating: 0, count: pairs.count)
        var sampleCount = 0
        var maximumFootprint: UInt64 = 0
        var windowsMeasured = 0
        while ProcessInfo.processInfo.systemUptime - began < Double(seconds) {
            let drifts = await Task.detached {
                primaries.indices.map { index in
                    LiveLoupeClock.sample(readPrimary: { primaries[index].playbackTimeSnapshot() ?? .nan },
                        readSecondary: { children[index].playbackTimeSnapshot() ?? .nan },
                        loopDuration: loopDurations[index])?.effectiveDrift
                }
            }.value
            sampleCount += 1
            for index in pairs.indices {
                if let drift = drifts[index] {
                    validSamples[index] += 1
                    maximumDrift[index] = max(maximumDrift[index], drift)
                }
                XCTAssertNil(pairs[index].session.error, name)
            }
            let now = ProcessInfo.processInfo.systemUptime
            // Bound each window, so an aggregate average cannot conceal stalls.
            if now - windowStart >= 3 {
                for index in pairs.indices {
                    let main = pairs[index].mainLayer.presentedFrames
                    let loupe = pairs[index].liveLayer.presentedFrames
                    let mainFPS = Double(main - mainFrames[index]) / (now - windowStart)
                    let loupeFPS = Double(loupe - loupeFrames[index]) / (now - windowStart)
                    XCTAssertGreaterThanOrEqual(mainFPS, 45, name)
                    XCTAssertGreaterThanOrEqual(loupeFPS, 45, name)
                    print("MPV_LIVE_LOUPE_SOAK_WINDOW: cycle=\(cycle), case=\(name), pair=\(index), elapsed=\(now - began), mainFPS=\(mainFPS), loupeFPS=\(loupeFPS)")
                    mainFrames[index] = main; loupeFrames[index] = loupe
                }
                maximumFootprint = max(maximumFootprint, try physicalFootprint())
                windowsMeasured += 1
                windowStart = now
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(windowsMeasured, 3)
        for index in pairs.indices {
            XCTAssertGreaterThanOrEqual(Double(validSamples[index]) / Double(sampleCount), 0.95,
                "Missing clock samples must not silently qualify: \(name)")
            XCTAssertLessThanOrEqual(maximumDrift[index], 0.1, name)
            pairs[index].session.stop()
            XCTAssertNil(children[index].playbackTimeSnapshot())
            XCTAssertNotNil(primaries[index].playbackTimeSnapshot())
        }
        print("MPV_LIVE_LOUPE_SOAK_CASE: cycle=\(cycle), case=\(name), maximumDrift=\(maximumDrift), validSamples=\(validSamples), samples=\(sampleCount), maximumSampledFootprintBytes=\(maximumFootprint)")
    }

    private func physicalFootprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw NSError(domain: NSMachErrorDomain, code: Int(status)) }
        return info.phys_footprint
    }

    private struct Pair {
        let controller: PlayerController, session: LiveLoupeSession
        let mainLayer: LiveLoupeMetalLayer, liveLayer: LiveLoupeMetalLayer
        let window: NSWindow
    }

    private func makePair(url: URL) async throws -> Pair {
        let controller = PlayerController(proResRAWDetector: { _, _ in false })
        let session = LiveLoupeSession()
        controllers.append(controller); sessions.append(session)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 840, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 840, height: 400))
        window.contentView = root
        let mainView = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        let mainLayer = LiveLoupeMetalLayer()
        mainLayer.frame = mainView.bounds
        mainLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        mainLayer.drawableSize = CGSize(width: 640 * mainLayer.contentsScale, height: 360 * mainLayer.contentsScale)
        mainView.layer = mainLayer; mainView.wantsLayer = true
        root.addSubview(mainView)
        let liveView = LiveLoupeVideoSurface.SurfaceView(frame: CGRect(x: 660, y: 0, width: 160, height: 120))
        liveView.session = session
        root.addSubview(liveView)
        window.orderFront(nil)
        controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: url))
        let constructed = await waitUntil { controller.mpvPlayer != nil }
        XCTAssertTrue(constructed)
        try XCTUnwrap(controller.mpvPlayer).attachDrawable(mainLayer)
        let ready = await waitUntil { controller.isReady }
        XCTAssertTrue(ready)
        controller.pause()
        controller.updateLoopPlayback(true)
        let pair = Pair(controller: controller, session: session, mainLayer: mainLayer,
            liveLayer: liveView.metalLayer, window: window)
        configure(pair, point: CGPoint(x: 0.25, y: 0.25), magnification: .twoTimes)
        session.attachSurface(liveView.metalLayer)
        session.start(controller: controller)
        let followerReady = await waitUntil { session.isReady }
        XCTAssertTrue(followerReady, session.error ?? "Live viewer did not become ready")
        return pair
    }

    private func configure(_ pair: Pair, point: CGPoint, magnification: LoupeMagnification) {
        let ratio = pair.controller.videoAspectRatio ?? 16.0 / 9
        if let viewport = LoupeVideoViewport(pictureSize: CGSize(width: 320, height: 320 / ratio),
            lensSize: CGSize(width: 160, height: 120), normalizedPoint: point, magnification: magnification) {
            pair.session.configure(viewport: viewport, nearest: true)
        }
    }

    private func waitForColor(_ expected: NSColor, player: MPVPlayer, x: Double, y: Double) async -> Bool {
        for _ in 0..<30 {
            let raw = await Task.detached { player.screenshotRaw(scaledToWindow: true) }.value
            if let raw, let image = LoupeFrameCapture.image(from: raw),
               let color = NSBitmapImageRep(cgImage: image).colorAt(x: Int(Double(image.width) * x),
                   y: Int(Double(image.height) * y))?.usingColorSpace(.sRGB),
               let expected = expected.usingColorSpace(.sRGB),
               abs(color.redComponent - expected.redComponent) < 0.25,
               abs(color.greenComponent - expected.greenComponent) < 0.25,
               abs(color.blueComponent - expected.blueComponent) < 0.25 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return predicate()
    }

    private func fixture(_ name: String) throws -> URL {
        let root = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Test Fixtures/Generated")
        let url = root.appending(path: "loupe/\(name).mp4")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Generate the loupe fixtures first") }
        return url
    }

    private func liveSurface(in view: NSView) -> LiveLoupeVideoSurface.SurfaceView? {
        if let surface = view as? LiveLoupeVideoSurface.SurfaceView { return surface }
        for child in view.subviews {
            if let surface = liveSurface(in: child) { return surface }
        }
        return nil
    }
}
