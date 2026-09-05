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

    private let taskOwner = MediaOperationTaskOwner()
    private let screenshotFeedbackDismissal = DeferredMainActorTask()
    private let trimExportFeedbackDismissal = DeferredMainActorTask()
    private let feedbackDelays: MediaOperationFeedbackDelays
    private var screenshotSavePanel: NSSavePanel?
    private var trimExportSavePanel: NSSavePanel?
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "MediaOperationsController")

    init(feedbackDelays: MediaOperationFeedbackDelays = .standard) {
        self.feedbackDelays = feedbackDelays
    }

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

    func captureScreenshot(for item: MediaItem, at time: Double) {
        guard !screenshotState.isInFlight else { return }
        screenshotFeedbackDismissal.cancel()

        taskOwner.start(.screenshot) { [weak self] token, subprocessHandle in
            await self?.performScreenshot(
                for: item,
                at: time,
                token: token,
                subprocessHandle: subprocessHandle
            )
        }
    }

    func captureComparisonStill(
        primaryItem: MediaItem,
        secondaryItem: MediaItem,
        primaryTime: TimeInterval,
        secondaryTime: TimeInterval,
        alignmentMode: CompareAlignmentMode,
        inspectionView: CompareViewMode
    ) {
        guard !screenshotState.isInFlight else { return }
        screenshotFeedbackDismissal.cancel()

        let clampedPrimaryTime = ComparisonStillFrameExtractor.clampedTime(
            primaryTime,
            for: primaryItem
        )
        let clampedSecondaryTime = ComparisonStillFrameExtractor.clampedTime(
            secondaryTime,
            for: secondaryItem
        )

        // Freeze all user-visible values before asynchronous frame extraction
        // begins. Playback may continue while the still is being prepared.
        let details = ComparisonStillDetails(
            primary: ComparisonStillSourceDetails(item: primaryItem, time: clampedPrimaryTime),
            secondary: ComparisonStillSourceDetails(item: secondaryItem, time: clampedSecondaryTime),
            alignmentLabel: alignmentMode.label,
            inspectionView: inspectionView
        )

        taskOwner.start(.screenshot) { [weak self] token, _ in
            await self?.performComparisonStill(
                primaryItem: primaryItem,
                secondaryItem: secondaryItem,
                primaryTime: clampedPrimaryTime,
                secondaryTime: clampedSecondaryTime,
                details: details,
                token: token
            )
        }
    }

    private func performComparisonStill(
        primaryItem: MediaItem,
        secondaryItem: MediaItem,
        primaryTime: TimeInterval,
        secondaryTime: TimeInterval,
        details: ComparisonStillDetails,
        token: MediaOperationTaskOwner.Token
    ) async {
        guard taskOwner.isCurrent(.screenshot, token: token) else { return }

        screenshotState = .idle
        let primaryBaseName = primaryItem.url.deletingPathExtension().lastPathComponent
        let secondaryBaseName = secondaryItem.url.deletingPathExtension().lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let outputName = "\(primaryBaseName)_vs_\(secondaryBaseName)_\(timestamp).png"

        let output: CoordinatedOutput
        let resolvedDir = SettingsView.resolvedScreenshotDirectory(sourceURL: primaryItem.url)

        if let dir = resolvedDir {
            let needsSecurityScope = dir != primaryItem.url.deletingLastPathComponent()
            if needsSecurityScope { _ = dir.startAccessingSecurityScopedResource() }
            defer { if needsSecurityScope { dir.stopAccessingSecurityScopedResource() } }
            output = OutputCoordinator.automatic(directory: dir, preferredFilename: outputName)
        } else {
            let chosenURL: URL? = await withCheckedContinuation { continuation in
                let panel = NSSavePanel()
                screenshotSavePanel = panel
                panel.nameFieldStringValue = outputName
                panel.allowedContentTypes = [.png]
                panel.canCreateDirectories = true
                panel.directoryURL = primaryItem.url.deletingLastPathComponent()

                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
            screenshotSavePanel = nil

            guard taskOwner.isCurrent(.screenshot, token: token),
                  !Task.isCancelled,
                  let chosenURL else { return }
            output = OutputCoordinator.userConfirmed(destinationURL: chosenURL)
        }

        defer { output.discard() }
        screenshotState = .saving

        do {
            let primaryImage = try await ComparisonStillFrameExtractor.image(
                from: primaryItem.url,
                at: primaryTime
            )
            try Task.checkCancellation()
            guard taskOwner.isCurrent(.screenshot, token: token) else { return }

            let secondaryImage = try await ComparisonStillFrameExtractor.image(
                from: secondaryItem.url,
                at: secondaryTime
            )
            try Task.checkCancellation()
            guard taskOwner.isCurrent(.screenshot, token: token) else { return }

            let rendered = try ComparisonStillRenderer.render(
                primaryImage: primaryImage,
                secondaryImage: secondaryImage,
                details: details
            )
            try ComparisonStillRenderer.writePNG(rendered, to: output.temporaryURL)
            guard taskOwner.isCurrent(.screenshot, token: token), !Task.isCancelled else { return }

            let outputURL = try output.commit()
            logger.info("Comparison still saved: \(outputURL.lastPathComponent)")
            screenshotState = .succeeded(outputURL)
            clearScreenshotSuccess(outputURL: outputURL)
        } catch is CancellationError {
            guard taskOwner.isCurrent(.screenshot, token: token) else { return }
            screenshotState = .idle
            logger.info("Comparison still cancelled")
        } catch {
            guard taskOwner.isCurrent(.screenshot, token: token) else { return }
            screenshotState = .failed("Comparison still failed: \(error.localizedDescription)")
            logger.error("Comparison still failed: \(error.localizedDescription)")
        }
    }

    private func performScreenshot(
        for item: MediaItem,
        at time: Double,
        token: MediaOperationTaskOwner.Token,
        subprocessHandle: SubprocessHandle
    ) async {
        guard taskOwner.isCurrent(.screenshot, token: token) else { return }

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
                screenshotSavePanel = panel
                panel.nameFieldStringValue = outputName
                panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension) ?? .image]
                panel.canCreateDirectories = true
                panel.directoryURL = item.url.deletingLastPathComponent()

                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
            screenshotSavePanel = nil

            guard taskOwner.isCurrent(.screenshot, token: token),
                  !Task.isCancelled,
                  let chosenURL else { return }
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
            try await FFmpegService.run(
                arguments: arguments,
                duration: nil,
                onProgress: nil,
                handle: subprocessHandle
            )
            guard taskOwner.isCurrent(.screenshot, token: token), !Task.isCancelled else { return }
            let outputURL = try output.commit()
            logger.info("Screenshot saved: \(outputURL.lastPathComponent)")
            screenshotState = .succeeded(outputURL)
            clearScreenshotSuccess(outputURL: outputURL)
        } catch let error as FFmpegError where error == .cancelled {
            guard taskOwner.isCurrent(.screenshot, token: token) else { return }
            screenshotState = .idle
            logger.info("Screenshot cancelled")
        } catch {
            guard taskOwner.isCurrent(.screenshot, token: token) else { return }
            screenshotState = .failed("Screenshot failed: \(error.localizedDescription)")
            logger.error("Screenshot failed: \(error.localizedDescription)")
        }
    }

    func dismissScreenshotFeedback() {
        screenshotFeedbackDismissal.cancel()
        screenshotState = .idle
    }

    // MARK: - Trim Export

    func exportTrim(for item: MediaItem) {
        guard !trimExportState.isInFlight else { return }

        trimExportFeedbackDismissal.cancel()
        trimExportState = .idle
        guard let inPoint = trimIn, let outPoint = trimOut, outPoint > inPoint else {
            let missing = trimIn == nil && trimOut == nil ? "Set trim in and out points first."
                : trimIn == nil ? "Set a trim in point first."
                : trimOut == nil ? "Set a trim out point first."
                : "Trim out must be after trim in."
            logger.warning("Export requires both trim in and out points")
            trimExportState = .warning(missing)
            clearTrimWarning(message: missing)
            return
        }

        taskOwner.start(.trimExport) { [weak self] token, subprocessHandle in
            await self?.performTrimExport(
                for: item,
                inPoint: inPoint,
                outPoint: outPoint,
                token: token,
                subprocessHandle: subprocessHandle
            )
        }
    }

    private func performTrimExport(
        for item: MediaItem,
        inPoint: Double,
        outPoint: Double,
        token: MediaOperationTaskOwner.Token,
        subprocessHandle: SubprocessHandle
    ) async {
        guard taskOwner.isCurrent(.trimExport, token: token) else { return }

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
                trimExportSavePanel = panel
                panel.nameFieldStringValue = defaultName
                panel.allowedContentTypes = [UTType(filenameExtension: outputExtension) ?? .movie]
                panel.canCreateDirectories = true
                panel.directoryURL = item.url.deletingLastPathComponent()

                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
            trimExportSavePanel = nil

            guard taskOwner.isCurrent(.trimExport, token: token),
                  !Task.isCancelled,
                  let chosenURL else { return }
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

        let progressCallback: (@Sendable (Double) -> Void)?
        if format != .copy {
            progressCallback = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.taskOwner.isCurrent(.trimExport, token: token),
                          self.trimExportState.acceptsProgress else { return }
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
                handle: subprocessHandle
            )
            guard taskOwner.isCurrent(.trimExport, token: token), !Task.isCancelled else { return }
            let outputURL = try output.commit()
            logger.info("Trim export saved: \(outputURL.lastPathComponent)")
            trimExportState = .succeeded(outputURL)
            clearTrimSuccess(outputURL: outputURL)
        } catch let error as FFmpegError where error == .cancelled {
            guard taskOwner.isCurrent(.trimExport, token: token) else { return }
            logger.info("Trim export cancelled")
            trimExportState = .cancelled
            clearTrimCancellation()
        } catch {
            guard taskOwner.isCurrent(.trimExport, token: token) else { return }
            trimExportState = .failed("Export failed: \(error.localizedDescription)")
            logger.error("Trim export failed: \(error.localizedDescription)")
        }
    }

    func cancelExport() {
        guard taskOwner.isActive(.trimExport) else { return }
        trimExportState = .cancelling
        taskOwner.requestCancellation(.trimExport)
    }

    func dismissTrimExportFeedback() {
        trimExportFeedbackDismissal.cancel()
        trimExportState = .idle
    }

    /// Cancels every operation owned by the closing player window.
    func cancelOperationsForWindowClose() {
        taskOwner.cancelAll()
        screenshotSavePanel?.cancel(nil)
        trimExportSavePanel?.cancel(nil)
        screenshotSavePanel = nil
        trimExportSavePanel = nil
        screenshotFeedbackDismissal.cancel()
        trimExportFeedbackDismissal.cancel()
        screenshotState = .idle
        trimExportState = .idle
    }

    // MARK: - Delayed Feedback Cleanup

    private func clearScreenshotSuccess(outputURL: URL) {
        screenshotFeedbackDismissal.schedule(after: feedbackDelays.screenshotSuccess) { [weak self] in
            guard self?.screenshotState == .succeeded(outputURL) else { return }
            self?.screenshotState = .idle
        }
    }

    private func clearTrimWarning(message: String) {
        trimExportFeedbackDismissal.schedule(after: feedbackDelays.trimWarning) { [weak self] in
            guard self?.trimExportState == .warning(message) else { return }
            self?.trimExportState = .idle
        }
    }

    private func clearTrimSuccess(outputURL: URL) {
        trimExportFeedbackDismissal.schedule(after: feedbackDelays.trimSuccess) { [weak self] in
            guard self?.trimExportState == .succeeded(outputURL) else { return }
            self?.trimExportState = .idle
        }
    }

    private func clearTrimCancellation() {
        trimExportFeedbackDismissal.schedule(after: feedbackDelays.trimCancellation) { [weak self] in
            guard self?.trimExportState == .cancelled else { return }
            self?.trimExportState = .idle
        }
    }
}

nonisolated struct MediaOperationFeedbackDelays: Sendable {
    let screenshotSuccess: Duration
    let trimWarning: Duration
    let trimSuccess: Duration
    let trimCancellation: Duration

    static let standard = MediaOperationFeedbackDelays(
        screenshotSuccess: .seconds(5),
        trimWarning: .seconds(2),
        trimSuccess: .seconds(5),
        trimCancellation: .milliseconds(1_500)
    )
}
