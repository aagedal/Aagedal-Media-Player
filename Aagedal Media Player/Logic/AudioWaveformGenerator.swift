// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Generates per-channel audio waveform images using the bundled ffmpeg binary.
// Decodes audio once as raw PCM, then renders waveforms natively in Swift.

import Foundation
import AppKit
import Combine
import OSLog

nonisolated struct AudioWaveformGenerationRequest: Sendable {
    let url: URL
    let streamIndex: Int
    let channelCount: Int
    let duration: Double
    let colorHex: String
    let gamma: Float
    let pixelsPerSecond: Double
    let channelHeight: Int
    let maxWidth: Int
}

nonisolated struct AudioWaveformGenerationOutput: @unchecked Sendable {
    let images: [NSImage]
    let amplitudes: [WaveformAmplitudeData]
    let width: Int
}

typealias AudioWaveformGenerationOperation = @Sendable (
    AudioWaveformGenerationRequest
) async throws -> AudioWaveformGenerationOutput

@MainActor
final class AudioWaveformGenerator: ObservableObject {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "AudioWaveform")

    /// One image per audio channel for the current stream.
    @Published var channelImages: [NSImage] = []
    @Published var channelLabels: [String] = []
    @Published var isGenerating = false
    @Published var error: String?

    private var currentTask: Task<Void, Never>?
    private var taskGeneration = OperationGeneration()
    private var currentURL: URL?
    private var currentStreamIndex: Int?
    private var currentAllStreams: Bool = false
    private var currentColor: AudioWaveformColor?
    private var currentBoost: Double = 0
    private let generationOperation: AudioWaveformGenerationOperation

    /// Cached per-channel amplitude data from PCM decode, enabling fast re-renders.
    private var cachedAmplitudes: [WaveformAmplitudeData] = []
    private var cachedWidth: Int = 0

    var hasCachedAmplitudes: Bool { !cachedAmplitudes.isEmpty }

    // Waveform rendering parameters
    private static let pixelsPerSecond: Double = 12
    private static let channelHeight: Int = 240
    private static let maxWidth: Int = 24000

    init(generationOperation: AudioWaveformGenerationOperation? = nil) {
        self.generationOperation = generationOperation ?? { request in
            try await AudioWaveformGenerator.generateNativeWaveforms(request: request)
        }
    }

    /// Generate waveform images for every channel in the given audio stream.
    /// Decodes audio once as raw PCM, then renders all channels natively.
    func generate(url: URL, streamIndex: Int, channels: Int, channelLayout: String?, duration: Double) {
        let rawColor = UserDefaults.standard.value(for: AppSettings.audioWaveformColor)
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink
        let boost = UserDefaults.standard.value(for: AppSettings.audioWaveformBoost)

        // Same stream — keep an in-flight decode, or re-render completed
        // amplitude data when only the appearance changed.
        if url == currentURL, streamIndex == currentStreamIndex, !currentAllStreams {
            if color == currentColor, boost == currentBoost,
               isGenerating || !channelImages.isEmpty {
                return
            }
            if hasCachedAmplitudes {
                rerender()
                return
            }
        }

        cancel()
        currentURL = url
        currentStreamIndex = streamIndex
        currentAllStreams = false
        currentColor = color
        currentBoost = boost
        channelImages = []
        channelLabels = []
        cachedAmplitudes = []
        error = nil
        isGenerating = true

        let labels = AudioChannelLabels.names(count: channels, layout: channelLayout)

        let colorHex = color.ffmpegHex
        let gamma = Self.boostToGamma(boost)
        let logger = self.logger
        let generation = taskGeneration.current
        let generationOperation = self.generationOperation

        currentTask = Task { [weak self] in
            defer {
                if let self, self.taskGeneration.isCurrent(generation) {
                    self.isGenerating = false
                    self.currentTask = nil
                }
            }

            do {
                let t0 = CFAbsoluteTimeGetCurrent()
                let output = try await generationOperation(AudioWaveformGenerationRequest(
                    url: url,
                    streamIndex: streamIndex,
                    channelCount: channels,
                    duration: duration,
                    colorHex: colorHex,
                    gamma: gamma,
                    pixelsPerSecond: Self.pixelsPerSecond,
                    channelHeight: Self.channelHeight,
                    maxWidth: Self.maxWidth
                ))
                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("Waveform generation: \(String(format: "%.2f", t1 - t0))s (\(channels) channels)")
                guard let self,
                      !Task.isCancelled,
                      self.taskGeneration.isCurrent(generation) else { return }
                self.cachedAmplitudes = output.amplitudes
                self.cachedWidth = output.width
                self.channelImages = output.images
                self.channelLabels = labels
            } catch is CancellationError {
                // Cancelled — no action needed
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.taskGeneration.isCurrent(generation) else { return }
                self.error = error.localizedDescription
                self.logger.error("Waveform generation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Generate waveform images for all mono audio streams, one per stream.
    func generateAllMonoStreams(url: URL, streams: [(index: Int, label: String)], duration: Double) {
        let rawColor = UserDefaults.standard.value(for: AppSettings.audioWaveformColor)
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink
        let boost = UserDefaults.standard.value(for: AppSettings.audioWaveformBoost)

        // Same streams — keep an in-flight decode, or re-render completed
        // amplitude data when only the appearance changed.
        if url == currentURL, currentAllStreams {
            if color == currentColor, boost == currentBoost,
               isGenerating || !channelImages.isEmpty {
                return
            }
            if hasCachedAmplitudes {
                rerender()
                return
            }
        }

        cancel()
        currentURL = url
        currentStreamIndex = nil
        currentAllStreams = true
        currentColor = color
        currentBoost = boost
        channelImages = []
        channelLabels = []
        cachedAmplitudes = []
        error = nil
        isGenerating = true

        let colorHex = color.ffmpegHex
        let gamma = Self.boostToGamma(boost)
        let logger = self.logger
        let labels = streams.map { $0.label }
        let generation = taskGeneration.current
        let generationOperation = self.generationOperation

        currentTask = Task { [weak self] in
            defer {
                if let self, self.taskGeneration.isCurrent(generation) {
                    self.isGenerating = false
                    self.currentTask = nil
                }
            }

            do {
                let t0 = CFAbsoluteTimeGetCurrent()
                var images: [NSImage] = []
                var allAmplitudes: [WaveformAmplitudeData] = []
                var cachedW = 0

                for stream in streams {
                    try Task.checkCancellation()
                    let output = try await generationOperation(AudioWaveformGenerationRequest(
                        url: url,
                        streamIndex: stream.index,
                        channelCount: 1,
                        duration: duration,
                        colorHex: colorHex,
                        gamma: gamma,
                        pixelsPerSecond: Self.pixelsPerSecond,
                        channelHeight: Self.channelHeight,
                        maxWidth: Self.maxWidth
                    ))
                    images.append(contentsOf: output.images)
                    allAmplitudes.append(contentsOf: output.amplitudes)
                    cachedW = output.width
                }

                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("All-streams waveform generation: \(String(format: "%.2f", t1 - t0))s (\(streams.count) streams)")
                guard let self,
                      !Task.isCancelled,
                      self.taskGeneration.isCurrent(generation) else { return }
                self.cachedAmplitudes = allAmplitudes
                self.cachedWidth = cachedW
                self.channelImages = images
                self.channelLabels = labels
            } catch is CancellationError {
                // Cancelled
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.taskGeneration.isCurrent(generation) else { return }
                self.error = error.localizedDescription
                self.logger.error("All-streams waveform generation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancel() {
        taskGeneration.advance()
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
    }

    func reset() {
        cancel()
        currentURL = nil
        currentStreamIndex = nil
        currentAllStreams = false
        currentColor = nil
        currentBoost = 0
        cachedAmplitudes = []
        cachedWidth = 0
        channelImages = []
        channelLabels = []
        error = nil
        isGenerating = false
    }

    /// Re-renders waveform images from cached amplitude data with current color and boost.
    /// Skips FFmpeg decode entirely — only runs the fast pixel rendering.
    func rerender() {
        guard !cachedAmplitudes.isEmpty else { return }

        let rawColor = UserDefaults.standard.value(for: AppSettings.audioWaveformColor)
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink
        let boost = UserDefaults.standard.value(for: AppSettings.audioWaveformBoost)

        guard color != currentColor || boost != currentBoost else { return }

        currentColor = color
        currentBoost = boost

        let amplitudes = cachedAmplitudes
        let width = cachedWidth
        let height = Self.channelHeight
        let colorHex = color.ffmpegHex
        let gamma = Self.boostToGamma(boost)
        let (cr, cg, cb) = Self.parseHexColor(colorHex)

        cancel()
        let generation = taskGeneration.current
        let renderTask = Task.detached(priority: .userInitiated) {
            var images: [NSImage] = []
            for data in amplitudes {
                guard !Task.isCancelled else { return Optional<[NSImage]>.none }
                if let image = Self.renderWaveformImage(
                    mins: data.mins, maxs: data.maxs,
                    width: width, height: height,
                    r: cr, g: cg, b: cb,
                    gamma: gamma
                ) {
                    images.append(image)
                }
            }
            guard !Task.isCancelled else { return Optional<[NSImage]>.none }
            return images
        }

        currentTask = Task { [weak self] in
            let images = await withTaskCancellationHandler {
                await renderTask.value
            } onCancel: {
                renderTask.cancel()
            }

            guard let self,
                  !Task.isCancelled,
                  self.taskGeneration.isCurrent(generation) else { return }
            self.currentTask = nil
            if let images {
                self.channelImages = images
            }
        }
    }

    /// Converts a boost value (0–100) to a gamma exponent.
    /// boost 0 → gamma 1.0 (linear), boost 100 → gamma 0.1 (max boost).
    private static func boostToGamma(_ boost: Double) -> Float {
        Float(pow(0.1, boost / 100.0))
    }

    // MARK: - Native Waveform Generation

    /// Decodes audio once as raw PCM via ffmpeg, then renders all channel waveforms natively.
    /// Returns images, cached amplitude data, and the computed width.
    private static nonisolated func generateNativeWaveforms(
        request: AudioWaveformGenerationRequest
    ) async throws -> AudioWaveformGenerationOutput {
        let width = max(400, min(request.maxWidth, Int(request.duration * request.pixelsPerSecond)))

        // Downsample to reduce data: aim for ~100 samples per output pixel column.
        // Streaming means even very long recordings retain only the fixed-size
        // column accumulators. A 100 Hz floor preserves short transients without
        // producing multi-gigabyte intermediate streams for day-long media.
        let idealRate = max(100, min(48000, Int(ceil(Double(width) * 100.0 / max(request.duration, 0.1)))))
        let accumulator = StreamingWaveformAccumulator(
            width: width,
            channelCount: request.channelCount,
            expectedFrameCount: max(1, Int(ceil(request.duration * Double(idealRate))))
        )

        let arguments: [String] = [
            "-hide_banner", "-loglevel", "error",
            "-i", request.url.path,
            "-vn",
            "-map", "0:a:\(request.streamIndex)",
            "-ar", "\(idealRate)",
            "-f", "f32le",
            "-c:a", "pcm_f32le",
            "pipe:1"
        ]

        try await FFmpegService.runStreamingOutput(arguments: arguments) { data in
            accumulator.consume(data)
        }
        try Task.checkCancellation()

        let amplitudes = try accumulator.finish()

        // Parse waveform color
        let (cr, cg, cb) = parseHexColor(request.colorHex)

        var images: [NSImage] = []
        for amplitude in amplitudes {
            try Task.checkCancellation()
            if let image = renderWaveformImage(
                mins: amplitude.mins, maxs: amplitude.maxs,
                width: width, height: request.channelHeight,
                r: cr, g: cg, b: cb,
                gamma: request.gamma
            ) {
                images.append(image)
            }
        }

        return AudioWaveformGenerationOutput(images: images, amplitudes: amplitudes, width: width)
    }

    // MARK: - Image Rendering

    /// Renders a single-channel waveform image from min/max amplitude data.
    /// When gamma < 1, quiet values are boosted while peaks (1.0) stay fixed.
    private static nonisolated func renderWaveformImage(
        mins: [Float], maxs: [Float],
        width: Int, height: Int,
        r: UInt8, g: UInt8, b: UInt8,
        gamma: Float = 1.0
    ) -> NSImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let centerY = Float(height) / 2.0
        let applyGamma = gamma != 1.0

        for col in 0..<width {
            // Map amplitude [-1, 1] to pixel rows.
            // Row 0 = top of image, row height-1 = bottom.
            // amplitude 1.0 → row 0 (top), -1.0 → row height-1 (bottom)
            var maxVal = maxs[col]
            var minVal = mins[col]
            if applyGamma {
                maxVal = powf(maxVal, gamma)         // maxs >= 0
                minVal = -powf(-minVal, gamma)       // mins <= 0
            }
            let topRow = max(0, Int(centerY - maxVal * centerY))
            let bottomRow = min(height - 1, Int(centerY - minVal * centerY))

            for row in topRow...bottomRow {
                let idx = (row * width + col) * 4
                pixels[idx] = r
                pixels[idx + 1] = g
                pixels[idx + 2] = b
                pixels[idx + 3] = 255
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Parses a hex color string (RRGGBB) into RGB byte components.
    private static nonisolated func parseHexColor(_ hex: String) -> (UInt8, UInt8, UInt8) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            return (255, 45, 120) // default pink
        }
        return (
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        )
    }

}
