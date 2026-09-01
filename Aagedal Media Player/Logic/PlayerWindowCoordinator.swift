// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Owns per-player-window registration and asynchronous file opening.

import AppKit
import Combine
import OSLog
import UniformTypeIdentifiers

@MainActor
final class PlayerWindowCoordinator: ObservableObject {
    let id: UUID

    @Published private(set) var window: NSWindow?

    private var fileOpenTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: "com.aagedal.MediaPlayer",
        category: "PlayerWindowCoordinator"
    )

    init(id: UUID = UUID()) {
        self.id = id
    }

    /// Accepts an AppKit window that SwiftUI created for this player scene.
    /// Extra URL-routing windows are rejected unless WindowManager explicitly
    /// reserved a slot for them.
    @discardableResult
    func accept(_ candidate: NSWindow) -> Bool {
        guard window !== candidate else { return true }

        let manager = WindowManager.shared
        if manager.hasWindows && manager.windowsToAllow <= 0 {
            candidate.orderOut(nil)
            DispatchQueue.main.async {
                candidate.close()
            }
            return false
        }

        if manager.windowsToAllow > 0 {
            manager.windowsToAllow -= 1
        }

        cascade(candidate, after: manager.windows.values.compactMap(\.window).count)
        window = candidate
        manager.register(id: id, window: candidate)
        return true
    }

    func configureWindowOpening(openNewWindow: @escaping () -> Void) {
        WindowManager.shared.openNewWindow = openNewWindow

        let manager = WindowManager.shared
        guard !manager.pendingWindowsSpawned,
              manager.pendingFileURLs.count > 1 else { return }

        manager.pendingWindowsSpawned = true
        let extraWindowCount = manager.pendingFileURLs.count - 1
        manager.windowsToAllow += extraWindowCount
        for _ in 0..<extraWindowCount {
            openNewWindow()
        }
    }

    /// Consumes a Finder/Dock file queued for this scene once its NSWindow has
    /// been accepted. Also closes a redundant empty scene after another window
    /// successfully consumes the launch request.
    func consumePendingFile(
        controller: PlayerController,
        onTimecodeModeChange: @escaping (TimecodeDisplayMode) -> Void,
        onMetadataLoaded: @escaping () -> Void
    ) async {
        for _ in 0..<20 {
            if window != nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard window != nil else { return }

        for _ in 0..<10 {
            if controller.mediaItem != nil { return }
            if !WindowManager.shared.pendingFileURLs.isEmpty {
                let url = WindowManager.shared.pendingFileURLs.removeFirst()
                openFile(
                    url,
                    controller: controller,
                    onTimecodeModeChange: onTimecodeModeChange,
                    onMetadataLoaded: onMetadataLoaded
                )
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard WindowManager.shared.fileOpenInProgress else { return }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if controller.mediaItem != nil { return }
            if WindowManager.shared.otherWindowsHaveMedia(excluding: id) {
                window?.close()
                return
            }
        }
    }

    func openFilePanel(
        controller: PlayerController,
        onTimecodeModeChange: @escaping (TimecodeDisplayMode) -> Void,
        onMetadataLoaded: @escaping () -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedMediaTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(
            url,
            controller: controller,
            onTimecodeModeChange: onTimecodeModeChange,
            onMetadataLoaded: onMetadataLoaded
        )
    }

    func openFile(
        _ url: URL,
        controller: PlayerController,
        onTimecodeModeChange: @escaping (TimecodeDisplayMode) -> Void,
        onMetadataLoaded: @escaping () -> Void
    ) {
        logger.info("Opening file: \(url.lastPathComponent)")
        fileOpenTask?.cancel()

        var item = Self.makeMediaItem(for: url)
        WindowManager.shared.markHasMedia(id: id)
        (window ?? NSApp.keyWindow)?.title = item.name

        fileOpenTask = Task { @MainActor in
            let preloadedMetadata = await Self.loadMetadataWithTimeout(
                url: url,
                timeoutMillis: 500
            )
            guard !Task.isCancelled else { return }

            if let metadata = preloadedMetadata {
                Self.apply(metadata, to: &item)
                onTimecodeModeChange(metadata.timecode != nil ? .source : .relative)
            }

            controller.loadMedia(item)

            if preloadedMetadata != nil {
                // updateMetadata runs the HDR transfer-function pass and
                // audio-only presentation hooks after loadMedia seeds the
                // initial window geometry from the same MediaItem.
                controller.updateMetadata(item)
                onMetadataLoaded()
            } else {
                logger.info("Metadata fetch exceeded preload timeout for \(url.lastPathComponent), continuing without preload")
                do {
                    let metadata = try await MetadataService.shared.metadata(for: url)
                    guard !Task.isCancelled else { return }
                    Self.apply(metadata, to: &item)
                    controller.updateMetadata(item)
                    onTimecodeModeChange(metadata.timecode != nil ? .source : .relative)
                    onMetadataLoaded()
                } catch {
                    guard !Task.isCancelled else { return }
                    logger.warning("Failed to load metadata: \(error.localizedDescription)")
                }
            }
        }

        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let results = DroppedURLResults(count: providers.count)

        for (index, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let completedURLs = results.record(url, at: index) else { return }
                Task { @MainActor in
                    WindowManager.shared.open(completedURLs)
                }
            }
        }

        return true
    }

    func tearDown() {
        fileOpenTask?.cancel()
        fileOpenTask = nil
        WindowManager.shared.unregister(id: id)
        window = nil
    }

    nonisolated static func makeMediaItem(
        for url: URL,
        fileManager: FileManager = .default
    ) -> MediaItem {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        return MediaItem(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            size: fileSize
        )
    }

    private func cascade(_ candidate: NSWindow, after existingWindowCount: Int) {
        guard existingWindowCount > 0 else { return }
        DispatchQueue.main.async {
            guard candidate.isVisible else { return }
            let offset = CGFloat(existingWindowCount) * 12
            var frame = candidate.frame
            frame.origin.x += offset
            frame.origin.y -= offset
            candidate.setFrameOrigin(frame.origin)
        }
    }

    private static func apply(_ metadata: MediaMetadata, to item: inout MediaItem) {
        item.metadata = metadata
        item.durationSeconds = metadata.duration ?? 0
        item.hasVideoStream = !metadata.videoStreams.isEmpty
    }

    /// The underlying SwiftExif read is not cancellable, so timing out merely
    /// stops this caller waiting. The actor finishes and caches the result for
    /// the follow-up request in openFile.
    private static func loadMetadataWithTimeout(
        url: URL,
        timeoutMillis: UInt64
    ) async -> MediaMetadata? {
        await withTaskGroup(of: MediaMetadata?.self) { group in
            group.addTask {
                try? await MetadataService.shared.metadata(for: url)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutMillis * 1_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static let supportedMediaTypes: [UTType] = [
        .movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video,
        UTType("public.mpeg-4") ?? .movie,
        UTType("com.microsoft.windows-media-wmv") ?? .movie,
        UTType("org.matroska.mkv") ?? .movie,
        UTType("public.mxf") ?? .movie,
        UTType("org.webmproject.webm") ?? .movie,
        UTType("com.apple.quicktime-movie") ?? .quickTimeMovie,
        UTType("public.mp3") ?? .audio,
        UTType("public.aiff-audio") ?? .audio,
        UTType("org.xiph.flac") ?? .audio,
        UTType("com.microsoft.waveform-audio") ?? .audio,
    ]
}

/// Collects NSItemProvider callbacks without depending on completion order.
/// Provider callbacks may arrive concurrently and off the main actor.
final class DroppedURLResults: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var urls: [URL?]
    nonisolated(unsafe) private var remaining: Int

    nonisolated init(count: Int) {
        urls = Array(repeating: nil, count: count)
        remaining = count
    }

    nonisolated func record(_ url: URL?, at index: Int) -> [URL]? {
        lock.withLock {
            urls[index] = url
            remaining -= 1
            guard remaining == 0 else { return nil }
            return urls.compactMap { $0 }
        }
    }
}
