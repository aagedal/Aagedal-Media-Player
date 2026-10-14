// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LoupeTrackDecoderTests: XCTestCase {
    private var retainedSurfaces: [NSView] = []

    override func tearDown() async throws {
        retainedSurfaces.removeAll()
        try await super.tearDown()
    }

    func testEnabledItemTrackSuppliesGeometryAndNativeRasterProof() async throws {
        let asset = AVURLAsset(url: try fixture("multi-track"))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 2)
        let first = try XCTUnwrap(tracks.first)
        let second = try XCTUnwrap(tracks.last)
        let controller = try await makeController(url: try fixture("landscape"))
        let capture = LoupeFrameCapture()
        defer { capture.stop(); controller.teardown() }
        let player = try XCTUnwrap(controller.player)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        let ready = await waitUntil { item.status == .readyToPlay && item.tracks.count == 2 }
        XCTAssertTrue(ready, "The two-track file must load in the real decoder")
        for track in item.tracks { track.isEnabled = track.assetTrack?.trackID == second.trackID }
        XCTAssertEqual(LoupeFrameCapture.sourceVideoTrack(in: item)?.trackID, second.trackID)
        await player.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        capture.start(controller: controller)
        let captured = await waitUntil {
            capture.image?.width == 180 && capture.image?.height == 240 && capture.hasVerifiedAVRaster(for: controller)
        }
        XCTAssertTrue(captured, "The enabled second track, rather than the asset's first track, defines the oriented coded raster")
        let image = try XCTUnwrap(capture.image)
        try assertQuadrants([.green, .yellow, .red, .blue], image: image)

        // Item identity and preparation stay constant. Track selection alone
        // must invalidate the old geometry and its native-pixel certification.
        for track in item.tracks { track.isEnabled = track.assetTrack?.trackID == first.trackID }
        XCTAssertFalse(capture.hasVerifiedAVRaster(for: controller))
        await player.seek(to: CMTime(seconds: 0.75, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let changed = await waitUntil {
            capture.image?.width == 320 && capture.image?.height == 180 && capture.hasVerifiedAVRaster(for: controller)
        }
        XCTAssertTrue(changed, "The loupe must rebind its output when the enabled track changes")
        try assertQuadrants([.red, .green, .blue, .yellow], image: XCTUnwrap(capture.image))

        for track in item.tracks { track.isEnabled = true }
        XCTAssertNil(LoupeFrameCapture.sourceVideoTrack(in: item), "Two enabled tracks do not establish one decoded raster")
        XCTAssertFalse(capture.hasVerifiedAVRaster(for: controller))
    }

    func testVideoCompositionWithMatchingDimensionsStaysPreviewOnly() async throws {
        let controller = try await makeController(url: try fixture("landscape"))
        let capture = LoupeFrameCapture()
        defer { capture.stop(); controller.teardown() }
        let player = try XCTUnwrap(controller.player)
        let item = try XCTUnwrap(player.currentItem)
        capture.start(controller: controller)
        let verified = await waitUntil { capture.hasVerifiedAVRaster(for: controller) }
        XCTAssertTrue(verified)
        let originalImage = try XCTUnwrap(capture.image)
        let track = try XCTUnwrap(LoupeFrameCapture.sourceVideoTrack(in: item))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await item.asset.load(.duration))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // This shear/scale keeps the same bounds while resampling the pixels.
        layer.setTransform(CGAffineTransform(a: 0.5, b: 0, c: 8.0 / 9.0, d: 1, tx: 0, ty: 0), at: .zero)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: 320, height: 180)
        composition.frameDuration = CMTime(value: 1, timescale: 24)
        composition.instructions = [instruction]
        item.videoComposition = composition
        XCTAssertNil(LoupeFrameCapture.sourceVideoTrack(in: item))
        XCTAssertFalse(capture.hasVerifiedAVRaster(for: controller), "Composition changes must invalidate proof immediately")
        capture.start(controller: controller)
        XCTAssertNil(capture.image, "Refreshing composition identity must clear the old display preview")
        await player.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let preview = await waitUntil {
            guard let image = capture.image else { return false }
            return image !== originalImage && image.width == 320 && image.height == 180
        }
        XCTAssertTrue(preview, "Composited output remains useful as a display preview")
        XCTAssertFalse(capture.hasVerifiedAVRaster(for: controller), "Matching composition dimensions must never certify source pixels")
        XCTAssertEqual(player.rate, 0, "Loupe capture must preserve paused transport")
    }

    func testCompositionTrackCannotCertifySourcePixels() async throws {
        let asset = AVURLAsset(url: try fixture("landscape"))
        let composition = AVMutableComposition()
        let sources = try await asset.loadTracks(withMediaType: .video)
        let source = try XCTUnwrap(sources.first)
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: try await asset.load(.duration)), of: source, at: .zero)
        track.preferredTransform = try await source.load(.preferredTransform)
        let controller = try await makeController(url: try fixture("landscape"))
        let capture = LoupeFrameCapture()
        defer { capture.stop(); controller.teardown() }
        let player = try XCTUnwrap(controller.player)
        let item = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: item)
        let ready = await waitUntil { item.status == .readyToPlay && !item.tracks.isEmpty }
        XCTAssertTrue(ready)
        capture.start(controller: controller)
        let preview = await waitUntil { capture.image?.width == 320 && capture.image?.height == 180 }
        XCTAssertTrue(preview, "A composition still provides a display preview")
        XCTAssertNil(item.videoComposition, "Composition segments need not use an explicit video composition")
        XCTAssertFalse(capture.hasVerifiedAVRaster(for: controller), "Composition track format descriptions cannot prove the current segment's pixel provenance")
    }

    func testBundledMPVFallbackPreviewNeverCertifiesMatchingDimensions() async throws {
        let controller = PlayerController(proResRAWDetector: { _, _ in false })
        let capture = LoupeFrameCapture()
        defer { capture.stop(); controller.teardown() }
        controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: try fixture("landscape")))
        let constructed = await waitUntil { controller.useMPV && controller.mpvPlayer != nil }
        XCTAssertTrue(constructed)
        let mpv = try XCTUnwrap(controller.mpvPlayer)
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let layer = MPVMetalLayer()
        layer.frame = view.bounds
        layer.drawableSize = view.bounds.size
        view.layer = layer
        view.wantsLayer = true
        retainedSurfaces.append(view)
        mpv.attachDrawable(layer)
        let ready = await waitUntil { controller.isReady }
        XCTAssertTrue(ready)
        controller.pause()
        capture.start(controller: controller)
        let preview = await waitUntil { capture.image?.width == 320 && capture.image?.height == 180 }
        XCTAssertTrue(preview, "The bundled backend must retain its existing full-resolution preview")
        try assertQuadrants([.red, .green, .blue, .yellow], image: XCTUnwrap(capture.image))
        XCTAssertNil(mpv.decoderRaster(), "The shipping backend does not expose the candidate provider")
        XCTAssertFalse(mpv.isDecoderRasterCurrent(pts: 0, trackID: 1),
                       "A missing validity property must reject proof immediately")
        XCTAssertFalse(capture.hasVerifiedSourceRaster(for: controller),
                       "Matching coded dimensions must not promote a display screenshot to source-pixel proof")
        XCTAssertFalse(controller.isPlaying, "Capture must preserve paused transport")
        capture.stop()
        XCTAssertNil(capture.image)
        XCTAssertFalse(capture.hasVerifiedSourceRaster(for: controller))
    }

    func testMPVNativeRasterOptInUsesCurrentDecoderFrameAndRevokesOnResume() async throws {
        let environment = ProcessInfo.processInfo.environment
        let requiresProvider = environment["AAGEDAL_MPV_DECODER_RASTER_CANDIDATE"] == "1"
        if let cases = environment["MPV_DECODER_RASTER_CASES"] {
            XCTAssertTrue(requiresProvider, "Extended validation must explicitly enable the candidate")
            try await validateExtendedNativeCases(URL(fileURLWithPath: cases))
            return
        }
        let url: URL
        if requiresProvider {
            url = URL(fileURLWithPath: try XCTUnwrap(environment["MPV_DECODER_RASTER_FIXTURE"],
                "Candidate acceptance requires the independently numbered RGB-grid fixture"))
        } else {
            url = try fixture("landscape")
        }
        let controller = PlayerController(proResRAWDetector: { _, _ in false })
        let capture = LoupeFrameCapture()
        defer { capture.stop(); controller.teardown() }
        controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: url))
        let constructed = await waitUntil { controller.useMPV && controller.mpvPlayer != nil }
        XCTAssertTrue(constructed)
        let mpv = try XCTUnwrap(controller.mpvPlayer)
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let layer = MPVMetalLayer()
        layer.frame = view.bounds
        layer.drawableSize = view.bounds.size
        view.layer = layer
        view.wantsLayer = true
        retainedSurfaces.append(view)
        mpv.attachDrawable(layer)
        let ready = await waitUntil { controller.isReady }
        XCTAssertTrue(ready)
        controller.pause()
        XCTAssertEqual(mpv.canInspectDecoderRaster, requiresProvider,
                       "Candidate acceptance must fail if the rebuilt provider is missing")
        capture.start(controller: controller)
        if !requiresProvider {
            let preview = await waitUntil { capture.image != nil }
            XCTAssertTrue(preview)
            XCTAssertNil(mpv.decoderRaster())
            XCTAssertFalse(capture.hasVerifiedSourceRaster(for: controller))
            return
        }
        let verified = await waitUntil { capture.hasVerifiedSourceRaster(for: controller) }
        XCTAssertTrue(verified, "The actual app capture must certify the paused decoder frame")
        try assertNumberedGrid(try XCTUnwrap(mpv.decoderRaster()), expectedFrame: 0)
        mpv.seek(to: 1)
        let sought = await waitUntil {
            capture.hasVerifiedSourceRaster(for: controller) && mpv.decoderRaster()?.pixels.playbackTime == 1
        }
        XCTAssertTrue(sought)
        try assertNumberedGrid(try XCTUnwrap(mpv.decoderRaster()), expectedFrame: 5)
        controller.play()
        let playing = await waitUntil { controller.isPlaying }
        XCTAssertTrue(playing)
        XCTAssertFalse(capture.hasVerifiedSourceRaster(for: controller))
        XCTAssertNil(mpv.decoderRaster())
        print("MPV_NATIVE_RASTER_APP_ACCEPTANCE: 512 numbered pixels verified; proof revoked on resume")
    }

    private struct NativeCaseManifest: Decodable { let cases: [NativeCase] }
    private struct NativeCase: Decodable {
        let name: String, input: String
        let references: [String]?
        let width: Int, height: Int, depth: Int, rotation: Int
        let mirrored: Bool, transfer: String, primaries: String, hardwareDecoder: String
        let bytesPerPixel: Int, tolerance: Int, seekPTS: Double, reject: Bool
    }

    private func validateExtendedNativeCases(_ manifestURL: URL) async throws {
        let manifest = try JSONDecoder().decode(NativeCaseManifest.self, from: Data(contentsOf: manifestURL))
        let cases = manifest.cases.filter { !$0.reject }
        XCTAssertGreaterThan(cases.count, 10)
        for testCase in cases {
            let previousHWDec = ProcessInfo.processInfo.environment["AAGEDAL_MPV_DECODER_RASTER_HWDEC"]
            setenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC", testCase.hardwareDecoder, 1)
            defer {
                if let previousHWDec { setenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC", previousHWDec, 1) }
                else { unsetenv("AAGEDAL_MPV_DECODER_RASTER_HWDEC") }
            }
            let controller = PlayerController(proResRAWDetector: { _, _ in false })
            let capture = LoupeFrameCapture()
            defer { capture.stop(); controller.teardown() }
            controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: URL(fileURLWithPath: testCase.input)))
            let constructed = await waitUntil { controller.useMPV && controller.mpvPlayer != nil }
            XCTAssertTrue(constructed, testCase.name)
            let mpv = try XCTUnwrap(controller.mpvPlayer)
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
            let layer = MPVMetalLayer()
            layer.frame = view.bounds
            layer.drawableSize = view.bounds.size
            view.layer = layer
            view.wantsLayer = true
            retainedSurfaces.append(view)
            mpv.attachDrawable(layer)
            let ready = await waitUntil { controller.isReady }
            XCTAssertTrue(ready, testCase.name)
            controller.pause()
            XCTAssertTrue(mpv.canInspectDecoderRaster, testCase.name)
            capture.start(controller: controller)
            let verified = await waitUntil { capture.hasVerifiedSourceRaster(for: controller) }
            XCTAssertTrue(verified, testCase.name)
            let firstResult = await Task.detached { mpv.decoderRaster() }.value
            let first = try XCTUnwrap(firstResult)
            let references = try XCTUnwrap(testCase.references)
            try assertExtendedRaster(first, image: XCTUnwrap(capture.image), testCase: testCase,
                                     reference: references[0], expectedPTS: 0)
            let firstImage = try XCTUnwrap(capture.image)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(capture.image === firstImage, "An unchanged verified frame must reuse its large cached image")
            mpv.seek(to: testCase.seekPTS)
            let sought = await waitUntil {
                capture.hasVerifiedSourceRaster(for: controller) &&
                    mpv.isDecoderRasterCurrent(pts: testCase.seekPTS, trackID: first.trackID)
            }
            XCTAssertTrue(sought, testCase.name)
            let secondResult = await Task.detached { mpv.decoderRaster() }.value
            let second = try XCTUnwrap(secondResult)
            try assertExtendedRaster(second, image: XCTUnwrap(capture.image), testCase: testCase,
                                     reference: references[1], expectedPTS: testCase.seekPTS)
            controller.play()
            let playing = await waitUntil { controller.isPlaying }
            XCTAssertTrue(playing, testCase.name)
            XCTAssertFalse(capture.hasVerifiedSourceRaster(for: controller), testCase.name)
            print("MPV_EXTENDED_NATIVE_CASE_ACCEPTANCE: \(testCase.name), hardwareTransfer=\(second.hardwareTransferred), bits=\(second.sourceBitDepth)")
        }
        print("MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: \(cases.count) cases verified with seek, cached-image reuse, and resume revocation")
    }

    private func assertExtendedRaster(_ raster: MPVDecoderRaster, image: CGImage, testCase: NativeCase,
                                      reference: String, expectedPTS: Double) throws {
        XCTAssertEqual(raster.pixels.width, testCase.width, testCase.name)
        XCTAssertEqual(raster.pixels.height, testCase.height, testCase.name)
        XCTAssertEqual(raster.sourceBitDepth, testCase.depth, testCase.name)
        XCTAssertEqual(raster.rotation, testCase.rotation, testCase.name)
        XCTAssertEqual(raster.mirrored, testCase.mirrored, testCase.name)
        XCTAssertEqual(raster.hardwareTransferred, testCase.hardwareDecoder != "no", testCase.name)
        XCTAssertEqual(raster.colorEncoding, MPVDecoderRaster.ColorEncoding(primaries: testCase.primaries, transfer: testCase.transfer))
        XCTAssertEqual(try XCTUnwrap(raster.pixels.playbackTime), expectedPTS, accuracy: 0.000_001)
        XCTAssertEqual(image.width, testCase.width)
        XCTAssertEqual(image.height, testCase.height)
        XCTAssertEqual(image.bitsPerComponent, testCase.bytesPerPixel == 8 ? 16 : 8)
        if testCase.transfer == "pq" { XCTAssertEqual(image.colorSpace?.name, CGColorSpace.itur_2100_PQ) }
        if testCase.transfer == "hlg" { XCTAssertEqual(image.colorSpace?.name, CGColorSpace.itur_2100_HLG) }
        let expected = try Data(contentsOf: URL(fileURLWithPath: reference))
        let captured = try XCTUnwrap(image.dataProvider?.data) as Data
        let points = [(0,0), (testCase.width-1,0), (testCase.width/2,testCase.height/2),
                      (0,testCase.height-1), (testCase.width-1,testCase.height-1),
                      (testCase.width/4,testCase.height/4), (testCase.width*3/4,testCase.height*3/4)]
        let componentSize = testCase.bytesPerPixel == 8 ? 2 : 1
        for data in [raster.pixels.data, captured] {
            for (x,y) in points {
                for component in 0..<4 {
                    let a = y * raster.pixels.stride + x * testCase.bytesPerPixel + component * componentSize
                    let e = (y * testCase.width + x) * testCase.bytesPerPixel + component * componentSize
                    guard a + componentSize <= data.count, e + componentSize <= expected.count else {
                        return XCTFail("Truncated native/reference raster: \(testCase.name)")
                    }
                    let av = Int(data[a]) | (componentSize == 2 ? Int(data[a+1]) << 8 : 0)
                    let ev = Int(expected[e]) | (componentSize == 2 ? Int(expected[e+1]) << 8 : 0)
                    XCTAssertLessThanOrEqual(abs(av - ev), testCase.tolerance, "\(testCase.name), \(x),\(y), channel \(component)")
                }
            }
        }
    }

    private func assertNumberedGrid(_ raster: MPVDecoderRaster, expectedFrame: Int) throws {
        XCTAssertEqual(raster.pixels.width, 16)
        XCTAssertEqual(raster.pixels.height, 16)
        XCTAssertEqual(try XCTUnwrap(raster.pixels.playbackTime), Double(expectedFrame) / 5, accuracy: 0.000_001)
        let bytes = [UInt8](raster.pixels.data)
        guard raster.pixels.width == 16, raster.pixels.height == 16,
              bytes.count >= raster.pixels.stride * 16 else { return XCTFail("Invalid numbered-grid raster") }
        for y in 0..<16 {
            for x in 0..<16 {
                let offset = y * raster.pixels.stride + x * 4
                XCTAssertEqual(Array(bytes[offset..<(offset + 4)]),
                               [UInt8((x + y) * 7), UInt8(y * 13), UInt8((x * 13 + expectedFrame * 17) % 256), 255])
            }
        }
    }

    private func makeController(url: URL) async throws -> PlayerController {
        let controller = PlayerController(proResRAWDetector: { _, _ in true })
        controller.loadMedia(PlayerWindowCoordinator.makeMediaItem(for: url))
        let ready = await waitUntil { controller.isReady && controller.player?.currentItem?.tracks.isEmpty == false }
        XCTAssertTrue(ready)
        controller.pause()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: controller.player)
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        retainedSurfaces.append(view)
        return controller
    }

    private func fixture(_ name: String) throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let root = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? repository.appending(path: "Test Fixtures/Generated")
        let url = root.appending(path: "loupe/\(name).mp4")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Run scripts/generate-test-fixtures.sh to create loupe decoder fixtures")
        }
        return url
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return predicate()
    }

    private func assertQuadrants(_ expected: [NSColor], image: CGImage) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let positions = [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
        for (target, position) in zip(expected, positions) {
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(Double(image.width) * position.0),
                                                   y: Int(Double(image.height) * position.1))?.usingColorSpace(.deviceRGB))
            let target = try XCTUnwrap(target.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, target.redComponent, accuracy: 0.25)
            XCTAssertEqual(color.greenComponent, target.greenComponent, accuracy: 0.25)
            XCTAssertEqual(color.blueComponent, target.blueComponent, accuracy: 0.25)
        }
    }
}
