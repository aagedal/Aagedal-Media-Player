// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest
import CoreGraphics

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
}
