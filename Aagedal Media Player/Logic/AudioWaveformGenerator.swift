// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Generates per-channel audio waveform images using the bundled ffmpeg binary.
// Uses a two-pass approach: a fast low-resolution preview is rendered first,
// then replaced with the full resolution waveform.

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
    private var currentResolution: AudioWaveformResolution?

    // MARK: - Preview resolution (fast first pass)

    private static let previewPixelsPerSecond: Double = 1.5
    private static let previewChannelHeight: Int = 40
    private static let previewMaxWidth: Int = 2000

    /// Generate waveform images for every channel in the given audio stream.
    /// Renders a fast low-res preview first, then replaces it with the final resolution.
    func generate(url: URL, streamIndex: Int, channels: Int, channelLayout: String?, duration: Double) {
        let rawResolution = UserDefaults.standard.string(forKey: SettingsView.audioWaveformResolutionKey) ?? AudioWaveformResolution.standard.rawValue
        let resolution = AudioWaveformResolution(rawValue: rawResolution) ?? .standard

        // Skip if already generated for this exact stream at this resolution
        if url == currentURL, streamIndex == currentStreamIndex,
           resolution == currentResolution, !channelImages.isEmpty {
            return
        }

        cancel()
        currentURL = url
        currentStreamIndex = streamIndex
        currentResolution = resolution
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

        currentTask = Task {
            do {
                // Pass 1: fast low-res preview
                let previewImages = try await Self.generateChannelWaveforms(
                    url: url,
                    ffmpegPath: ffmpegPath,
                    streamIndex: streamIndex,
                    channelCount: channels,
                    duration: duration,
                    pixelsPerSecond: Self.previewPixelsPerSecond,
                    channelHeight: Self.previewChannelHeight,
                    maxWidth: Self.previewMaxWidth
                )
                guard !Task.isCancelled else { return }
                self.channelImages = previewImages
                self.channelLabels = labels

                // Pass 2: full resolution
                let fullImages = try await Self.generateChannelWaveforms(
                    url: url,
                    ffmpegPath: ffmpegPath,
                    streamIndex: streamIndex,
                    channelCount: channels,
                    duration: duration,
                    pixelsPerSecond: resolution.pixelsPerSecond,
                    channelHeight: resolution.channelHeight,
                    maxWidth: resolution.maxWidth
                )
                guard !Task.isCancelled else { return }
                self.channelImages = fullImages
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

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func reset() {
        cancel()
        currentURL = nil
        currentStreamIndex = nil
        currentResolution = nil
        channelImages = []
        channelLabels = []
        error = nil
        isGenerating = false
    }

    // MARK: - FFmpeg Waveform Generation

    /// Generates one waveform PNG per channel on a background thread.
    private static nonisolated func generateChannelWaveforms(
        url: URL,
        ffmpegPath: String,
        streamIndex: Int,
        channelCount: Int,
        duration: Double,
        pixelsPerSecond: Double,
        channelHeight: Int,
        maxWidth: Int
    ) async throws -> [NSImage] {

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.aagedal.MediaPlayer.waveforms.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let width = max(400, min(maxWidth, Int(duration * pixelsPerSecond)))

        var images: [NSImage] = []

        for ch in 0..<channelCount {
            try Task.checkCancellation()

            let dest = tempDir.appendingPathComponent("ch\(ch).png")
            let filterChain: String
            if channelCount == 1 {
                filterChain = "[0:a:\(streamIndex)]showwavespic=s=\(width)x\(channelHeight):colors=4A9EE5,format=rgba[out]"
            } else {
                filterChain = "[0:a:\(streamIndex)]pan=mono|c0=c\(ch),showwavespic=s=\(width)x\(channelHeight):colors=4A9EE5,format=rgba[out]"
            }

            let arguments: [String] = [
                "-hide_banner",
                "-loglevel", "error",
                "-i", url.path,
                "-filter_complex", filterChain,
                "-map", "[out]",
                "-an",
                "-frames:v", "1",
                "-f", "image2",
                "-c:v", "png",
                "-y",
                dest.path
            ]

            try await runFFmpeg(path: ffmpegPath, arguments: arguments)

            guard let image = NSImage(contentsOf: dest) else {
                throw FFmpegError.outputMissing
            }
            images.append(image)
        }

        return images
    }

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
