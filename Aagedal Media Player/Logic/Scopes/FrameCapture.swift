// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Unified frame capture for video scopes — extracts decoded video frames
// from either AVPlayer (via AVPlayerItemVideoOutput) or MPV (via screenshot-raw).

import AVFoundation
import AppKit
import Combine
import OSLog
import VideoToolbox

@MainActor
final class FrameCapture: ObservableObject {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "FrameCapture")
    private nonisolated static let staticLogger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "FrameCapture")
    private nonisolated static let performanceSignposter = OSSignposter(
        subsystem: "com.aagedal.MediaPlayer",
        category: "ScopePerformance"
    )

    /// The latest captured frame, downscaled for scope computation (SDR path).
    @Published var currentFrame: CGImage?

    /// The latest captured HDR frame data (HDR path).
    @Published var currentHDRFrame: HDRFrameData?

    /// Transfer function of the current content.
    var transferFunction: TransferFunction = .sdr

    /// Peak luminance of the current content in nits.
    var contentPeakNits: Float = 100

    // AVPlayer capture
    private var videoOutput: AVPlayerItemVideoOutput?
    private var hdrVideoOutput: AVPlayerItemVideoOutput?
    private weak var player: AVPlayer?

    /// Called after the video output is removed so the host can rebuild the decode pipeline.
    var onAVOutputRemoved: (() -> Void)?

    // MPV capture via screenshot-raw
    private weak var mpvPlayer: MPVPlayer?
    private var mpvCaptureInFlight = false
    private nonisolated(unsafe) static var hdrFormatLogged = false

    // Shared timer
    private var captureTimer: Timer?
    private(set) var isCapturing = false

    /// Target downscale width for scope analysis, read from settings.
    private var analysisWidth: Int {
        UserDefaults.standard.value(for: AppSettings.scopeResolution)
    }

    // MARK: - AVPlayer Setup

    func attachAVPlayer(_ player: AVPlayer) {
        self.player = player
    }

    func detachAVPlayer() {
        if let output = videoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        if let output = hdrVideoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        videoOutput = nil
        hdrVideoOutput = nil
        player = nil
    }

    // MARK: - MPV Setup

    func attachMPV(_ mpv: MPVPlayer) {
        self.mpvPlayer = mpv
    }

    func detachMPV() {
        mpvPlayer = nil
    }

    // MARK: - Start / Stop

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        // Lazily attach AVPlayerItemVideoOutput only when capture is needed
        if let item = player?.currentItem {
            if transferFunction != .sdr {
                // HDR: use Float16 RGBA for linear-light extended-range capture
                if hdrVideoOutput == nil {
                    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_64RGBAHalf)
                    ])
                    item.add(output)
                    hdrVideoOutput = output
                    logger.info("Attached Float16 AVPlayerItemVideoOutput for HDR scope capture")
                }
            } else {
                // SDR: use standard 8-bit BGRA
                if videoOutput == nil {
                    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ])
                    item.add(output)
                    videoOutput = output
                    logger.info("Lazily attached AVPlayerItemVideoOutput for scope capture")
                }
            }
        }

        let fps = UserDefaults.standard.value(for: AppSettings.scopeFrameRate)
        let interval = 1.0 / max(fps, 1)
        captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame()
            }
        }

        logger.info("Scope frame capture started")
    }

    /// Stop capture. When `rebuildPipeline` is false, the AVFoundation decode pipeline
    /// rebuild is suppressed — used when switching capture format (SDR↔HDR) to avoid
    /// a teardown/rebuild cycle that resets the transfer function.
    func stopCapture(rebuildPipeline: Bool = true) {
        guard isCapturing else { return }
        isCapturing = false

        captureTimer?.invalidate()
        captureTimer = nil
        currentFrame = nil
        currentHDRFrame = nil
        Self.hdrFormatLogged = false

        // Remove video output so it doesn't interfere with playback pipeline
        let hadOutput = videoOutput != nil || hdrVideoOutput != nil
        if let output = videoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        if let output = hdrVideoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        videoOutput = nil
        hdrVideoOutput = nil

        // Force AVFoundation to rebuild its decode pipeline (ProRes RAW
        // tone-maps highlights when an output is attached and the pipeline
        // doesn't revert on its own after removing the output).
        // Deferred so the scope UI tears down fully before the item swap.
        if hadOutput && rebuildPipeline {
            let callback = onAVOutputRemoved
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                callback?()
            }
        }

        logger.info("Scope frame capture stopped")
    }

    // MARK: - Frame Capture

    private func captureFrame() {
        if transferFunction != .sdr {
            captureHDRFrame()
        } else if let output = videoOutput, let player {
            captureAVPlayerFrame(output: output, player: player)
        } else if mpvPlayer != nil {
            captureMPVFrame()
        }
    }

    private func captureHDRFrame() {
        if let output = hdrVideoOutput, let player {
            captureAVPlayerHDRFrame(output: output, player: player)
        } else if mpvPlayer != nil {
            captureMPVHDRFrame()
        }
    }

    private func captureAVPlayerFrame(output: AVPlayerItemVideoOutput, player: AVPlayer) {
        let interval = Self.performanceSignposter.beginInterval("Scope capture")
        defer { Self.performanceSignposter.endInterval("Scope capture", interval) }

        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return }
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

        currentFrame = downsamplePixelBuffer(pixelBuffer)
    }

    // MARK: - AVPlayer HDR Frame Capture

    private func captureAVPlayerHDRFrame(output: AVPlayerItemVideoOutput, player: AVPlayer) {
        let interval = Self.performanceSignposter.beginInterval("Scope capture")
        defer { Self.performanceSignposter.endInterval("Scope capture", interval) }

        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return }
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

        let targetW = analysisWidth
        let tf = transferFunction
        let peak = contentPeakNits

        // Extract HDR and SDR data on the main actor before sending to detached task
        let hdrFrame = Self.convertFloat16PixelBuffer(pixelBuffer, targetWidth: targetW, transferFunction: tf, peakNits: peak)
        let sdrFrame = downsamplePixelBuffer(pixelBuffer)

        currentHDRFrame = hdrFrame
        currentFrame = sdrFrame
    }

    /// Convert Float16 RGBA pixel buffer to HDRFrameData with RGB Float32 array.
    nonisolated private static func convertFloat16PixelBuffer(
        _ pixelBuffer: CVPixelBuffer, targetWidth: Int,
        transferFunction: TransferFunction, peakNits: Float
    ) -> HDRFrameData? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        guard srcW > 0, srcH > 0 else { return nil }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        // Check the pixel buffer's transfer function to determine if values are linear
        // AVFoundation may deliver Float16 in the source transfer function (PQ/HLG)
        // rather than linearized, depending on OS version and pipeline configuration.
        var isLinear = false
        if let tfAttachment = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, nil) {
            isLinear = CFEqual(tfAttachment, kCVImageBufferTransferFunction_Linear)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let srcPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Compute target dimensions
        let scale = srcW <= targetWidth ? 1.0 : Float(targetWidth) / Float(srcW)
        let dstW = srcW <= targetWidth ? srcW : targetWidth
        let dstH = srcW <= targetWidth ? srcH : Int(Float(srcH) * scale)
        guard dstW > 0, dstH > 0 else { return nil }

        // Each pixel: R16F, G16F, B16F, A16F (4 x Float16 = 8 bytes)
        var pixels = [Float](repeating: 0, count: dstW * dstH * 3)

        for dy in 0..<dstH {
            let sy = srcW <= targetWidth ? dy : min(Int(Float(dy) / scale), srcH - 1)
            let rowPtr = srcPtr.advanced(by: sy * bytesPerRow)

            for dx in 0..<dstW {
                let sx = srcW <= targetWidth ? dx : min(Int(Float(dx) / scale), srcW - 1)
                let pixelPtr = rowPtr.advanced(by: sx * 8) // 8 bytes per Float16 RGBA pixel
                let f16Ptr = pixelPtr.withMemoryRebound(to: UInt16.self, capacity: 4) { $0 }

                let dstOffset = (dy * dstW + dx) * 3
                pixels[dstOffset]     = float16ToFloat32(f16Ptr[0])
                pixels[dstOffset + 1] = float16ToFloat32(f16Ptr[1])
                pixels[dstOffset + 2] = float16ToFloat32(f16Ptr[2])
            }
        }

        return HDRFrameData(
            pixels: pixels,
            width: dstW,
            height: dstH,
            transferFunction: transferFunction,
            isLinearLight: isLinear,
            contentPeakNits: peakNits
        )
    }

    /// Convert IEEE 754 half-precision float to single-precision float.
    nonisolated private static func float16ToFloat32(_ h: UInt16) -> Float {
        Float(bitPattern: {
            let sign = UInt32(h >> 15) << 31
            let exp = UInt32((h >> 10) & 0x1F)
            let frac = UInt32(h & 0x3FF)

            if exp == 0 {
                if frac == 0 { return sign }
                // Denormalized
                var f = frac
                var e: UInt32 = 113
                while f & 0x400 == 0 { f <<= 1; e -= 1 }
                f &= 0x3FF
                return sign | (e << 23) | (f << 13)
            } else if exp == 31 {
                return sign | 0x7F800000 | (frac << 13) // Inf or NaN
            }
            return sign | ((exp + 112) << 23) | (frac << 13)
        }())
    }

    // MARK: - MPV Frame Capture via screenshot-raw

    private func captureMPVFrame() {
        guard !mpvCaptureInFlight, let mpv = mpvPlayer else { return }

        mpvCaptureInFlight = true
        let width = analysisWidth

        Task {
            let image = await Self.screenshotAndDownsample(mpv: mpv, targetWidth: width)
            guard isCapturing else {
                mpvCaptureInFlight = false
                return
            }
            currentFrame = image
            mpvCaptureInFlight = false
        }
    }

    private func captureMPVHDRFrame() {
        guard !mpvCaptureInFlight, let mpv = mpvPlayer else { return }

        mpvCaptureInFlight = true
        let width = analysisWidth
        let tf = transferFunction
        let peak = contentPeakNits

        Task {
            let result = await Self.screenshotAndDownsampleHDR(mpv: mpv, targetWidth: width, transferFunction: tf, peakNits: peak)
            guard isCapturing else {
                mpvCaptureInFlight = false
                return
            }
            currentHDRFrame = result?.hdrFrame
            currentFrame = result?.sdrImage
            mpvCaptureInFlight = false
        }
    }

    /// Runs off the main actor: captures raw pixels via mpv and downscales.
    nonisolated private static func screenshotAndDownsample(
        mpv: MPVPlayer, targetWidth: Int
    ) async -> CGImage? {
        let interval = performanceSignposter.beginInterval("Scope capture")
        defer { performanceSignposter.endInterval("Scope capture", interval) }

        guard let raw = mpv.screenshotRaw() else { return nil }

        // screenshot-raw returns bgr0 format: B,G,R,X in memory
        // With byteOrder32Little + noneSkipFirst this maps to XRGB in the 32-bit word
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: raw.data as CFData) else { return nil }

        guard let image = CGImage(
            width: raw.width,
            height: raw.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: raw.stride,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return downsampleCGImage(image, targetWidth: targetWidth)
    }

    private struct MPVHDRResult {
        let hdrFrame: HDRFrameData
        let sdrImage: CGImage?  // For vectorscope
    }

    /// Captures HDR frame data from MPV screenshot-raw, handling both 8-bit and 16-bit formats.
    nonisolated private static func screenshotAndDownsampleHDR(
        mpv: MPVPlayer, targetWidth: Int,
        transferFunction: TransferFunction, peakNits: Float
    ) async -> MPVHDRResult? {
        let interval = performanceSignposter.beginInterval("Scope capture")
        defer { performanceSignposter.endInterval("Scope capture", interval) }

        guard let raw = mpv.screenshotRaw() else { return nil }

        let srcW = raw.width
        let srcH = raw.height
        guard srcW > 0, srcH > 0 else { return nil }

        // One-shot diagnostic: log format and sample pixel values on first HDR capture
        if !Self.hdrFormatLogged {
            Self.hdrFormatLogged = true
            // Sample center pixel to verify value range
            let cx = srcW / 2, cy = srcH / 2
            var sampleR: Float = 0, sampleG: Float = 0, sampleB: Float = 0
            raw.data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                if raw.format.contains("64") || raw.format.contains("16") {
                    let off = cy * raw.stride + cx * 8
                    let p = base.advanced(by: off).assumingMemoryBound(to: UInt16.self)
                    sampleR = Float(p[0]) / 65535.0
                    sampleG = Float(p[1]) / 65535.0
                    sampleB = Float(p[2]) / 65535.0
                } else {
                    let off = cy * raw.stride + cx * 4
                    sampleB = Float(base.load(fromByteOffset: off, as: UInt8.self)) / 255.0
                    sampleG = Float(base.load(fromByteOffset: off + 1, as: UInt8.self)) / 255.0
                    sampleR = Float(base.load(fromByteOffset: off + 2, as: UInt8.self)) / 255.0
                }
            }
            let pqR = ScopeComputer.pqToNits(sampleR)
            let pqG = ScopeComputer.pqToNits(sampleG)
            let pqB = ScopeComputer.pqToNits(sampleB)
            Self.staticLogger.info("HDR screenshot: format=\(raw.format) \(srcW)×\(srcH) stride=\(raw.stride) peak=\(peakNits)")
            Self.staticLogger.info("  center pixel encoded: R=\(String(format: "%.4f", sampleR)) G=\(String(format: "%.4f", sampleG)) B=\(String(format: "%.4f", sampleB))")
            Self.staticLogger.info("  center pixel as PQ nits: R=\(String(format: "%.1f", pqR)) G=\(String(format: "%.1f", pqG)) B=\(String(format: "%.1f", pqB))")
        }

        let scale = srcW <= targetWidth ? 1.0 : Float(targetWidth) / Float(srcW)
        let dstW = srcW <= targetWidth ? srcW : targetWidth
        let dstH = srcW <= targetWidth ? srcH : Int(Float(srcH) * scale)
        guard dstW > 0, dstH > 0 else { return nil }

        var pixels = [Float](repeating: 0, count: dstW * dstH * 3)

        if raw.format.contains("64") || raw.format.contains("16") {
            // 16-bit format (e.g. rgba64): UInt16 values [0, 65535]
            // Layout: R16, G16, B16, A16 (8 bytes per pixel)
            let bytesPerPixel = 8

            raw.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                guard let baseAddr = ptr.baseAddress else { return }
                for dy in 0..<dstH {
                    let sy = srcW <= targetWidth ? dy : min(Int(Float(dy) / scale), srcH - 1)
                    for dx in 0..<dstW {
                        let sx = srcW <= targetWidth ? dx : min(Int(Float(dx) / scale), srcW - 1)
                        let offset = sy * raw.stride + sx * bytesPerPixel
                        let pixelPtr = baseAddr.advanced(by: offset).assumingMemoryBound(to: UInt16.self)

                        let dstOffset = (dy * dstW + dx) * 3
                        pixels[dstOffset]     = Float(pixelPtr[0]) / 65535.0
                        pixels[dstOffset + 1] = Float(pixelPtr[1]) / 65535.0
                        pixels[dstOffset + 2] = Float(pixelPtr[2]) / 65535.0
                    }
                }
            }
        } else {
            // 8-bit format (bgr0): B,G,R,X in memory (4 bytes per pixel)
            raw.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                guard let baseAddr = ptr.baseAddress else { return }
                for dy in 0..<dstH {
                    let sy = srcW <= targetWidth ? dy : min(Int(Float(dy) / scale), srcH - 1)
                    for dx in 0..<dstW {
                        let sx = srcW <= targetWidth ? dx : min(Int(Float(dx) / scale), srcW - 1)
                        let offset = sy * raw.stride + sx * 4

                        let dstOffset = (dy * dstW + dx) * 3
                        pixels[dstOffset + 2] = Float(baseAddr.load(fromByteOffset: offset, as: UInt8.self)) / 255.0     // B→B
                        pixels[dstOffset + 1] = Float(baseAddr.load(fromByteOffset: offset + 1, as: UInt8.self)) / 255.0 // G→G
                        pixels[dstOffset]     = Float(baseAddr.load(fromByteOffset: offset + 2, as: UInt8.self)) / 255.0 // R→R
                    }
                }
            }
        }

        let hdrFrame = HDRFrameData(
            pixels: pixels,
            width: dstW,
            height: dstH,
            transferFunction: transferFunction,
            isLinearLight: false,
            contentPeakNits: peakNits
        )

        // Also produce SDR CGImage for vectorscope
        let sdrImage = screenshotToSDRImage(raw: raw, targetWidth: targetWidth)

        return MPVHDRResult(hdrFrame: hdrFrame, sdrImage: sdrImage)
    }

    /// Creates an 8-bit CGImage from a raw screenshot for the vectorscope.
    nonisolated private static func screenshotToSDRImage(raw: MPVPlayer.RawScreenshot, targetWidth: Int) -> CGImage? {
        // For 16-bit formats, we need to downsample to 8-bit manually
        if raw.format.contains("64") || raw.format.contains("16") {
            let srcW = raw.width
            let srcH = raw.height
            let bytesPerPixel = 8

            var sdrPixels = [UInt8](repeating: 0, count: srcW * srcH * 4)
            raw.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                guard let baseAddr = ptr.baseAddress else { return }
                for y in 0..<srcH {
                    for x in 0..<srcW {
                        let srcOffset = y * raw.stride + x * bytesPerPixel
                        let pixelPtr = baseAddr.advanced(by: srcOffset).assumingMemoryBound(to: UInt16.self)

                        let dstOffset = (y * srcW + x) * 4
                        // BGRA byte order for CGImage
                        sdrPixels[dstOffset]     = UInt8(min(Int(pixelPtr[2]) >> 8, 255)) // B
                        sdrPixels[dstOffset + 1] = UInt8(min(Int(pixelPtr[1]) >> 8, 255)) // G
                        sdrPixels[dstOffset + 2] = UInt8(min(Int(pixelPtr[0]) >> 8, 255)) // R
                        sdrPixels[dstOffset + 3] = 255
                    }
                }
            }

            let data = Data(sdrPixels)
            guard let provider = CGDataProvider(data: data as CFData) else { return nil }
            guard let image = CGImage(
                width: srcW, height: srcH,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: srcW * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
            ) else { return nil }

            return downsampleCGImage(image, targetWidth: targetWidth)
        }

        // Standard bgr0 path
        guard let provider = CGDataProvider(data: raw.data as CFData) else { return nil }
        guard let image = CGImage(
            width: raw.width, height: raw.height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: raw.stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else { return nil }

        return downsampleCGImage(image, targetWidth: targetWidth)
    }

    // MARK: - Downscaling

    private func downsamplePixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let source = cgImage else { return nil }
        return Self.downsampleCGImage(source, targetWidth: analysisWidth)
    }

    nonisolated static func downsampleCGImage(_ source: CGImage, targetWidth: Int) -> CGImage? {
        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)

        if sourceWidth <= CGFloat(targetWidth) {
            return source
        }

        let scale = CGFloat(targetWidth) / sourceWidth
        let targetHeight = Int(sourceHeight * scale)

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
