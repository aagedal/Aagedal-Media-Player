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

@MainActor
final class AudioWaveformGenerator: ObservableObject {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "AudioWaveform")

    /// One image per audio channel for the current stream.
    @Published var channelImages: [NSImage] = []
    @Published var channelLabels: [String] = []
    @Published var isGenerating = false
    @Published var error: String?

    private var currentTask: Task<Void, Never>?
    private var currentURL: URL?
    private var currentStreamIndex: Int?
    private var currentAllStreams: Bool = false
    private var currentColor: AudioWaveformColor?

    // Waveform rendering parameters
    private static let pixelsPerSecond: Double = 12
    private static let channelHeight: Int = 240
    private static let maxWidth: Int = 24000

    /// Generate waveform images for every channel in the given audio stream.
    /// Decodes audio once as raw PCM, then renders all channels natively.
    func generate(url: URL, streamIndex: Int, channels: Int, channelLayout: String?, duration: Double) {
        let rawColor = UserDefaults.standard.string(forKey: SettingsView.audioWaveformColorKey) ?? AudioWaveformColor.pink.rawValue
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink

        // Skip if already generated for this exact stream and color
        if url == currentURL, streamIndex == currentStreamIndex,
           !currentAllStreams, color == currentColor, !channelImages.isEmpty {
            return
        }

        cancel()
        currentURL = url
        currentStreamIndex = streamIndex
        currentAllStreams = false
        currentColor = color
        channelImages = []
        channelLabels = []
        error = nil
        isGenerating = true

        let labels = Self.channelNames(count: channels, layout: channelLayout)

        guard let ffmpegPath = FFmpegService.ffmpegPath else {
            error = FFmpegError.ffmpegMissing.localizedDescription
            isGenerating = false
            return
        }

        let colorHex = color.ffmpegHex
        let logger = self.logger

        currentTask = Task {
            do {
                let t0 = CFAbsoluteTimeGetCurrent()
                let images = try await Self.generateNativeWaveforms(
                    url: url,
                    ffmpegPath: ffmpegPath,
                    streamIndex: streamIndex,
                    channelCount: channels,
                    duration: duration,
                    colorHex: colorHex,
                    pixelsPerSecond: Self.pixelsPerSecond,
                    channelHeight: Self.channelHeight,
                    maxWidth: Self.maxWidth
                )
                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("Waveform generation: \(String(format: "%.2f", t1 - t0))s (\(channels) channels)")
                guard !Task.isCancelled else { return }
                self.channelImages = images
                self.channelLabels = labels
            } catch is CancellationError {
                // Cancelled — no action needed
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.logger.error("Waveform generation failed: \(error.localizedDescription, privacy: .public)")
            }
            self.isGenerating = false
        }
    }

    /// Generate waveform images for all mono audio streams, one per stream.
    func generateAllMonoStreams(url: URL, streams: [(index: Int, label: String)], duration: Double) {
        let rawColor = UserDefaults.standard.string(forKey: SettingsView.audioWaveformColorKey) ?? AudioWaveformColor.pink.rawValue
        let color = AudioWaveformColor(rawValue: rawColor) ?? .pink

        if url == currentURL, currentAllStreams, color == currentColor, !channelImages.isEmpty {
            return
        }

        cancel()
        currentURL = url
        currentStreamIndex = nil
        currentAllStreams = true
        currentColor = color
        channelImages = []
        channelLabels = []
        error = nil
        isGenerating = true

        guard let ffmpegPath = FFmpegService.ffmpegPath else {
            error = FFmpegError.ffmpegMissing.localizedDescription
            isGenerating = false
            return
        }

        let colorHex = color.ffmpegHex
        let logger = self.logger
        let labels = streams.map { $0.label }

        currentTask = Task {
            do {
                let t0 = CFAbsoluteTimeGetCurrent()
                var images: [NSImage] = []

                for stream in streams {
                    try Task.checkCancellation()
                    let streamImages = try await Self.generateNativeWaveforms(
                        url: url,
                        ffmpegPath: ffmpegPath,
                        streamIndex: stream.index,
                        channelCount: 1,
                        duration: duration,
                        colorHex: colorHex,
                        pixelsPerSecond: Self.pixelsPerSecond,
                        channelHeight: Self.channelHeight,
                        maxWidth: Self.maxWidth
                    )
                    images.append(contentsOf: streamImages)
                }

                let t1 = CFAbsoluteTimeGetCurrent()
                logger.info("All-streams waveform generation: \(String(format: "%.2f", t1 - t0))s (\(streams.count) streams)")
                guard !Task.isCancelled else { return }
                self.channelImages = images
                self.channelLabels = labels
            } catch is CancellationError {
                // Cancelled
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.logger.error("All-streams waveform generation failed: \(error.localizedDescription, privacy: .public)")
            }
            self.isGenerating = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func reset() {
        cancel()
        currentURL = nil
        currentStreamIndex = nil
        currentAllStreams = false
        currentColor = nil
        channelImages = []
        channelLabels = []
        error = nil
        isGenerating = false
    }

    // MARK: - Native Waveform Generation

    /// Decodes audio once as raw PCM via ffmpeg, then renders all channel waveforms natively.
    private static nonisolated func generateNativeWaveforms(
        url: URL,
        ffmpegPath: String,
        streamIndex: Int,
        channelCount: Int,
        duration: Double,
        colorHex: String,
        pixelsPerSecond: Double,
        channelHeight: Int,
        maxWidth: Int
    ) async throws -> [NSImage] {
        let width = max(400, min(maxWidth, Int(duration * pixelsPerSecond)))

        // Downsample to reduce data: aim for ~100 samples per output pixel column.
        // This is plenty for visual waveform accuracy while keeping data manageable
        // (e.g. a 1-hour 5.1 file at 1kHz ≈ 86 MB vs 4+ GB at full rate).
        let idealRate = max(1000, min(48000, Int(ceil(Double(width) * 100.0 / max(duration, 0.1)))))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.aagedal.MediaPlayer.waveforms.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pcmFile = tempDir.appendingPathComponent("audio.raw")

        let arguments: [String] = [
            "-hide_banner", "-loglevel", "error",
            "-i", url.path,
            "-vn",
            "-map", "0:a:\(streamIndex)",
            "-ar", "\(idealRate)",
            "-f", "f32le",
            "-c:a", "pcm_f32le",
            "-y", pcmFile.path
        ]

        try await runFFmpeg(path: ffmpegPath, arguments: arguments)
        try Task.checkCancellation()

        let pcmData = try Data(contentsOf: pcmFile)
        let floatCount = pcmData.count / MemoryLayout<Float>.size
        let totalFrames = floatCount / channelCount
        guard totalFrames > 0 else { throw FFmpegError.outputMissing }

        // Parse waveform color
        let (cr, cg, cb) = parseHexColor(colorHex)

        var images: [NSImage] = []

        for ch in 0..<channelCount {
            try Task.checkCancellation()

            // Compute average positive/negative amplitude per pixel column.
            // This matches ffmpeg showwavespic's default "average" mode,
            // which shows the mean envelope rather than absolute peaks.
            var columnMins = [Float](repeating: 0, count: width)
            var columnMaxs = [Float](repeating: 0, count: width)

            pcmData.withUnsafeBytes { rawBuffer in
                let floats = rawBuffer.bindMemory(to: Float.self)

                for col in 0..<width {
                    let startFrame = col * totalFrames / width
                    let endFrame = min((col + 1) * totalFrames / width, totalFrames)
                    guard startFrame < endFrame else { return }

                    var posSum: Float = 0
                    var posCount: Int = 0
                    var negSum: Float = 0
                    var negCount: Int = 0

                    for frame in startFrame..<endFrame {
                        let sample = floats[frame * channelCount + ch]
                        if sample >= 0 {
                            posSum += sample
                            posCount += 1
                        } else {
                            negSum += sample
                            negCount += 1
                        }
                    }

                    columnMaxs[col] = min(posCount > 0 ? posSum / Float(posCount) : 0, 1.0)
                    columnMins[col] = max(negCount > 0 ? negSum / Float(negCount) : 0, -1.0)
                }
            }

            if let image = renderWaveformImage(
                mins: columnMins, maxs: columnMaxs,
                width: width, height: channelHeight,
                r: cr, g: cg, b: cb
            ) {
                images.append(image)
            }
        }

        return images
    }

    // MARK: - Image Rendering

    /// Renders a single-channel waveform image from min/max amplitude data.
    private static nonisolated func renderWaveformImage(
        mins: [Float], maxs: [Float],
        width: Int, height: Int,
        r: UInt8, g: UInt8, b: UInt8
    ) -> NSImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let centerY = Float(height) / 2.0

        for col in 0..<width {
            // Map amplitude [-1, 1] to pixel rows.
            // Row 0 = top of image, row height-1 = bottom.
            // amplitude 1.0 → row 0 (top), -1.0 → row height-1 (bottom)
            let topRow = max(0, Int(centerY - maxs[col] * centerY))
            let bottomRow = min(height - 1, Int(centerY - mins[col] * centerY))

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

    // MARK: - FFmpeg Process

    private static nonisolated func runFFmpeg(path: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let stderrPipe = Pipe()
            process.standardOutput = Pipe()
            process.standardError = stderrPipe

            // Use terminationHandler instead of waitUntilExit() to avoid
            // blocking the Swift cooperative thread pool, which can starve
            // the main actor when generating many channels sequentially.
            process.terminationHandler = { terminatedProcess in
                if terminatedProcess.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else if terminatedProcess.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: CancellationError())
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: stderrData, encoding: .utf8) ?? "Unknown ffmpeg error"
                    continuation.resume(throwing: FFmpegError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Channel Labels

    private static func channelNames(count: Int, layout: String?) -> [String] {
        if let layout, !layout.isEmpty {
            let knownLayouts: [String: [String]] = [
                "mono": ["Mono"],
                "stereo": ["Left", "Right"],
                "2.1": ["Left", "Right", "LFE"],
                "3.0": ["Left", "Right", "Center"],
                "3.0(back)": ["Left", "Right", "Back Center"],
                "3.1": ["Left", "Right", "Center", "LFE"],
                "4.0": ["Left", "Right", "Center", "Back Center"],
                "quad": ["Left", "Right", "Back Left", "Back Right"],
                "quad(side)": ["Left", "Right", "Side Left", "Side Right"],
                "5.0": ["Left", "Right", "Center", "Back Left", "Back Right"],
                "5.0(side)": ["Left", "Right", "Center", "Side Left", "Side Right"],
                "5.1": ["Left", "Right", "Center", "LFE", "Back Left", "Back Right"],
                "5.1(side)": ["Left", "Right", "Center", "LFE", "Side Left", "Side Right"],
                "6.1": ["Left", "Right", "Center", "LFE", "Back Center", "Side Left", "Side Right"],
                "7.1": ["Left", "Right", "Center", "LFE", "Back Left", "Back Right", "Side Left", "Side Right"],
                "7.1(wide)": ["Left", "Right", "Center", "LFE", "Back Left", "Back Right", "Front Left of Center", "Front Right of Center"],
            ]
            let normalized = layout.lowercased()
            if let names = knownLayouts[normalized], names.count == count {
                return names
            }
        }

        if count == 1 { return ["Mono"] }
        if count == 2 { return ["Left", "Right"] }
        return (0..<count).map { "Channel \($0 + 1)" }
    }
}
