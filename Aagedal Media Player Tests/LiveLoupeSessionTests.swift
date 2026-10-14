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
