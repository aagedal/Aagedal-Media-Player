// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// CPU-based waveform, parade, and vectorscope computation from CGImage frames.

import CoreGraphics
import AppKit

enum ScopeComputer: Sendable {

    // MARK: - Colorized Waveform (Luma)

    /// Generates a colorized waveform monitor image.
    /// Each column maps to source pixel columns; Y axis represents luma (0 bottom, 1 top).
    /// Pixels are colored by their actual RGB values with saturation boost for visibility.
    nonisolated static func computeWaveform(from image: CGImage, outputSize: CGSize) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let pixelData = extractPixelData(from: image) else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        // Flat bins indexed as [col * outH + level]
        let binCount = outW * outH
        var counts = [UInt32](repeating: 0, count: binCount)
        var sumR = [Float](repeating: 0, count: binCount)
        var sumG = [Float](repeating: 0, count: binCount)
        var sumB = [Float](repeating: 0, count: binCount)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let b = Float(pixelData[offset]) / 255.0
                let g = Float(pixelData[offset + 1]) / 255.0
                let r = Float(pixelData[offset + 2]) / 255.0

                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let col = min(x * outW / width, outW - 1)
                let level = min(Int(luma * Float(outH - 1)), outH - 1)

                let idx = col * outH + level
                counts[idx] &+= 1
                sumR[idx] += r
                sumG[idx] += g
                sumB[idx] += b
            }
        }

        var maxCount: UInt32 = 1
        for i in 0..<binCount {
            if counts[i] > maxCount { maxCount = counts[i] }
        }

        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)
        let normFactor: Float = 1.0 / (Float(maxCount) * 0.25)

        for col in 0..<outW {
            for level in 0..<outH {
                let idx = col * outH + level
                let count = counts[idx]
                guard count > 0 else { continue }

                let intensity = min(Float(count) * normFactor, 1.0)
                let invCount = 1.0 / Float(count)
                var avgR = sumR[idx] * invCount
                var avgG = sumG[idx] * invCount
                var avgB = sumB[idx] * invCount

                // Saturation boost for visibility
                let gray = (avgR + avgG + avgB) / 3.0
                let satBoost: Float = 1.8
                avgR = gray + (avgR - gray) * satBoost
                avgG = gray + (avgG - gray) * satBoost
                avgB = gray + (avgB - gray) * satBoost

                // Normalize — ensure minimum brightness so sparse data is visible
                let maxC = max(avgR, avgG, avgB, 0.3)
                let invMax = 1.0 / maxC
                avgR = max(avgR * invMax, 0.08)
                avgG = max(avgG * invMax, 0.08)
                avgB = max(avgB * invMax, 0.08)

                let row = outH - 1 - level
                let px = (row * outW + col) * 4
                outputPixels[px]     = UInt8(min(avgB * intensity * 255, 255))
                outputPixels[px + 1] = UInt8(min(avgG * intensity * 255, 255))
                outputPixels[px + 2] = UInt8(min(avgR * intensity * 255, 255))
                outputPixels[px + 3] = 255
            }
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - RGBY Parade

    /// Generates an RGBY parade — four side-by-side channel waveforms (Red, Green, Blue, Luma).
    nonisolated static func computeParade(from image: CGImage, outputSize: CGSize) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let pixelData = extractPixelData(from: image) else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        let channelCount = 4
        let gap = 2
        let totalGaps = gap * (channelCount - 1)
        let channelW = (outW - totalGaps) / channelCount
        guard channelW > 1 else { return nil }

        let binCount = channelW * outH
        var rBins = [UInt32](repeating: 0, count: binCount)
        var gBins = [UInt32](repeating: 0, count: binCount)
        var bBins = [UInt32](repeating: 0, count: binCount)
        var yBins = [UInt32](repeating: 0, count: binCount)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let bVal = Float(pixelData[offset]) / 255.0
                let gVal = Float(pixelData[offset + 1]) / 255.0
                let rVal = Float(pixelData[offset + 2]) / 255.0
                let luma = 0.2126 * rVal + 0.7152 * gVal + 0.0722 * bVal

                let col = min(x * channelW / width, channelW - 1)

                let rLevel = min(Int(rVal * Float(outH - 1)), outH - 1)
                let gLevel = min(Int(gVal * Float(outH - 1)), outH - 1)
                let bLevel = min(Int(bVal * Float(outH - 1)), outH - 1)
                let yLevel = min(Int(luma * Float(outH - 1)), outH - 1)

                rBins[col * outH + rLevel] &+= 1
                gBins[col * outH + gLevel] &+= 1
                bBins[col * outH + bLevel] &+= 1
                yBins[col * outH + yLevel] &+= 1
            }
        }

        var maxCount: UInt32 = 1
        for i in 0..<binCount {
            maxCount = max(maxCount, rBins[i], gBins[i], bBins[i], yBins[i])
        }

        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)
        let normFactor: Float = 1.0 / (Float(maxCount) * 0.25)

        // Channel tint colors
        let channelColors: [(r: Float, g: Float, b: Float)] = [
            (1.0, 0.2, 0.2),    // Red
            (0.2, 1.0, 0.2),    // Green
            (0.3, 0.4, 1.0),    // Blue
            (0.85, 0.85, 0.85), // Luma (Y)
        ]
        let allBins = [rBins, gBins, bBins, yBins]

        for ch in 0..<channelCount {
            let xOffset = ch * (channelW + gap)
            let bins = allBins[ch]
            let color = channelColors[ch]

            for col in 0..<channelW {
                for level in 0..<outH {
                    let count = bins[col * outH + level]
                    guard count > 0 else { continue }

                    let intensity = min(Float(count) * normFactor, 1.0)
                    let row = outH - 1 - level
                    let outX = xOffset + col
                    guard outX < outW else { continue }

                    let px = (row * outW + outX) * 4
                    outputPixels[px]     = UInt8(min(color.b * intensity * 255, 255))
                    outputPixels[px + 1] = UInt8(min(color.g * intensity * 255, 255))
                    outputPixels[px + 2] = UInt8(min(color.r * intensity * 255, 255))
                    outputPixels[px + 3] = 255
                }
            }
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - Colorized Vectorscope

    /// Generates a colorized vectorscope image.
    /// Plots Cb on X axis, Cr on Y axis (BT.709 matrix), centered.
    /// Pixels are colored by their actual RGB values with logarithmic intensity mapping.
    nonisolated static func computeVectorscope(from image: CGImage, outputSize: CGSize) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let pixelData = extractPixelData(from: image) else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        let halfW = Float(outW) / 2.0
        let halfH = Float(outH) / 2.0
        let scale = min(halfW, halfH) * 0.9

        let totalBins = outW * outH
        var counts = [UInt32](repeating: 0, count: totalBins)
        var sumR = [Float](repeating: 0, count: totalBins)
        var sumG = [Float](repeating: 0, count: totalBins)
        var sumB = [Float](repeating: 0, count: totalBins)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let bVal = Float(pixelData[offset]) / 255.0
                let gVal = Float(pixelData[offset + 1]) / 255.0
                let rVal = Float(pixelData[offset + 2]) / 255.0

                let cb = -0.1146 * rVal - 0.3854 * gVal + 0.5 * bVal
                let cr =  0.5 * rVal - 0.4542 * gVal - 0.0458 * bVal

                let px = Int(halfW + cb * scale * 2.0)
                let py = Int(halfH - cr * scale * 2.0)

                guard px >= 0, px < outW, py >= 0, py < outH else { continue }
                let idx = py * outW + px
                counts[idx] &+= 1
                sumR[idx] += rVal
                sumG[idx] += gVal
                sumB[idx] += bVal
            }
        }

        var maxCount: UInt32 = 1
        for i in 0..<totalBins {
            if counts[i] > maxCount { maxCount = counts[i] }
        }

        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)
        let logMax = log2f(1 + Float(maxCount))
        let gain: Float = 3.0

        for i in 0..<totalBins {
            let count = counts[i]
            guard count > 0 else { continue }

            // Logarithmic intensity makes sparse bins visible
            let intensity = min(log2f(1 + Float(count)) / logMax * gain, 1.0)
            let invCount = 1.0 / Float(count)
            var avgR = sumR[i] * invCount
            var avgG = sumG[i] * invCount
            var avgB = sumB[i] * invCount

            // Saturation boost
            let gray = (avgR + avgG + avgB) / 3.0
            let satBoost: Float = 2.0
            avgR = max(gray + (avgR - gray) * satBoost, 0.05)
            avgG = max(gray + (avgG - gray) * satBoost, 0.05)
            avgB = max(gray + (avgB - gray) * satBoost, 0.05)

            // Normalize
            let maxC = max(avgR, avgG, avgB, 0.01)
            avgR /= maxC
            avgG /= maxC
            avgB /= maxC

            let px = i * 4
            outputPixels[px]     = UInt8(min(avgB * intensity * 255, 255))
            outputPixels[px + 1] = UInt8(min(avgG * intensity * 255, 255))
            outputPixels[px + 2] = UInt8(min(avgR * intensity * 255, 255))
            outputPixels[px + 3] = 255
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - Graticules (rendered at 2x for Retina sharpness)

    /// Draws vectorscope graticule overlay: crosshairs, chroma circle, color targets, skin tone line.
    /// Rendered at 2x pixel resolution; use with `Image(decorative:scale: 2.0)`.
    nonisolated static func drawVectorscopeGraticule(size: CGSize) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let pixelW = w * 2
        let pixelH = h * 2

        let halfW = size.width / 2.0
        let halfH = size.height / 2.0
        let scale = min(halfW, halfH) * 0.9

        guard let context = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: pixelW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip Y and apply 2x scale so drawing uses logical coordinates
        context.translateBy(x: 0, y: CGFloat(pixelH))
        context.scaleBy(x: 2, y: -2)

        let center = CGPoint(x: halfW, y: halfH)

        // Crosshairs
        context.setStrokeColor(CGColor(gray: 0.3, alpha: 1.0))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 0, y: halfH))
        context.addLine(to: CGPoint(x: size.width, y: halfH))
        context.move(to: CGPoint(x: halfW, y: 0))
        context.addLine(to: CGPoint(x: halfW, y: size.height))
        context.strokePath()

        // 75% chroma circle — max chroma maps to distance `scale` from center,
        // so 75% is at radius `scale * 0.75`.
        context.setStrokeColor(CGColor(gray: 0.25, alpha: 1.0))
        context.setLineWidth(0.5)
        context.addArc(center: center, radius: scale * 0.75, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        // BT.709 75% color bar targets (Cb, Cr computed from the same matrix as data)
        let targets: [(cb: CGFloat, cr: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (-0.0860,  0.3750, 0.75, 0.15, 0.15),  // Red
            (-0.2891, -0.3407, 0.15, 0.75, 0.15),  // Green
            ( 0.3750, -0.0344, 0.15, 0.15, 0.75),  // Blue
            ( 0.0860, -0.3750, 0.15, 0.75, 0.75),  // Cyan
            ( 0.2891,  0.3407, 0.75, 0.15, 0.75),  // Magenta
            (-0.3750,  0.0344, 0.75, 0.75, 0.15),  // Yellow
        ]

        let targetSize: CGFloat = 8
        context.setLineWidth(1.0)

        for target in targets {
            // Same mapping as vectorscope data: Cb → X, positive Cr → up
            let x = halfW + target.cb * scale * 2.0
            let y = halfH - target.cr * scale * 2.0

            context.setStrokeColor(CGColor(red: target.r, green: target.g, blue: target.b, alpha: 0.8))
            context.addRect(CGRect(x: x - targetSize / 2, y: y - targetSize / 2, width: targetSize, height: targetSize))
            context.strokePath()
        }

        // Skin tone line (~123 degrees from Cb axis toward red/yellow)
        let skinAngle: CGFloat = 123.0 * .pi / 180.0
        let lineLen = scale
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
    /// Rendered at 2x pixel resolution; use with `Image(decorative:scale: 2.0)`.
    nonisolated static func drawWaveformGraticule(size: CGSize) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let pixelW = w * 2
        let pixelH = h * 2

        guard let context = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: pixelW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip Y and apply 2x scale so drawing uses logical coordinates
        context.translateBy(x: 0, y: CGFloat(pixelH))
        context.scaleBy(x: 2, y: -2)

        context.setStrokeColor(CGColor(gray: 0.25, alpha: 1.0))
        context.setLineWidth(0.5)

        let ireValues: [CGFloat] = [0, 25, 50, 75, 100]
        let font = CTFontCreateWithName("Menlo" as CFString, 9, nil)

        for ire in ireValues {
            let y = size.height * (1.0 - ire / 100.0)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            context.strokePath()

            let label = "\(Int(ire))" as CFString
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 0.4, alpha: 1.0)
            ]
            let attrString = CFAttributedStringCreate(nil, label, attrs as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attrString)
            // Un-flip Y locally so text renders right-side up
            context.saveGState()
            context.translateBy(x: 2, y: y + 11)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
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
