// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest
import CoreGraphics
import CoreMedia
import CoreVideo

final class LoupeCaptureGateTests: XCTestCase {
    func testTrackRotationUsesCoreImageCoordinateHandedness() {
        // A track with 90-degree display rotation reports this matrix. Applying
        // it directly to CIImage turns the picture in the opposite direction.
        let track = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        let converted = LoupeFrameCapture.coreImageTransform(track)
        let origin = CGPoint.zero.applying(converted)
        let right = CGPoint(x: 1, y: 0).applying(converted)
        XCTAssertEqual(right.x, origin.x)
        XCTAssertEqual(right.y, origin.y + 1)

        let mirrored = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 64, ty: 0)
        XCTAssertEqual(LoupeFrameCapture.coreImageTransform(mirrored), mirrored)
        XCTAssertEqual(LoupeFrameCapture.coreImageTransform(.identity), .identity)
    }

    func testNativePixelVerificationAcceptsWholePixelRotationsAndReflections() {
        let transforms = [
            CGAffineTransform.identity,
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920),
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1920, ty: 0),
            CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 1080, ty: 1920)
        ]
        for transform in transforms {
            XCTAssertTrue(LoupeFrameCapture.isPixelPreserving(transform), "\(transform)")
        }
    }

    func testNativePixelVerificationRejectsResamplingEvenWhenBoundsCouldMatch() {
        // A 100×100 raster with this shear and scale retains 100×100 bounds,
        // yet its pixels are interpolated rather than copied one for one.
        let sameBoundsShear = CGAffineTransform(a: 0.5, b: 0, c: 0.5, d: 1, tx: 0, ty: 0)
        for transform in [
            sameBoundsShear,
            CGAffineTransform(a: 0.5, b: 0, c: 0, d: 1, tx: 0, ty: 0),
            CGAffineTransform(a: 0.9999999, b: 0, c: 0, d: 1, tx: 0, ty: 0),
            CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0.5, ty: 0),
            CGAffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        ] {
            XCTAssertFalse(LoupeFrameCapture.isPixelPreserving(transform), "\(transform)")
        }
    }

    func testNativeRasterChecksDecodedBufferBeforeRotationAndPARCorrection() throws {
        let format = try videoFormat(width: 8, height: 6, anamorphic: true)
        let codedBuffer = try pixelBuffer(width: 8, height: 6)
        // The track's 4:3 PAR belongs to display geometry. It must not make a
        // 10-pixel-wide negotiated buffer qualify as the eight-pixel raster.
        XCTAssertTrue(LoupeFrameCapture.isSourceRaster(codedBuffer, format: format, transform: .identity))
        XCTAssertFalse(LoupeFrameCapture.isSourceRaster(
            try pixelBuffer(width: 10, height: 6), format: format, transform: .identity
        ))

        let rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 8)
        XCTAssertTrue(LoupeFrameCapture.isSourceRaster(codedBuffer, format: format, transform: rotation))
        XCTAssertFalse(LoupeFrameCapture.isSourceRaster(
            try pixelBuffer(width: 6, height: 8), format: format, transform: rotation
        ), "An already-oriented buffer must not qualify as the original coded raster")

        let reflection = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 8, ty: 0)
        XCTAssertTrue(LoupeFrameCapture.isSourceRaster(codedBuffer, format: format, transform: reflection))
    }

    func testNativeRasterRejectsUnknownFormatAndScaledDecoderOutput() throws {
        let buffer = try pixelBuffer(width: 8, height: 6)
        XCTAssertFalse(LoupeFrameCapture.isSourceRaster(buffer, format: nil, transform: .identity))
        XCTAssertFalse(LoupeFrameCapture.isSourceRaster(
            buffer, format: try videoFormat(width: 16, height: 12), transform: .identity
        ), "Cached UI metadata could match this buffer, but the active track's coded raster does not")
        XCTAssertFalse(LoupeFrameCapture.isSourceRaster(
            buffer, format: try videoFormat(width: 8, height: 6),
            transform: CGAffineTransform(a: 0.5, b: 0, c: 0.5, d: 1, tx: 0, ty: 0)
        ), "Coded buffer dimensions must not override evidence of resampling")
    }

    func testOnlyOneWorkerCanStart() throws {
        var gate = LoupeCaptureGate()
        XCTAssertNil(gate.begin())
        gate.start()
        let token = try XCTUnwrap(gate.begin())
        XCTAssertNil(gate.begin())
        XCTAssertTrue(gate.complete(token))
        let next = try XCTUnwrap(gate.begin())
        XCTAssertNotEqual(next, token)
        XCTAssertFalse(gate.complete(token))
        XCTAssertEqual(gate.inFlight, next)
    }

    func testStopRejectsLateResultAndKeepsWorkerSlotOccupied() throws {
        var gate = LoupeCaptureGate()
        gate.start()
        let token = try XCTUnwrap(gate.begin())
        gate.stop()
        XCTAssertNil(gate.begin())
        gate.start()
        XCTAssertNil(gate.begin(), "Reopening must not queue another uncancellable screenshot")
        XCTAssertFalse(gate.complete(token))
        let next = try XCTUnwrap(gate.begin())
        XCTAssertNotEqual(next, token)
        XCTAssertTrue(gate.complete(next))
    }

    func testOldCompletionCannotReleaseNewWorkerSlot() throws {
        var gate = LoupeCaptureGate()
        gate.start()
        let old = try XCTUnwrap(gate.begin())
        gate.stop()
        XCTAssertFalse(gate.complete(old))
        gate.start()
        let current = try XCTUnwrap(gate.begin())
        XCTAssertFalse(gate.complete(old))
        XCTAssertEqual(gate.inFlight, current)
        XCTAssertTrue(gate.complete(current))
    }

    func testRejectsMalformedRawFrameWithoutReadingPastItsBuffer() {
        let truncated = screenshot(data: Data(repeating: 0, count: 7), width: 2, height: 1, stride: 8)
        XCTAssertNil(LoupeFrameCapture.image(from: truncated))
        let badStride = screenshot(data: Data(repeating: 0, count: 8), width: 2, height: 1, stride: 4)
        XCTAssertNil(LoupeFrameCapture.image(from: badStride))
        let unknown = screenshot(data: Data(repeating: 0, count: 8), width: 2, height: 1, stride: 8, format: "unknown")
        XCTAssertNil(LoupeFrameCapture.image(from: unknown))
    }

    func testPreservesFullMPVDisplayRaster() throws {
        let pixels = Data([0, 0, 255, 0, 0, 255, 0, 0])
        let image = try XCTUnwrap(LoupeFrameCapture.image(from: screenshot(data: pixels, width: 2, height: 1, stride: 8)))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.bytesPerRow, 8)
        let providerData = try XCTUnwrap(image.dataProvider?.data)
        XCTAssertEqual(providerData as Data, pixels)
    }

    private func screenshot(data: Data, width: Int, height: Int, stride: Int, format: String = "bgr0") -> MPVPlayer.RawScreenshot {
        MPVPlayer.RawScreenshot(data: data, width: width, height: height, stride: stride,
                                format: format, playbackTime: 0, playbackTimeUncertainty: 0)
    }

    private func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func videoFormat(width: Int32, height: Int32, anamorphic: Bool = false) throws -> CMFormatDescription {
        let extensions: CFDictionary? = anamorphic ? [
            kCMFormatDescriptionExtension_PixelAspectRatio as String: [
                kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String: 4,
                kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String: 3
            ]
        ] as CFDictionary : nil
        var format: CMFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA,
            width: width, height: height, extensions: extensions, formatDescriptionOut: &format
        ), noErr)
        return try XCTUnwrap(format)
    }
}
