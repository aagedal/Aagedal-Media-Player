// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Main window: drop zone when no file, player when file is loaded.

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OSLog

struct ContentView: View {
    @StateObject private var controller = PlayerController()
    @State private var timecodeMode: TimecodeDisplayMode = .preferred
    @State private var isDropTargeted = false
    @State private var showInspector = false
    @State private var showOverlay = true
    @State private var isHoveringWindow = false
    @State private var isHoveringControls = false
    @State private var isHoveringRightEdge = false
    @State private var overlayHideTask: Task<Void, Never>?
    @State private var mouseMoveMonitor: Any?
    @State private var appActiveObserver: NSObjectProtocol?
    @State private var isEditingTimecode = false
    @State private var timecodeActivationTrigger: String?

    private let rightEdgeWidth: CGFloat = 60
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "ContentView")

    private var isPlaying: Bool { controller.isPlaying }
    private var isMediaLoaded: Bool { controller.mediaItem != nil }

    private var videoAspectRatio: CGFloat? {
        controller.videoAspectRatio
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1: content (player or drop zone)
            if controller.mediaItem != nil {
                PlayerView(
                    controller: controller,
                    item: controller.mediaItem!,
                    isEditingTimecode: $isEditingTimecode,
                    timecodeActivationTrigger: $timecodeActivationTrigger
                )
            } else {
                DropZoneView(isDropTargeted: isDropTargeted, onOpenFile: openFilePanel)
            }

            // Layer 2: overlay controls
            overlayControls

            // Layer 3: right-edge cursor hide zone
            if isMediaLoaded && !showInspector {
                cursorHideZone
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 500, minHeight: 250)
        .background(Color.black)
        .background(
            WindowConfigurator(
                aspectRatio: videoAspectRatio,
                showTrafficLights: isHoveringWindow && !isHoveringRightEdge
            )
        )
        .onHover { hovering in
            isHoveringWindow = hovering
            if !hovering && !isEditingTimecode {
                showOverlay = false
                overlayHideTask?.cancel()
            }
        }
        .inspector(isPresented: $showInspector) {
            if let item = controller.mediaItem {
                MetadataInspectorView(item: item, useMPV: controller.useMPV, isPresented: $showInspector)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onOpenURL { url in
            openFile(url: url)
        }
        .onAppear {
            installMouseMoveMonitor()
            installAppActiveObserver()
        }
        .onDisappear {
            removeMouseMoveMonitor()
            removeAppActiveObserver()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            openFilePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
            if let url = notification.object as? URL {
                openFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            showInspector.toggle()
        }
    }

    // MARK: - Overlay Controls

    private var overlayControls: some View {
        VStack(spacing: 0) {
            if isMediaLoaded {
                topToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            ControlsView(
                controller: controller,
                item: controller.mediaItem,
                timecodeMode: $timecodeMode,
                isEditingTimecode: $isEditingTimecode,
                timecodeActivationTrigger: $timecodeActivationTrigger
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .frame(minWidth: 20)
        }
        .onHover { hovering in
            isHoveringControls = hovering
            if hovering {
                overlayHideTask?.cancel()
            }
        }
        .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
        .animation(.easeInOut(duration: 0.3), value: showOverlay)
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack {
            Spacer()
            Button(action: { showInspector.toggle() }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Show metadata inspector")
            .disabled(controller.mediaItem == nil)
        }
        .padding(.leading, 16)
        .padding(.trailing, rightEdgeWidth + 16)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Cursor Hide Zone

    private var cursorHideZone: some View {
        HStack {
            Spacer()
            CursorHideZone { hovering in
                isHoveringRightEdge = hovering
                if hovering {
                    showOverlay = false
                    overlayHideTask?.cancel()
                } else {
                    showOverlay = true
                    scheduleOverlayHide()
                }
            }
            .frame(width: rightEdgeWidth)
        }
        .padding(.bottom, 80)
    }

    // MARK: - Overlay Auto-Hide

    private func scheduleOverlayHide() {
        overlayHideTask?.cancel()

        guard !isHoveringControls, !isEditingTimecode, isPlaying else { return }

        overlayHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if !isHoveringControls && !isEditingTimecode && isPlaying {
                showOverlay = false
            }
        }
    }

    // MARK: - Mouse & App Observers

    private func installMouseMoveMonitor() {
        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            guard isMediaLoaded,
                  !isHoveringRightEdge,
                  let window = NSApp.keyWindow,
                  window.isKeyWindow else {
                return event
            }

            // Safety net: if cursor was hidden by right-edge zone but mouse moved
            // outside it, force-correct the state.
            CursorHideNSView.ensureCursorVisible()

            showOverlay = true
            scheduleOverlayHide()

            return event
        }
    }

    private func removeMouseMoveMonitor() {
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
    }

    private func installAppActiveObserver() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            // Returning from another app — cursor must be visible.
            isHoveringRightEdge = false
            CursorHideNSView.ensureCursorVisible()
        }
    }

    private func removeAppActiveObserver() {
        if let observer = appActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appActiveObserver = nil
        }
    }

    // MARK: - File Opening

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedMediaTypes

        if panel.runModal() == .OK, let url = panel.url {
            openFile(url: url)
        }
    }

    func openFile(url: URL) {
        logger.info("Opening file: \(url.lastPathComponent)")

        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        var item = MediaItem(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            size: fileSize
        )

        // Start playback immediately, load metadata in parallel
        controller.loadMedia(item)
        NSApp.keyWindow?.title = item.name

        Task {
            do {
                let metadata = try await MetadataService.shared.metadata(for: url)
                item.metadata = metadata
                item.durationSeconds = metadata.duration ?? 0
                item.hasVideoStream = !metadata.videoStreams.isEmpty
                controller.updateMetadata(item)
            } catch {
                logger.warning("Failed to load metadata: \(error.localizedDescription)")
            }
        }

        // Add to recent files
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else { return }
            Task { @MainActor in
                self.openFile(url: url)
            }
        }

        return true
    }

    private var supportedMediaTypes: [UTType] {
        [
            .movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video,
            UTType("public.mpeg-4") ?? .movie,
            UTType("com.microsoft.windows-media-wmv") ?? .movie,
            UTType("org.matroska.mkv") ?? .movie,
            UTType("public.mxf") ?? .movie,
            UTType("com.apple.quicktime-movie") ?? .quickTimeMovie,
            UTType("public.mp3") ?? .audio,
            UTType("public.aiff-audio") ?? .audio,
            UTType("org.xiph.flac") ?? .audio,
            UTType("com.microsoft.waveform-audio") ?? .audio,
        ]
    }
}
