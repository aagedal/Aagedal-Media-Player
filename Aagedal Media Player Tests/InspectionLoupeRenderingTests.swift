// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class InspectionLoupeRenderingTests: XCTestCase {
    private let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let yellow = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)
    private let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    func testActualLensCentersSelectedImageRegionAtEveryMagnification() throws {
        let image = try makeAsymmetricImage()
        for scale: CGFloat in [1, 2] {
            for magnification in LoupeMagnification.allCases {
                for (point, expected) in [
                    (CGPoint(x: 0.25, y: 0.25), red),
                    (CGPoint(x: 0.75, y: 0.75), yellow)
                ] {
                    let bitmap = try render(image, point: point, magnification: magnification, scale: scale)
                    // Twelve points diagonally away from the crosshair avoids
                    // the glyph and its shadow while sampling the selected patch.
                    try assertColor(expected, in: bitmap, at: CGPoint(x: 92, y: 72), scale: scale)
                }
            }
        }
    }

    func testActualLensShowsBlackBeyondImageEdgesWithoutShiftingTheInspectedPoint() throws {
        let image = try makeAsymmetricImage()
        for scale: CGFloat in [1, 2] {
            for magnification in LoupeMagnification.allCases {
                let topLeft = try render(image, point: .zero, magnification: magnification, scale: scale)
                try assertColor(black, in: topLeft, at: CGPoint(x: 66, y: 46), scale: scale)
                try assertColor(red, in: topLeft, at: CGPoint(x: 94, y: 74), scale: scale)

                let bottomRight = try render(image, point: CGPoint(x: 1, y: 1), magnification: magnification, scale: scale)
                try assertColor(yellow, in: bottomRight, at: CGPoint(x: 66, y: 46), scale: scale)
                try assertColor(black, in: bottomRight, at: CGPoint(x: 94, y: 74), scale: scale)
            }
        }
    }

    private func render(
        _ image: CGImage,
        point: CGPoint,
        magnification: LoupeMagnification,
        scale: CGFloat
    ) throws -> CGImage {
        let lens = InspectionLoupeLens(
            image: image, source: "A", size: CGSize(width: 160, height: 120),
            pictureSize: CGSize(width: 200, height: 100),
            normalizedPoint: point, magnification: magnification
        )
        .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: lens)
        renderer.scale = scale
        let rendered = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(rendered.width, Int(160 * scale))
        XCTAssertEqual(rendered.height, Int(146 * scale))
        return rendered
    }

    private func assertColor(
        _ expected: NSColor,
        in bitmap: CGImage,
        at point: CGPoint,
        scale: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pixel = try XCTUnwrap(bitmap.cropping(to: CGRect(
            x: Int(point.x * scale), y: Int(point.y * scale), width: 1, height: 1
        )), file: file, line: line)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB), file: file, line: line)
        // NSBitmapImageRep.colorAt can report calibrated RGB even for an sRGB
        // CGImage, introducing a second, incorrect profile conversion. Read
        // through an explicitly tagged RGBA context instead.
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), file: file, line: line)
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try XCTUnwrap(context.data, file: file, line: line).assumingMemoryBound(to: UInt8.self)
        let expected = try XCTUnwrap(expected.usingColorSpace(.sRGB), file: file, line: line)
        let actual = (0..<4).map { CGFloat(bytes[$0]) / 255 }
        let diagnostic = "Sample \(point) at \(scale)×: RGBA \(actual), expected \(expected)"
        XCTAssertEqual(actual[0], expected.redComponent, accuracy: 0.04, diagnostic, file: file, line: line)
        XCTAssertEqual(actual[1], expected.greenComponent, accuracy: 0.04, diagnostic, file: file, line: line)
        XCTAssertEqual(actual[2], expected.blueComponent, accuracy: 0.04, diagnostic, file: file, line: line)
        XCTAssertEqual(actual[3], 1, accuracy: 0.01, diagnostic, file: file, line: line)
    }

    /// Deliberately unequal regions reveal image-axis inversions and incorrect
    /// centering that a symmetric checkerboard or solid image could conceal.
    private func makeAsymmetricImage() throws -> CGImage {
        let width = 400
        let height = 200
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let upper = y < 80
                let left = x < 240
                pixels[index] = (upper && left) || (!upper && !left) ? 255 : 0
                pixels[index + 1] = left ? 0 : 255
                pixels[index + 2] = !upper && left ? 255 : 0
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        // Match source, expected values, and readback explicitly. Device RGB
        // depends on the test host's display profile and can shift primaries.
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
