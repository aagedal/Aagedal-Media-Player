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
    var renderWidth: Int = 1600
}

nonisolated struct AudioWaveformGenerationOutput: @unchecked Sendable {
    let images: [NSImage]
    let amplitudes: [WaveformAmplitudeData]
    let width: Int
}

nonisolated enum AudioWaveformGenerationFailure: Error, LocalizedError {
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let detail): "Cannot generate the audio waveform: \(detail)."
        }
    }
}

typealias AudioWaveformGenerationOperation = @Sendable (
    AudioWaveformGenerationRequest
) async throws -> AudioWaveformGenerationOutput

@MainActor
final class AudioWaveformGenerator: ObservableObject {
    private struct MonoStreamIdentity: Equatable {
        let index: Int
        let label: String
    }

    private enum SourceIdentity: Equatable {
        case stream(
            url: URL,
            streamIndex: Int,
            channelCount: Int,
            channelLayout: String?,
            duration: Double
        )
        case allMonoStreams(
            url: URL,
            streams: [MonoStreamIdentity],
            duration: Double
        )
    }

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "AudioWaveform")

    /// One image per audio channel for the current stream.
    @Published var channelImages: [NSImage] = []
    @Published var channelLabels: [String] = []
    @Published var isGenerating = false
    @Published var error: String?

    private var currentTask: Task<Void, Never>?
    private var currentRenderTask: Task<Void, Never>?
    private var renderGeneration = OperationGeneration()
    private var renderWidth = 1600
    private var taskGeneration = OperationGeneration()
    private var currentSourceIdentity: SourceIdentity?
    private var currentColor: AudioWaveformColor?
    private var currentBoost: Double = 0
    private let generationOperation: AudioWaveformGenerationOperation

    /// Cached per-channel amplitude data from PCM decode, enabling fast re-renders.
    private var cachedAmplitudes: [WaveformAmplitudeData] = []

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
        guard duration.isFinite, duration >= 0 else {
            rejectInvalidRequest("the media duration is unavailable")
            return
        }
        guard streamIndex >= 0, channels > 0 else {
            rejectInvalidRequest("the selected audio stream is invalid")
            return
        }
        let rawColor = UserDefaults.standard.value(for: AppSettings.audioWaveformColor)
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink
        let boost = UserDefaults.standard.value(for: AppSettings.audioWaveformBoost)

        let sourceIdentity = SourceIdentity.stream(
            url: url,
            streamIndex: streamIndex,
            channelCount: channels,
            channelLayout: channelLayout,
            duration: duration
        )

        // Same source description — keep an in-flight decode, or re-render completed
        // amplitude data when only the appearance changed.
        if sourceIdentity == currentSourceIdentity {
            if isGenerating { return }
            if color == currentColor, boost == currentBoost, !channelImages.isEmpty {
                return
            }
            if hasCachedAmplitudes {
                rerender()
                return
            }
        }

        cancel()
        currentSourceIdentity = sourceIdentity
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
        let renderWidth = self.renderWidth

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
                    maxWidth: Self.maxWidth,
                    renderWidth: renderWidth
                ))
                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("Waveform generation: \(String(format: "%.2f", t1 - t0))s (\(channels) channels)")
                guard let self,
                      !Task.isCancelled,
                      self.taskGeneration.isCurrent(generation) else { return }
                self.cachedAmplitudes = output.amplitudes
                self.channelImages = output.images
                self.channelLabels = labels
                // Appearance may have changed while decoding. Keep that decode
                // and apply the latest preferences to its cached amplitudes.
                self.rerender(force: self.renderWidth != renderWidth)
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
        guard duration.isFinite, duration >= 0 else {
            rejectInvalidRequest("the media duration is unavailable")
            return
        }
        guard !streams.isEmpty, streams.allSatisfy({ $0.index >= 0 }) else {
            rejectInvalidRequest("the selected audio streams are invalid")
            return
        }
        let rawColor = UserDefaults.standard.value(for: AppSettings.audioWaveformColor)
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink
        let boost = UserDefaults.standard.value(for: AppSettings.audioWaveformBoost)

        let sourceIdentity = SourceIdentity.allMonoStreams(
            url: url,
            streams: streams.map { MonoStreamIdentity(index: $0.index, label: $0.label) },
            duration: duration
        )

        // Same streams — keep an in-flight decode, or re-render completed
        // amplitude data when only the appearance changed.
        if sourceIdentity == currentSourceIdentity {
            if isGenerating { return }
            if color == currentColor, boost == currentBoost, !channelImages.isEmpty {
                return
            }
            if hasCachedAmplitudes {
                rerender()
                return
            }
        }

        cancel()
        currentSourceIdentity = sourceIdentity
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
        let renderWidth = self.renderWidth

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
                        maxWidth: Self.maxWidth,
                        renderWidth: renderWidth
                    ))
                    images.append(contentsOf: output.images)
                    allAmplitudes.append(contentsOf: output.amplitudes)
                }

                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("All-streams waveform generation: \(String(format: "%.2f", t1 - t0))s (\(streams.count) streams)")
                guard let self,
                      !Task.isCancelled,
                      self.taskGeneration.isCurrent(generation) else { return }
                self.cachedAmplitudes = allAmplitudes
                self.channelImages = images
                self.channelLabels = labels
                // Appearance may have changed while decoding. Keep that decode
                // and apply the latest preferences to its cached amplitudes.
                self.rerender(force: self.renderWidth != renderWidth)
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
        renderGeneration.advance()
        if currentRenderTask != nil { currentColor = nil }
        currentRenderTask?.cancel()
        currentRenderTask = nil
        currentTask = nil
        isGenerating = false
    }

    func reset() {
        cancel()
        currentSourceIdentity = nil
        currentColor = nil
        currentBoost = 0
        cachedAmplitudes = []
        channelImages = []
        channelLabels = []
        error = nil
        isGenerating = false
    }

    private func rejectInvalidRequest(_ detail: String) {
        reset()
        error = AudioWaveformGenerationFailure.invalidRequest(detail).localizedDescription
    }

    /// Limit raster allocation to the visible width, including the display scale.
    func setRenderWidth(_ pixels: Double) {
        guard pixels.isFinite, pixels > 0 else { return }
        let width = Int(min(4096, max(1, pixels.rounded(.up))))
        guard width != renderWidth else { return }
        renderWidth = width
        rerender(force: true)
    }

    /// Apply appearance changes to cached amplitudes without restarting decoding.
    func rerender(force: Bool = false) {
        guard !cachedAmplitudes.isEmpty else { return }

        let rawColor = UserDefaults.standard.value(for: AppSettings.audioWaveformColor)
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink
        let boost = UserDefaults.standard.value(for: AppSettings.audioWaveformBoost)

        guard force || color != currentColor || boost != currentBoost else { return }

        currentColor = color
        currentBoost = boost

        let amplitudes = cachedAmplitudes
        let width = renderWidth
        let height = Self.channelHeight
        let colorHex = color.ffmpegHex
        let gamma = Self.boostToGamma(boost)
        let (cr, cg, cb) = Self.parseHexColor(colorHex)

        renderGeneration.advance()
        currentRenderTask?.cancel()
        let generation = renderGeneration.current
        let renderTask = Task.detached(priority: .userInitiated) {
            var images: [NSImage] = []
            for data in amplitudes {
                guard !Task.isCancelled else { return Optional<[NSImage]>.none }
                if let image = Self.renderWaveformImage(
                    data: data,
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

        currentRenderTask = Task { [weak self] in
            let images = await withTaskCancellationHandler {
                await renderTask.value
            } onCancel: {
                renderTask.cancel()
            }

            guard let self,
                  !Task.isCancelled,
                  self.renderGeneration.isCurrent(generation) else { return }
            self.currentRenderTask = nil
            if let images {
                self.channelImages = images
            }
        }
    }

    /// Converts a boost value (0–100) to a gamma exponent.
    /// boost 0 → gamma 1.0 (linear), boost 100 → gamma 0.1 (max boost).
    private static func boostToGamma(_ boost: Double) -> Float {
        Float(pow(0.1, (boost.isFinite ? min(100, max(0, boost)) : 0) / 100.0))
    }

    // MARK: - Native Waveform Generation

    /// Decodes audio once as raw PCM via ffmpeg, then renders all channel waveforms natively.
    /// Returns images, cached amplitude data, and the computed width.
    static nonisolated func generateNativeWaveforms(
        request: AudioWaveformGenerationRequest
    ) async throws -> AudioWaveformGenerationOutput {
        guard request.duration.isFinite, request.duration >= 0,
              request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0,
              request.streamIndex >= 0, request.channelCount > 0,
              request.channelHeight > 0, request.maxWidth > 0 else {
            throw AudioWaveformGenerationFailure.invalidRequest("its source parameters are invalid")
        }
        let requestedWidth = min(
            Double(request.maxWidth), request.duration * request.pixelsPerSecond
        )
        let width = min(request.maxWidth, max(400, Int(requestedWidth)))

        // Downsample to reduce data: aim for ~100 samples per output pixel column.
        // Streaming means even very long recordings retain only the fixed-size
        // column accumulators. This reduced-rate navigation preview is not a
        // sample-peak or true-peak measurement; audio meters provide those.
        let idealRate = max(100, min(48000, Int(ceil(Double(width) * 100.0 / max(request.duration, 0.1)))))
        guard let expectedFrames = Int(exactly: ceil(request.duration * Double(idealRate))) else {
            throw AudioWaveformGenerationFailure.invalidRequest("the media duration is too large")
        }
        let accumulator = StreamingWaveformAccumulator(
            width: width,
            channelCount: request.channelCount,
            expectedFrameCount: max(1, expectedFrames)
        )

        let arguments: [String] = [
            "-hide_banner", "-loglevel", "error",
        ] + (try RIFXAudioDecoding.ffmpegInputArguments(for: request.url)) + [
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
                data: amplitude,
                width: min(4096, max(1, request.renderWidth)), height: request.channelHeight,
                r: cr, g: cg, b: cb,
                gamma: request.gamma
            ) {
                images.append(image)
            }
        }

        return AudioWaveformGenerationOutput(images: images, amplitudes: amplitudes, width: width)
    }

    // MARK: - Image Rendering

    /// Render at the display's pixel width. The translucent peak envelope keeps
    /// short transients visible; the opaque signed-mean body shows sustained audio.
    /// Silence stays transparent so the view can draw a consistent zero line.
    static nonisolated func renderWaveformImage(
        data: WaveformAmplitudeData,
        width: Int, height: Int,
        r: UInt8, g: UInt8, b: UInt8,
        gamma: Float = 1.0
    ) -> NSImage? {
        guard (1...4096).contains(width), (1...1024).contains(height),
              !data.mins.isEmpty, data.mins.count == data.maxs.count else { return nil }
        let amplitude = data.resampled(to: width)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let centerY = Float(height) / 2
        let exponent = gamma.isFinite ? min(1, max(0.1, gamma)) : 1

        func draw(column: Int, low: Float, high: Float, opacity: Float) {
            guard low < 0 || high > 0 else { return }
            let top = centerY - powf(high, exponent) * centerY
            let bottom = centerY + powf(-low, exponent) * centerY
            let first = max(0, min(height - 1, Int(floor(top))))
            let last = max(first, min(height - 1, Int(ceil(bottom)) - 1))
            for row in first...last {
                // Fractional coverage keeps quiet passages smooth on Retina displays.
                let coverage = max(0, min(Float(row + 1), bottom) - max(Float(row), top))
                let alpha = opacity * coverage
                let index = (row * width + column) * 4
                // Both layers use the same color: replace with the denser coverage.
                if alpha * 255 > Float(pixels[index + 3]) {
                    pixels[index] = UInt8(Float(r) * alpha)
                    pixels[index + 1] = UInt8(Float(g) * alpha)
                    pixels[index + 2] = UInt8(Float(b) * alpha)
                    pixels[index + 3] = UInt8(255 * alpha)
                }
            }
        }

        let hasAverages = amplitude.averageMins.count == width && amplitude.averageMaxs.count == width
        for column in 0..<width {
            draw(column: column, low: amplitude.mins[column], high: amplitude.maxs[column],
                 opacity: hasAverages ? 0.55 : 1)
            if hasAverages {
                draw(column: column, low: amplitude.averageMins[column], high: amplitude.averageMaxs[column],
                     opacity: 1)
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
