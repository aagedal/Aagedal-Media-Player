// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import OSLog
import UniformTypeIdentifiers

/// Owns trim points and the lifecycle of screenshot and trim-export operations.
///
/// Keeping file-output state here gives it a single owner and lets
/// `PlayerController` focus on coordinating playback backends. The player
/// controller forwards this object's changes so its existing view-facing API
/// can remain stable while the architecture is split incrementally.
@MainActor
final class MediaOperationsController: ObservableObject {
    @Published private(set) var trimIn: Double?
    @Published private(set) var trimOut: Double?
    @Published private(set) var screenshotState: ScreenshotOperationState = .idle
    @Published private(set) var trimExportState: TrimExportOperationState = .idle

    private var exportHandle: SubprocessHandle?
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "MediaOperationsController")

    // MARK: - Trim Points

    func setTrimIn(at time: Double) {
        trimIn = time
        if let out = trimOut, out <= time {
            trimOut = nil
        }
    }

    func setTrimOut(at time: Double) {
        trimOut = time
        if let inn = trimIn, inn >= time {
            trimIn = nil
        }
    }

    func clearTrimIn() {
        trimIn = nil
    }

    func clearTrimOut() {
        trimOut = nil
    }

    func clearTrimPoints() {
        trimIn = nil
        trimOut = nil
    }

    // MARK: - Screenshot

    func captureScreenshot(for item: MediaItem, at time: Double) async {
        guard !screenshotState.isInFlight else { return }

        screenshotState = .idle

        let stream = item.metadata?.primaryVideoStream
        let bitDepth = stream?.bitDepth ?? 8
        let hasAlpha = stream?.hasAlpha ?? false
        let format = SettingsView.selectedScreenshotFormat

        let baseName = item.url.deletingPathExtension().lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let timeString = String(format: "%.3f", time)
        let outputName = "\(baseName)_\(timestamp)_t\(timeString).\(format.fileExtension)"

        let output: CoordinatedOutput
        let resolvedDir = SettingsView.resolvedScreenshotDirectory(sourceURL: item.url)

        if let dir = resolvedDir {
            let needsSecurityScope = dir != item.url.deletingLastPathComponent()
            if needsSecurityScope { _ = dir.startAccessingSecurityScopedResource() }
            defer { if needsSecurityScope { dir.stopAccessingSecurityScopedResource() } }
            output = OutputCoordinator.automatic(directory: dir, preferredFilename: outputName)
        } else {
            let chosenURL: URL? = await withCheckedContinuation { continuation in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = outputName
                panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension) ?? .image]
                panel.canCreateDirectories = true
                panel.directoryURL = item.url.deletingLastPathComponent()

                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }

            guard let chosenURL else { return }
            output = OutputCoordinator.userConfirmed(destinationURL: chosenURL)
        }

        defer { output.discard() }

        let arguments = ScreenshotCommandBuilder.arguments(for: ScreenshotCommandRequest(
            sourceURL: item.url,
            destinationURL: output.temporaryURL,
            time: time,
            format: format,
            bitDepth: bitDepth,
            hasAlpha: hasAlpha,
            isInterlaced: stream?.isInterlaced ?? false,
            jxlQuality: UserDefaults.standard.value(for: AppSettings.screenshotJXLQuality),
            jpegQuality: UserDefaults.standard.value(for: AppSettings.screenshotJPEGQuality),
            colorMetadata: stream
        ))

        screenshotState = .saving

        do {
            try await FFmpegService.run(arguments: arguments)
            let outputURL = try output.commit()
            logger.info("Screenshot saved: \(outputURL.lastPathComponent)")
            screenshotState = .succeeded(outputURL)
            clearScreenshotSuccess(after: .seconds(5), outputURL: outputURL)
        } catch {
            screenshotState = .failed("Screenshot failed: \(error.localizedDescription)")
            logger.error("Screenshot failed: \(error.localizedDescription)")
        }
    }

    func dismissScreenshotFeedback() {
        screenshotState = .idle
    }

    // MARK: - Trim Export

    func exportTrim(for item: MediaItem) async {
        guard !trimExportState.isInFlight else { return }

        trimExportState = .idle
        guard let inPoint = trimIn, let outPoint = trimOut, outPoint > inPoint else {
            let missing = trimIn == nil && trimOut == nil ? "Set trim in and out points first."
                : trimIn == nil ? "Set a trim in point first."
                : trimOut == nil ? "Set a trim out point first."
                : "Trim out must be after trim in."
            logger.warning("Export requires both trim in and out points")
            trimExportState = .warning(missing)
            clearTrimWarning(after: .seconds(2), message: missing)
            return
        }

        let format = SettingsView.selectedTrimExportFormat
        let duration = outPoint - inPoint
        let originalExtension = item.url.pathExtension
        let outputExtension = format.fileExtension ?? originalExtension
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let defaultName = "\(baseName)_trimmed.\(outputExtension)"

        let output: CoordinatedOutput
        let resolvedDir = SettingsView.resolvedTrimDirectory(sourceURL: item.url)

        if let dir = resolvedDir {
            let needsSecurityScope = dir != item.url.deletingLastPathComponent()
            if needsSecurityScope { _ = dir.startAccessingSecurityScopedResource() }
            defer { if needsSecurityScope { dir.stopAccessingSecurityScopedResource() } }
            output = OutputCoordinator.automatic(directory: dir, preferredFilename: defaultName)
        } else {
            let chosenURL: URL? = await withCheckedContinuation { continuation in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = defaultName
                panel.allowedContentTypes = [UTType(filenameExtension: outputExtension) ?? .movie]
                panel.canCreateDirectories = true
                panel.directoryURL = item.url.deletingLastPathComponent()

                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }

            guard let chosenURL else { return }
            output = OutputCoordinator.userConfirmed(destinationURL: chosenURL)
        }

        defer { output.discard() }

        if format == .copy {
            do {
                try TrimExportValidator.validateStreamCopy(
                    sourceURL: item.url,
                    destinationURL: output.destinationURL,
                    metadata: item.metadata
                )
            } catch {
                trimExportState = .failed("Export unavailable: \(error.localizedDescription)")
                logger.error("Trim export preflight failed: \(error.localizedDescription)")
                return
            }
        }

        let width: Int
        switch format {
        case .copy:
            width = ExportWidthPreset.original.rawValue
        case .gif:
            width = UserDefaults.standard.value(for: AppSettings.gifWidth)
        case .animatedAVIF:
            width = UserDefaults.standard.value(for: AppSettings.avifWidth)
        case .hardwareH264:
            width = UserDefaults.standard.value(for: AppSettings.h264Width)
        case .hardwareH265:
            width = UserDefaults.standard.value(for: AppSettings.h265Width)
        }

        let arguments = TrimExportCommandBuilder.arguments(for: TrimExportCommandRequest(
            sourceURL: item.url,
            destinationURL: output.temporaryURL,
            inPoint: inPoint,
            outPoint: outPoint,
            format: format,
            width: width,
            gifFrameRate: UserDefaults.standard.value(for: AppSettings.gifFrameRate),
            avifQuality: UserDefaults.standard.value(for: AppSettings.avifQuality),
            avifSpeed: UserDefaults.standard.value(for: AppSettings.avifSpeed),
            h264Quality: UserDefaults.standard.value(for: AppSettings.h264Quality),
            h265Quality: UserDefaults.standard.value(for: AppSettings.h265Quality)
        ))

        trimExportState = .preparing

        let handle = SubprocessHandle()
        exportHandle = handle

        let progressCallback: (@Sendable (Double) -> Void)?
        if format != .copy {
            progressCallback = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.trimExportState.acceptsProgress else { return }
                    self.trimExportState = .exporting(progress: fraction)
                }
            }
        } else {
            progressCallback = nil
        }

        do {
            try await FFmpegService.run(
                arguments: arguments,
                duration: format != .copy ? duration : nil,
                onProgress: progressCallback,
                handle: handle
            )
            let outputURL = try output.commit()
            exportHandle = nil
            logger.info("Trim export saved: \(outputURL.lastPathComponent)")
            trimExportState = .succeeded(outputURL)
            clearTrimSuccess(after: .seconds(5), outputURL: outputURL)
        } catch let error as FFmpegError where error == .cancelled {
            exportHandle = nil
            logger.info("Trim export cancelled")
            trimExportState = .cancelled
            clearTrimCancellation(after: .milliseconds(1_500))
        } catch {
            exportHandle = nil
            trimExportState = .failed("Export failed: \(error.localizedDescription)")
            logger.error("Trim export failed: \(error.localizedDescription)")
        }
    }

    func cancelExport() {
        guard exportHandle != nil else { return }
        trimExportState = .cancelling
        exportHandle?.cancel()
    }

    func dismissTrimExportFeedback() {
        trimExportState = .idle
    }

    // MARK: - Delayed Feedback Cleanup

    private func clearScreenshotSuccess(after delay: Duration, outputURL: URL) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard self?.screenshotState == .succeeded(outputURL) else { return }
            self?.screenshotState = .idle
        }
    }

    private func clearTrimWarning(after delay: Duration, message: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard self?.trimExportState == .warning(message) else { return }
            self?.trimExportState = .idle
        }
    }

    private func clearTrimSuccess(after delay: Duration, outputURL: URL) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard self?.trimExportState == .succeeded(outputURL) else { return }
            self?.trimExportState = .idle
        }
    }

    private func clearTrimCancellation(after delay: Duration) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard self?.trimExportState == .cancelled else { return }
            self?.trimExportState = .idle
        }
    }
}
