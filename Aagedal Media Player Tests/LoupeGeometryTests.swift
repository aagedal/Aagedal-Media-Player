// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class LoupeGeometryTests: XCTestCase {
    func testPinnedOverlayRemainsInsideCanvasAfterResize() {
        let canvas = CGSize(width: 500, height: 400)
        let overlay = CGSize(width: 366, height: 166)
        for pointer in [CGPoint(x: 900, y: 800), CGPoint(x: -100, y: -100)] {
            let center = LoupeGeometry.overlayCenter(canvasSize: canvas, overlaySize: overlay, pointer: pointer)
            XCTAssertGreaterThanOrEqual(center.x - overlay.width / 2, 8)
            XCTAssertGreaterThanOrEqual(center.y - overlay.height / 2, 8)
            XCTAssertLessThanOrEqual(center.x + overlay.width / 2, canvas.width - 8)
            XCTAssertLessThanOrEqual(center.y + overlay.height / 2, canvas.height - 8)
        }
    }

    func testOverlayPrefersBelowPointerAndFlipsAboveNearBottom() {
        let canvas = CGSize(width: 800, height: 600)
        let overlay = CGSize(width: 180, height: 166)
        XCTAssertEqual(
            LoupeGeometry.overlayCenter(canvasSize: canvas, overlaySize: overlay, pointer: CGPoint(x: 400, y: 200)),
            CGPoint(x: 400, y: 307)
        )
        XCTAssertEqual(
            LoupeGeometry.overlayCenter(canvasSize: canvas, overlaySize: overlay, pointer: CGPoint(x: 400, y: 500)),
            CGPoint(x: 400, y: 393)
        )
    }

    func testSmallCanvasReducesMarginAndCentersOversizedOverlay() {
        let overlay = CGSize(width: 180, height: 166)
        XCTAssertEqual(
            LoupeGeometry.overlayCenter(canvasSize: CGSize(width: 186, height: 172), overlaySize: overlay,
                                       pointer: CGPoint(x: 900, y: 800)),
            CGPoint(x: 93, y: 86)
        )
        XCTAssertEqual(
            LoupeGeometry.overlayCenter(canvasSize: CGSize(width: 100, height: 80), overlaySize: overlay,
                                       pointer: CGPoint(x: 900, y: 800)),
            CGPoint(x: 50, y: 40)
        )
    }

    func testLetterboxedPictureMapsTopLeftCenterAndBottomRight() {
        let picture = CGRect(x: 0, y: 60, width: 1_920, height: 1_080)

        XCTAssertEqual(LoupeGeometry.normalizedPoint(location: CGPoint(x: 0, y: 60), in: picture), .zero)
        XCTAssertEqual(
            LoupeGeometry.normalizedPoint(location: CGPoint(x: 960, y: 600), in: picture),
            CGPoint(x: 0.5, y: 0.5)
        )
        XCTAssertEqual(
            LoupeGeometry.normalizedPoint(location: CGPoint(x: 1_920, y: 1_140), in: picture),
            CGPoint(x: 1, y: 1)
        )
        XCTAssertNil(LoupeGeometry.normalizedPoint(location: CGPoint(x: 960, y: 59), in: picture))
        XCTAssertNil(LoupeGeometry.normalizedPoint(location: CGPoint(x: 960, y: 1_141), in: picture))
    }

    func testPillarboxedPictureRejectsBarsAndKeepsVerticalCoordinates() {
        let picture = CGRect(x: 400, y: 0, width: 600, height: 1_000)

        XCTAssertNil(LoupeGeometry.normalizedPoint(location: CGPoint(x: 399, y: 500), in: picture))
        XCTAssertNil(LoupeGeometry.normalizedPoint(location: CGPoint(x: 1_001, y: 500), in: picture))
        XCTAssertEqual(
            LoupeGeometry.normalizedPoint(location: CGPoint(x: 550, y: 750), in: picture),
            CGPoint(x: 0.25, y: 0.75)
        )
    }

    func testInvalidPictureOrPointerDoesNotProduceAnInspectionPoint() {
        let valid = CGRect(x: 0, y: 0, width: 100, height: 100)
        for point in [CGPoint(x: CGFloat.nan, y: 50), CGPoint(x: 50, y: CGFloat.infinity)] {
            XCTAssertNil(LoupeGeometry.normalizedPoint(location: point, in: valid))
        }
        for picture in [
            CGRect.zero,
            CGRect(x: 0, y: 0, width: -100, height: 100),
            CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: CGFloat.nan)
        ] {
            XCTAssertNil(LoupeGeometry.normalizedPoint(location: .zero, in: picture))
        }
    }

    func testFixedMagnificationUsesFittedPictureSizeAcrossAspectRatios() {
        for picture in [
            CGSize(width: 960, height: 540),
            CGSize(width: 300, height: 500),
            CGSize(width: 600, height: 600)
        ] {
            for (mode, factor) in [(LoupeMagnification.twoTimes, 2.0), (.fourTimes, 4.0), (.eightTimes, 8.0)] {
                let frame = placement(picture: picture, mode: mode)
                XCTAssertEqual(frame.width, picture.width * factor)
                XCTAssertEqual(frame.height, picture.height * factor)
                XCTAssertEqual(frame.midX, 100)
                XCTAssertEqual(frame.midY, 80)
            }
        }
    }

    func testNativePixelsAccountsForRetinaAndIgnoresFittedPictureSize() {
        let retina = placement(mode: .nativePixels, displayScale: 2)
        let standard = placement(mode: .nativePixels, displayScale: 1)

        XCTAssertEqual(retina.size, CGSize(width: 1_920, height: 1_080))
        XCTAssertEqual(standard.size, CGSize(width: 3_840, height: 2_160))
        XCTAssertEqual(retina.width * 2, 3_840)
        XCTAssertEqual(retina, placement(picture: CGSize(width: 480, height: 270), mode: .nativePixels, displayScale: 2))
    }

    func testInspectedPointRemainsCenteredAtEdgesWithoutPanningImageInward() {
        for point in [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: 0.25, y: 0.75)] {
            for mode in LoupeMagnification.allCases {
                let frame = placement(point: point, mode: mode)
                XCTAssertEqual(frame.minX + point.x * frame.width, 100)
                XCTAssertEqual(frame.minY + point.y * frame.height, 80)
            }
        }
        XCTAssertEqual(placement(point: .zero).origin, CGPoint(x: 100, y: 80))
        XCTAssertEqual(placement(point: CGPoint(x: 1, y: 1)).maxX, 100)
        XCTAssertEqual(placement(point: CGPoint(x: 1, y: 1)).maxY, 80)
    }

    func testPlacementClampsOutOfBoundsPointAndCentersNonfiniteCoordinates() {
        XCTAssertEqual(placement(point: CGPoint(x: -1, y: 2)), placement(point: CGPoint(x: 0, y: 1)))
        XCTAssertEqual(placement(point: CGPoint(x: CGFloat.nan, y: CGFloat.infinity)), placement())
    }

    func testInvalidScaleFallsBackToOnePhysicalPixelPerPoint() {
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertEqual(placement(mode: .nativePixels, displayScale: scale), placement(mode: .nativePixels, displayScale: 1))
        }
    }

    func testInvalidSizesAndOverflowProduceEmptyPlacement() {
        for size in [CGSize.zero, CGSize(width: -1, height: 2), CGSize(width: CGFloat.infinity, height: 2)] {
            XCTAssertEqual(placement(picture: size), .zero)
            XCTAssertEqual(LoupeGeometry.imagePlacement(
                imageSize: size, pictureSize: CGSize(width: 100, height: 100), normalizedPoint: .zero,
                lensSize: CGSize(width: 200, height: 160), magnification: .twoTimes, displayScale: 2
            ), .zero)
            XCTAssertEqual(LoupeGeometry.imagePlacement(
                imageSize: CGSize(width: 100, height: 100), pictureSize: CGSize(width: 100, height: 100),
                normalizedPoint: .zero, lensSize: size, magnification: .twoTimes, displayScale: 2
            ), .zero)
        }
        XCTAssertEqual(placement(picture: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100)), .zero)
    }

    private func placement(
        picture: CGSize = CGSize(width: 960, height: 540),
        point: CGPoint = CGPoint(x: 0.5, y: 0.5),
        mode: LoupeMagnification = .twoTimes,
        displayScale: CGFloat = 2
    ) -> CGRect {
        LoupeGeometry.imagePlacement(
            imageSize: CGSize(width: 3_840, height: 2_160), pictureSize: picture,
            normalizedPoint: point, lensSize: CGSize(width: 200, height: 160),
            magnification: mode, displayScale: displayScale
        )
    }
}
