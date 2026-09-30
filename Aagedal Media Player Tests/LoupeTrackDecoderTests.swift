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
