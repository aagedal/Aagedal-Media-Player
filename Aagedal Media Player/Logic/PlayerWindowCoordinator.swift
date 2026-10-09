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
    @Published private(set) var openingURL: URL?
    var isOpeningFile: Bool { openingURL != nil }
    @Published private(set) var canOpenPreviousFile = false
    @Published private(set) var canOpenNextFile = false

    private var fileOpenTask: Task<Void, Never>?
    private var fileOpenGeneration = 0
    private let mediaItemLoader: @Sendable (URL) async -> MediaItem
    private let metadataLoader: @Sendable (URL) async throws -> MediaMetadata
    private let noteRecentDocument: @MainActor (URL) -> Void
    private var folderNavigationTask: Task<Void, Never>?
    private var windowWillCloseObserver: NSObjectProtocol?
    private var windowCloseHandler: (() -> Void)?
    private weak var closedWindow: NSWindow?
    private var droppedURLResults: DroppedURLResults?
    private var droppedURLLoadProgresses: [Progress] = []
    private var siblingMediaURLs: [URL] = []
    private var siblingMediaIndex: Int?
    private let logger = Logger(
        subsystem: "com.aagedal.MediaPlayer",
        category: "PlayerWindowCoordinator"
    )

    init(
        id: UUID = UUID(),
        mediaItemLoader: @escaping @Sendable (URL) async -> MediaItem = {
            PlayerWindowCoordinator.makeMediaItem(for: $0)
        },
        metadataLoader: @escaping @Sendable (URL) async throws -> MediaMetadata = {
            try await MetadataService.shared.metadata(for: $0)
        },
        noteRecentDocument: @escaping @MainActor (URL) -> Void = {
            NSDocumentController.shared.noteNewRecentDocumentURL($0)
        }
    ) {
        self.id = id
        self.mediaItemLoader = mediaItemLoader
        self.metadataLoader = metadataLoader
        self.noteRecentDocument = noteRecentDocument
    }

    /// Accepts an AppKit window that SwiftUI created for this player scene.
    /// Extra URL-routing windows are rejected unless WindowManager explicitly
    /// reserved a slot for them.
    @discardableResult
    func accept(
        _ candidate: NSWindow,
        onClose: (() -> Void)? = nil
    ) -> Bool {
        // Published teardown state can trigger one last SwiftUI update while
        // the native window is closing. Never let that update re-register the
        // same window or reinstall its close callback.
        guard closedWindow !== candidate else { return false }
        if window === candidate {
            if let onClose {
                windowCloseHandler = onClose
            }
            return true
        }

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

        windowCloseHandler = onClose
        cascade(candidate, after: manager.windows.values.compactMap(\.window).count)
        window = candidate
        manager.register(id: id, window: candidate)
        observeWindowClose(candidate)
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

    func openFilePanel(onSelection: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedMediaTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        onSelection(url)
    }

    func openFile(
        _ url: URL,
        controller: PlayerController,
        onTimecodeModeChange: @escaping (TimecodeDisplayMode) -> Void,
        onMetadataLoaded: @escaping () -> Void
    ) {
        logger.info("Opening file: \(url.lastPathComponent)")
        fileOpenTask?.cancel()
        fileOpenGeneration &+= 1
        let generation = fileOpenGeneration
        openingURL = url
        refreshFolderNavigation(for: url)

        WindowManager.shared.markHasMedia(id: id)
        (window ?? NSApp.keyWindow)?.title = url.deletingPathExtension().lastPathComponent

        fileOpenTask = Task { @MainActor in
            defer {
                if fileOpenGeneration == generation { openingURL = nil }
            }
            var item = await mediaItemLoader(url)
            guard !Task.isCancelled, fileOpenGeneration == generation else { return }
            let loader = metadataLoader
            let preloadedMetadata = await AsyncDeadline.value(within: .milliseconds(500)) {
                try? await loader(url)
            }
            guard !Task.isCancelled, fileOpenGeneration == generation else { return }

            if let metadata = preloadedMetadata {
                Self.apply(metadata, to: &item)
                onTimecodeModeChange(metadata.timecode != nil ? .source : .relative)
            }

            controller.loadMedia(item)
            openingURL = nil

            if preloadedMetadata != nil {
                // updateMetadata runs the HDR transfer-function pass and
                // audio-only presentation hooks after loadMedia seeds the
                // initial window geometry from the same MediaItem.
                controller.updateMetadata(item)
                onMetadataLoaded()
            } else {
                logger.info("Metadata fetch exceeded preload timeout for \(url.lastPathComponent), continuing without preload")
                do {
                    let metadata = try await metadataLoader(url)
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

        noteRecentDocument(url)
    }

    func previousMediaURL() -> URL? {
        adjacentMediaURL(offset: -1)
    }

    func nextMediaURL() -> URL? {
        adjacentMediaURL(offset: 1)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        cancelDroppedURLLoads()

        let results = DroppedURLResults(count: providers.count)
        droppedURLResults = results

        for (index, provider) in providers.enumerated() {
            let progress = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let completedURLs = results.record(url, at: index) else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.droppedURLResults === results else { return }
                    self.droppedURLResults = nil
                    self.droppedURLLoadProgresses = []
                    WindowManager.shared.open(completedURLs)
                }
            }
            droppedURLLoadProgresses.append(progress)
        }

        return true
    }

    func tearDown() {
        if let windowWillCloseObserver {
            NotificationCenter.default.removeObserver(windowWillCloseObserver)
            self.windowWillCloseObserver = nil
        }
        windowCloseHandler = nil
        fileOpenTask?.cancel()
        fileOpenTask = nil
        fileOpenGeneration &+= 1
        openingURL = nil
        folderNavigationTask?.cancel()
        folderNavigationTask = nil
        cancelDroppedURLLoads()
        siblingMediaURLs = []
        siblingMediaIndex = nil
        canOpenPreviousFile = false
        canOpenNextFile = false
        WindowManager.shared.unregister(id: id)
        window = nil
    }

    private func observeWindowClose(_ window: NSWindow) {
        if let windowWillCloseObserver {
            NotificationCenter.default.removeObserver(windowWillCloseObserver)
        }
        windowWillCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.window === window else { return }
                self.closedWindow = window
                let closeHandler = self.windowCloseHandler
                self.windowCloseHandler = nil
                closeHandler?()
                self.tearDown()
            }
        }
    }

    private func cancelDroppedURLLoads() {
        droppedURLResults?.cancel()
        droppedURLResults = nil
        for progress in droppedURLLoadProgresses {
            progress.cancel()
        }
        droppedURLLoadProgresses = []
    }

    /// Returns supported media files beside the current item in stable Finder-like
    /// filename order. Folder navigation is intentionally local to each player
    /// window rather than a global playlist.
    nonisolated static func siblingMediaFiles(
        containing currentURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let directory = currentURL.deletingLastPathComponent()
        let resourceKeys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey]
        let resourceKeySet = Set(resourceKeys)
        let candidates = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates
            .filter { url in
                let values = try? url.resourceValues(forKeys: resourceKeySet)
                guard values?.isRegularFile != false else { return false }
                guard let type = values?.contentType
                    ?? UTType(filenameExtension: url.pathExtension) else { return false }
                return supportedMediaTypes.contains { type.conforms(to: $0) }
            }
            .sorted(by: compareMediaFilenames)
    }

    /// A URL-only placeholder: file attributes can block for seconds on a
    /// network mount. Metadata supplies the size after its background read.
    nonisolated static func makeMediaItem(for url: URL) -> MediaItem {
        return MediaItem(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            size: 0
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

    private func refreshFolderNavigation(for currentURL: URL) {
        folderNavigationTask?.cancel()
        applyFolderNavigation(currentURL: currentURL, siblingURLs: [])
        folderNavigationTask = Task { [weak self] in
            let siblingURLs = await Task.detached(priority: .userInitiated) {
                Self.siblingMediaFiles(containing: currentURL)
            }.value
            guard !Task.isCancelled else { return }
            self?.applyFolderNavigation(
                currentURL: currentURL,
                siblingURLs: siblingURLs
            )
        }
    }

    func applyFolderNavigation(currentURL: URL, siblingURLs: [URL]) {
        siblingMediaURLs = siblingURLs
        // Directory enumeration returns siblings in this same directory. URL
        // equality is lexical; standardizedFileURL performs reachability I/O
        // and can block the main actor on every file in a network directory.
        siblingMediaIndex = siblingMediaURLs.firstIndex(of: currentURL)
        updateFolderNavigationAvailability()
    }

    private func adjacentMediaURL(offset: Int) -> URL? {
        guard let siblingMediaIndex else { return nil }
        let destinationIndex = siblingMediaIndex + offset
        guard siblingMediaURLs.indices.contains(destinationIndex) else { return nil }
        return siblingMediaURLs[destinationIndex]
    }

    private func updateFolderNavigationAvailability() {
        guard let siblingMediaIndex else {
            canOpenPreviousFile = false
            canOpenNextFile = false
            return
        }
        canOpenPreviousFile = siblingMediaURLs.indices.contains(siblingMediaIndex - 1)
        canOpenNextFile = siblingMediaURLs.indices.contains(siblingMediaIndex + 1)
    }

    nonisolated private static func compareMediaFilenames(_ lhs: URL, _ rhs: URL) -> Bool {
        let result = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent)
        if result == .orderedSame {
            return lhs.path < rhs.path
        }
        return result == .orderedAscending
    }

    private static func apply(_ metadata: MediaMetadata, to item: inout MediaItem) {
        item.metadata = metadata
        item.size = metadata.sizeBytes ?? item.size
        item.durationSeconds = metadata.duration ?? 0
        item.hasVideoStream = !metadata.videoStreams.isEmpty
    }

    nonisolated static let supportedMediaTypes: [UTType] = [
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
    nonisolated(unsafe) private var isActive = true

    nonisolated init(count: Int) {
        urls = Array(repeating: nil, count: count)
        remaining = count
    }

    nonisolated func record(_ url: URL?, at index: Int) -> [URL]? {
        lock.withLock {
            guard isActive, urls.indices.contains(index) else { return nil }
            urls[index] = url
            remaining -= 1
            guard remaining == 0 else { return nil }
            isActive = false
            return urls.compactMap { $0 }
        }
    }

    nonisolated func cancel() {
        lock.withLock {
            isActive = false
        }
    }
}
