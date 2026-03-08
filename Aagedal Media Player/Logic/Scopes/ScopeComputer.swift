// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// CPU-based waveform and vectorscope computation from CGImage frames.

import CoreGraphics
import AppKit

enum ScopeComputer: Sendable {

    // MARK: - Waveform (Luma)

    /// Generates a waveform monitor image from a video frame.
    /// Each column corresponds to a source pixel column; Y axis represents luma (0 at bottom, 1 at top).
    /// Brightness is proportional to pixel density at each luma level.
    nonisolated static func computeWaveform(from image: CGImage, outputSize: CGSize) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard let pixelData = extractPixelData(from: image) else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        // Accumulate luma histogram per output column
        // histogram[col][lumaRow] = count of pixels mapping to that luma level
        var histogram = [[UInt32]](repeating: [UInt32](repeating: 0, count: outH), count: outW)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let b = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let r = CGFloat(pixelData[offset + 2]) / 255.0

                // BT.709 luma
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let col = x * outW / width
                let row = outH - 1 - min(Int(luma * CGFloat(outH - 1)), outH - 1)

                histogram[min(col, outW - 1)][row] += 1
            }
        }

        // Find max density for normalization
        var maxDensity: UInt32 = 1
        for col in 0..<outW {
            for row in 0..<outH {
                maxDensity = max(maxDensity, histogram[col][row])
            }
        }

        // Render into BGRA buffer
        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)

        for col in 0..<outW {
            for row in 0..<outH {
                let count = histogram[col][row]
                guard count > 0 else { continue }

                // Non-linear mapping for better visibility
                let normalized = CGFloat(count) / CGFloat(maxDensity)
                let brightness = UInt8(min(pow(normalized, 0.4) * 255, 255))

                let offset = (row * outW + col) * 4
                // Green-tinted waveform
                outputPixels[offset] = 0                           // B
                outputPixels[offset + 1] = brightness              // G
                outputPixels[offset + 2] = brightness / 3          // R
                outputPixels[offset + 3] = 255                     // A
            }
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - RGB Parade

    /// Generates an RGB parade waveform — three side-by-side channel waveforms.
    nonisolated static func computeRGBParade(from image: CGImage, outputSize: CGSize) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard let pixelData = extractPixelData(from: image) else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        let paradeW = outW / 3

        // Histograms for R, G, B channels
        var histR = [[UInt32]](repeating: [UInt32](repeating: 0, count: outH), count: paradeW)
        var histG = [[UInt32]](repeating: [UInt32](repeating: 0, count: outH), count: paradeW)
        var histB = [[UInt32]](repeating: [UInt32](repeating: 0, count: outH), count: paradeW)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let b = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let r = CGFloat(pixelData[offset + 2]) / 255.0

                let col = min(x * paradeW / width, paradeW - 1)

                let rowR = outH - 1 - min(Int(r * CGFloat(outH - 1)), outH - 1)
                let rowG = outH - 1 - min(Int(g * CGFloat(outH - 1)), outH - 1)
                let rowB = outH - 1 - min(Int(b * CGFloat(outH - 1)), outH - 1)

                histR[col][rowR] += 1
                histG[col][rowG] += 1
                histB[col][rowB] += 1
            }
        }

        var maxDensity: UInt32 = 1
        for col in 0..<paradeW {
            for row in 0..<outH {
                maxDensity = max(maxDensity, histR[col][row])
                maxDensity = max(maxDensity, histG[col][row])
                maxDensity = max(maxDensity, histB[col][row])
            }
        }

        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)

        for col in 0..<paradeW {
            for row in 0..<outH {
                // Red channel
                if histR[col][row] > 0 {
                    let brightness = UInt8(min(pow(CGFloat(histR[col][row]) / CGFloat(maxDensity), 0.4) * 255, 255))
                    let px = (row * outW + col) * 4
                    outputPixels[px] = 0
                    outputPixels[px + 1] = brightness / 4
                    outputPixels[px + 2] = brightness
                    outputPixels[px + 3] = 255
                }

                // Green channel
                if histG[col][row] > 0 {
                    let brightness = UInt8(min(pow(CGFloat(histG[col][row]) / CGFloat(maxDensity), 0.4) * 255, 255))
                    let px = (row * outW + col + paradeW) * 4
                    outputPixels[px] = 0
                    outputPixels[px + 1] = brightness
                    outputPixels[px + 2] = brightness / 4
                    outputPixels[px + 3] = 255
                }

                // Blue channel
                if histB[col][row] > 0 {
                    let brightness = UInt8(min(pow(CGFloat(histB[col][row]) / CGFloat(maxDensity), 0.4) * 255, 255))
                    let px = (row * outW + col + paradeW * 2) * 4
                    outputPixels[px] = brightness
                    outputPixels[px + 1] = brightness / 4
                    outputPixels[px + 2] = 0
                    outputPixels[px + 3] = 255
                }
            }
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - Vectorscope

    /// Generates a vectorscope image from a video frame.
    /// Plots Cb on X axis, Cr on Y axis (BT.709 matrix), centered.
    nonisolated static func computeVectorscope(from image: CGImage, outputSize: CGSize) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard let pixelData = extractPixelData(from: image) else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        // 2D histogram for vectorscope
        var histogram = [[UInt32]](repeating: [UInt32](repeating: 0, count: outW), count: outH)

        let halfW = CGFloat(outW) / 2.0
        let halfH = CGFloat(outH) / 2.0
        // Scale so full chroma range fits within the circle
        let scale = min(halfW, halfH) * 0.9

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let b = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let r = CGFloat(pixelData[offset + 2]) / 255.0

                // BT.709 YCbCr conversion
                let cb = -0.1146 * r - 0.3854 * g + 0.5 * b
                let cr =  0.5 * r - 0.4542 * g - 0.0458 * b

                // Map to output coordinates (Cb = X, Cr = Y inverted)
                let px = Int(halfW + cb * scale * 2.0)
                let py = Int(halfH - cr * scale * 2.0)

                if px >= 0, px < outW, py >= 0, py < outH {
                    histogram[py][px] += 1
                }
            }
        }

        // Find max density
        var maxDensity: UInt32 = 1
        for row in 0..<outH {
            for col in 0..<outW {
                maxDensity = max(maxDensity, histogram[row][col])
            }
        }

        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)

        for row in 0..<outH {
            for col in 0..<outW {
                let count = histogram[row][col]
                guard count > 0 else { continue }

                let normalized = CGFloat(count) / CGFloat(maxDensity)
                let brightness = UInt8(min(pow(normalized, 0.35) * 255, 255))

                let offset = (row * outW + col) * 4
                // White/green tinted
                outputPixels[offset] = brightness / 3       // B
                outputPixels[offset + 1] = brightness        // G
                outputPixels[offset + 2] = brightness / 2    // R
                outputPixels[offset + 3] = 255               // A
            }
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - Graticule

    /// Draws vectorscope graticule overlay: color targets and skin tone line.
    nonisolated static func drawVectorscopeGraticule(size: CGSize) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let halfW = size.width / 2.0
        let halfH = size.height / 2.0
        let scale = min(halfW, halfH) * 0.9

        guard let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip coordinates for standard drawing
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let center = CGPoint(x: halfW, y: halfH)

        // Draw crosshairs
        context.setStrokeColor(CGColor(gray: 0.3, alpha: 1.0))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 0, y: halfH))
        context.addLine(to: CGPoint(x: size.width, y: halfH))
        context.move(to: CGPoint(x: halfW, y: 0))
        context.addLine(to: CGPoint(x: halfW, y: size.height))
        context.strokePath()

        // Draw circle at 75% chroma
        context.setStrokeColor(CGColor(gray: 0.25, alpha: 1.0))
        context.setLineWidth(0.5)
        context.addArc(center: center, radius: scale * 0.75 * 2.0, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        // Color target positions (BT.709 75% bars)
        // Format: (Cb, Cr, color label)
        let targets: [(cb: CGFloat, cr: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, label: String)] = [
            ( 0.5,    -0.4542, 0.75, 0.0,  0.0,  "R"),   // Red
            (-0.3854,  0.5,    0.0,  0.75, 0.0,  "G"),   // Green
            ( 0.5,     0.0458, 0.0,  0.0,  0.75, "B"),   // Blue
            (-0.5,     0.4542, 0.0,  0.75, 0.75, "Cy"),  // Cyan
            ( 0.3854, -0.5,    0.75, 0.0,  0.75, "Mg"),  // Magenta
            (-0.5,    -0.0458, 0.75, 0.75, 0.0,  "Yl"),  // Yellow
        ]

        let targetSize: CGFloat = 8
        context.setLineWidth(1.0)

        for target in targets {
            let x = halfW + target.cb * scale * 2.0
            let y = halfH - target.cr * scale * 2.0

            context.setStrokeColor(CGColor(red: target.r, green: target.g, blue: target.b, alpha: 0.8))
            context.addRect(CGRect(x: x - targetSize / 2, y: y - targetSize / 2, width: targetSize, height: targetSize))
            context.strokePath()
        }

        // Skin tone line (roughly 123 degrees from Cb axis, which is about I-axis)
        let skinAngle: CGFloat = 123.0 * .pi / 180.0
        let lineLen = scale * 2.0
        context.setStrokeColor(CGColor(gray: 0.4, alpha: 0.8))
        context.setLineWidth(0.75)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.move(to: center)
        context.addLine(to: CGPoint(
            x: center.x + cos(skinAngle) * lineLen,
            y: center.y - sin(skinAngle) * lineLen
        ))
        context.strokePath()

        return context.makeImage()
    }

    /// Draws waveform graticule overlay with IRE markings.
    nonisolated static func drawWaveformGraticule(size: CGSize) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        guard let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        context.setStrokeColor(CGColor(gray: 0.25, alpha: 1.0))
        context.setLineWidth(0.5)

        // IRE lines at 0, 25, 50, 75, 100
        let ireValues: [CGFloat] = [0, 25, 50, 75, 100]
        let font = CTFontCreateWithName("Menlo" as CFString, 9, nil)

        for ire in ireValues {
            let y = size.height * (1.0 - ire / 100.0)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            context.strokePath()

            // Draw label
            let label = "\(Int(ire))" as CFString
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 0.4, alpha: 1.0)
            ]
            let attrString = CFAttributedStringCreate(nil, label, attrs as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attrString)
            context.textPosition = CGPoint(x: 2, y: y + 2)
            CTLineDraw(line, context)
        }

        return context.makeImage()
    }

    // MARK: - Helpers

    nonisolated private static func extractPixelData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }

    nonisolated private static func createCGImage(from pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
