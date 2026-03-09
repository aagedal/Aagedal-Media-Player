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

    /// The latest captured frame, downscaled for scope computation.
    @Published var currentFrame: CGImage?

    // AVPlayer capture
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var player: AVPlayer?

    /// Called after the video output is removed so the host can rebuild the decode pipeline.
    var onAVOutputRemoved: (() -> Void)?

    // MPV capture via screenshot-raw
    private weak var mpvPlayer: MPVPlayer?
    private var mpvCaptureInFlight = false

    // Shared timer
    private var captureTimer: Timer?
    private(set) var isCapturing = false

    /// Target downscale width for scope analysis, read from settings.
    private var analysisWidth: Int {
        let raw = UserDefaults.standard.integer(forKey: "scopeResolution")
        return raw > 0 ? raw : 720
    }

    // MARK: - AVPlayer Setup

    func attachAVPlayer(_ player: AVPlayer) {
        self.player = player
    }

    func detachAVPlayer() {
        if let output = videoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        videoOutput = nil
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
        if videoOutput == nil, let item = player?.currentItem {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            item.add(output)
            videoOutput = output
            logger.info("Lazily attached AVPlayerItemVideoOutput for scope capture")
        }

        let fps = UserDefaults.standard.double(forKey: "scopeFrameRate")
        let interval = 1.0 / (fps > 0 ? fps : 15.0)
        captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame()
            }
        }

        logger.info("Scope frame capture started")
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false

        captureTimer?.invalidate()
        captureTimer = nil
        currentFrame = nil

        // Remove video output so it doesn't interfere with playback pipeline
        let hadOutput = videoOutput != nil
        if let output = videoOutput, let item = player?.currentItem {
            item.remove(output)
        }
        videoOutput = nil

        // Force AVFoundation to rebuild its decode pipeline (ProRes RAW
        // tone-maps highlights when an output is attached and the pipeline
        // doesn't revert on its own after removing the output).
        if hadOutput {
            onAVOutputRemoved?()
        }

        logger.info("Scope frame capture stopped")
    }

    // MARK: - Frame Capture

    private func captureFrame() {
        if let output = videoOutput, let player {
            captureAVPlayerFrame(output: output, player: player)
        } else if mpvPlayer != nil {
            captureMPVFrame()
        }
    }

    private func captureAVPlayerFrame(output: AVPlayerItemVideoOutput, player: AVPlayer) {
        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return }
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

        currentFrame = downsamplePixelBuffer(pixelBuffer)
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

    /// Runs off the main actor: captures raw pixels via mpv and downscales.
    nonisolated private static func screenshotAndDownsample(
        mpv: MPVPlayer, targetWidth: Int
    ) async -> CGImage? {
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
