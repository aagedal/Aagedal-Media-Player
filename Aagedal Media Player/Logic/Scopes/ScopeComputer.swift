// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// CPU-based waveform, parade, and vectorscope computation from CGImage frames.

import CoreGraphics
import AppKit

// MARK: - HDR Types

enum TransferFunction: Sendable {
    case sdr    // BT.1886/sRGB — show IRE
    case pq     // SMPTE ST 2084 — absolute nits 0-10000
    case hlg    // ARIB STD-B67 — scene-referred
}

struct HDRFrameData: Sendable, Equatable {
    let pixels: [Float]             // RGB interleaved, encoded values [0,1]
    let width: Int
    let height: Int
    let transferFunction: TransferFunction
    let isLinearLight: Bool         // true for AVPlayer float16 path
    let contentPeakNits: Float      // 10000 for PQ, 1000 for HLG, 100 for SDR

    // Custom Equatable: use identity (never equal) to always trigger onChange
    nonisolated static func == (lhs: HDRFrameData, rhs: HDRFrameData) -> Bool { false }
}

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
        // Logarithmic intensity so sparse bins are still visible
        let logMax = log2f(1 + Float(maxCount))
        let gain: Float = 2.5

        for col in 0..<outW {
            for level in 0..<outH {
                let idx = col * outH + level
                let count = counts[idx]
                guard count > 0 else { continue }

                let intensity = min(log2f(1 + Float(count)) / logMax * gain, 1.0)
                let invCount = 1.0 / Float(count)
                let avgR = sumR[idx] * invCount
                let avgG = sumG[idx] * invCount
                let avgB = sumB[idx] * invCount

                // Measure how chromatic this bin is (0 = gray, 1 = saturated).
                let gray = (avgR + avgG + avgB) / 3.0
                let maxDev = max(abs(avgR - gray), abs(avgG - gray), abs(avgB - gray))
                let saturation = min(maxDev / max(gray, 0.01), 1.0)

                // Boost saturation and normalize color to full brightness.
                let satBoost: Float = 2.5
                var cR = max(gray + (avgR - gray) * satBoost, 0)
                var cG = max(gray + (avgG - gray) * satBoost, 0)
                var cB = max(gray + (avgB - gray) * satBoost, 0)
                let maxC = max(cR, cG, cB, 0.01)
                cR /= maxC; cG /= maxC; cB /= maxC

                // Blend between white and the boosted color based on saturation.
                // Low saturation → white trace; high saturation → colored trace.
                let colorMix = min(saturation * 3.0, 1.0)
                let finalR = cR * colorMix + (1.0 - colorMix)
                let finalG = cG * colorMix + (1.0 - colorMix)
                let finalB = cB * colorMix + (1.0 - colorMix)

                // Use premultiplied alpha: intensity drives opacity so sparse
                // bins fade out instead of rendering as dark opaque pixels.
                let alpha = intensity
                let row = outH - 1 - level
                let px = (row * outW + col) * 4
                outputPixels[px]     = UInt8(min(finalB * alpha * 255, 255))
                outputPixels[px + 1] = UInt8(min(finalG * alpha * 255, 255))
                outputPixels[px + 2] = UInt8(min(finalR * alpha * 255, 255))
                outputPixels[px + 3] = UInt8(min(alpha * 255, 255))
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

    // MARK: - EOTF Conversion Functions

    /// PQ (ST 2084) EOTF: encoded signal [0,1] → absolute luminance in nits [0, 10000]
    nonisolated static func pqToNits(_ e: Float) -> Float {
        guard e > 0 else { return 0 }
        let m1: Float = 0.1593017578125
        let m2: Float = 78.84375
        let c1: Float = 0.8359375
        let c2: Float = 18.8515625
        let c3: Float = 18.6875

        let eM2 = powf(e, 1.0 / m2)
        let num = max(eM2 - c1, 0.0)
        let den = c2 - c3 * eM2
        guard den > 0 else { return 0 }
        return 10000.0 * powf(num / den, 1.0 / m1)
    }

    /// HLG inverse OETF + OOTF: encoded [0,1] → nits
    nonisolated static func hlgToNits(_ e: Float, peakNits: Float = 1000) -> Float {
        guard e > 0 else { return 0 }
        // Inverse OETF: encoded → scene linear
        let a: Float = 0.17883277
        let b: Float = 1.0 - 4.0 * a
        let c: Float = 0.5 - a * logf(4.0 * a)
        let scene: Float
        if e <= 0.5 {
            scene = (e * e) / 3.0
        } else {
            scene = (expf((e - c) / a) + b) / 12.0
        }
        // Simplified OOTF: scene linear → display nits
        // System gamma ~1.2 for 1000-nit display
        let gamma: Float = 1.2
        return peakNits * powf(scene, gamma)
    }

    /// AVPlayer linear-light → nits (1.0 = SDR reference white = 203 nits per BT.2408)
    nonisolated static func linearToNits(_ v: Float) -> Float {
        max(0, v) * 203.0
    }

    /// Floor of the decade-based log scale in nits. Values below this are clamped.
    /// Gives equal visual space per decade: 0.1–1, 1–10, 10–100, 100–1K, 1K–10K.
    nonisolated static let hdrMinNits: Float = 0.1

    /// Convert a nit value to a Y-axis bin using a decade-based log scale.
    /// Each decade (10× range) occupies equal vertical space, matching DaVinci Resolve style.
    nonisolated private static func nitsToLevel(_ nits: Float, outH: Int, peakNits: Float) -> Int {
        let logMin = log10f(hdrMinNits)
        let logMax = log10f(peakNits)
        let logRange = logMax - logMin
        guard logRange > 0 else { return 0 }
        let clamped = min(max(nits, hdrMinNits), peakNits)
        let normalized = (log10f(clamped) - logMin) / logRange  // 0…1
        return min(Int(normalized * Float(outH - 1)), outH - 1)
    }

    /// Convert pixel values to nits based on transfer function and linear-light flag.
    nonisolated private static func toNits(r: Float, g: Float, b: Float, tf: TransferFunction, isLinear: Bool, peakNits: Float) -> (rNits: Float, gNits: Float, bNits: Float) {
        if isLinear {
            return (linearToNits(r), linearToNits(g), linearToNits(b))
        }
        switch tf {
        case .pq:
            return (pqToNits(r), pqToNits(g), pqToNits(b))
        case .hlg:
            return (hlgToNits(r, peakNits: peakNits), hlgToNits(g, peakNits: peakNits), hlgToNits(b, peakNits: peakNits))
        case .sdr:
            return (r * 100.0, g * 100.0, b * 100.0)
        }
    }

    // MARK: - HDR Colorized Waveform (Luma)

    nonisolated static func computeHDRWaveform(from frame: HDRFrameData, outputSize: CGSize) -> CGImage? {
        let width = frame.width
        let height = frame.height
        guard width > 0, height > 0 else { return nil }

        let outW = Int(outputSize.width)
        let outH = Int(outputSize.height)
        guard outW > 0, outH > 0 else { return nil }

        let binCount = outW * outH
        var counts = [UInt32](repeating: 0, count: binCount)
        var sumR = [Float](repeating: 0, count: binCount)
        var sumG = [Float](repeating: 0, count: binCount)
        var sumB = [Float](repeating: 0, count: binCount)

        let tf = frame.transferFunction
        let isLinear = frame.isLinearLight
        let peakNits = frame.contentPeakNits

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 3
                let r = frame.pixels[offset]
                let g = frame.pixels[offset + 1]
                let b = frame.pixels[offset + 2]

                let (rNits, gNits, bNits) = toNits(r: r, g: g, b: b, tf: tf, isLinear: isLinear, peakNits: peakNits)
                // BT.2020 luma
                let lumaNits = 0.2627 * rNits + 0.6780 * gNits + 0.0593 * bNits

                let col = min(x * outW / width, outW - 1)
                let level = nitsToLevel(lumaNits, outH: outH, peakNits: peakNits)

                let idx = col * outH + level
                counts[idx] &+= 1
                // Store encoded RGB for colorization (normalized 0-1)
                let maxVal = max(r, g, b, 0.001)
                sumR[idx] += r / maxVal
                sumG[idx] += g / maxVal
                sumB[idx] += b / maxVal
            }
        }

        var maxCount: UInt32 = 1
        for i in 0..<binCount {
            if counts[i] > maxCount { maxCount = counts[i] }
        }

        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)
        let logMax = log2f(1 + Float(maxCount))
        let gain: Float = 2.5

        for col in 0..<outW {
            for level in 0..<outH {
                let idx = col * outH + level
                let count = counts[idx]
                guard count > 0 else { continue }

                let intensity = min(log2f(1 + Float(count)) / logMax * gain, 1.0)
                let invCount = 1.0 / Float(count)
                let avgR = sumR[idx] * invCount
                let avgG = sumG[idx] * invCount
                let avgB = sumB[idx] * invCount

                let gray = (avgR + avgG + avgB) / 3.0
                let maxDev = max(abs(avgR - gray), abs(avgG - gray), abs(avgB - gray))
                let saturation = min(maxDev / max(gray, 0.01), 1.0)

                let satBoost: Float = 2.5
                var cR = max(gray + (avgR - gray) * satBoost, 0)
                var cG = max(gray + (avgG - gray) * satBoost, 0)
                var cB = max(gray + (avgB - gray) * satBoost, 0)
                let maxC = max(cR, cG, cB, 0.01)
                cR /= maxC; cG /= maxC; cB /= maxC

                let colorMix = min(saturation * 3.0, 1.0)
                let finalR = cR * colorMix + (1.0 - colorMix)
                let finalG = cG * colorMix + (1.0 - colorMix)
                let finalB = cB * colorMix + (1.0 - colorMix)

                let alpha = intensity
                let row = outH - 1 - level
                let px = (row * outW + col) * 4
                outputPixels[px]     = UInt8(min(finalB * alpha * 255, 255))
                outputPixels[px + 1] = UInt8(min(finalG * alpha * 255, 255))
                outputPixels[px + 2] = UInt8(min(finalR * alpha * 255, 255))
                outputPixels[px + 3] = UInt8(min(alpha * 255, 255))
            }
        }

        return createCGImage(from: &outputPixels, width: outW, height: outH)
    }

    // MARK: - HDR RGBY Parade

    nonisolated static func computeHDRParade(from frame: HDRFrameData, outputSize: CGSize) -> CGImage? {
        let width = frame.width
        let height = frame.height
        guard width > 0, height > 0 else { return nil }

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

        let tf = frame.transferFunction
        let isLinear = frame.isLinearLight
        let peakNits = frame.contentPeakNits

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 3
                let r = frame.pixels[offset]
                let g = frame.pixels[offset + 1]
                let b = frame.pixels[offset + 2]

                let (rNits, gNits, bNits) = toNits(r: r, g: g, b: b, tf: tf, isLinear: isLinear, peakNits: peakNits)
                let lumaNits = 0.2627 * rNits + 0.6780 * gNits + 0.0593 * bNits

                let col = min(x * channelW / width, channelW - 1)

                let rLevel = nitsToLevel(rNits, outH: outH, peakNits: peakNits)
                let gLevel = nitsToLevel(gNits, outH: outH, peakNits: peakNits)
                let bLevel = nitsToLevel(bNits, outH: outH, peakNits: peakNits)
                let yLevel = nitsToLevel(lumaNits, outH: outH, peakNits: peakNits)

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

        let channelColors: [(r: Float, g: Float, b: Float)] = [
            (1.0, 0.2, 0.2),
            (0.2, 1.0, 0.2),
            (0.3, 0.4, 1.0),
            (0.85, 0.85, 0.85),
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
