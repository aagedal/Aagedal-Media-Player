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
    @State private var isEditingTimecode = false
    @State private var timecodeActivationTrigger: String?

    private let rightEdgeWidth: CGFloat = 60
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "ContentView")

    private var isPlaying: Bool { controller.isPlaying }

    private var isMediaLoaded: Bool {
        controller.mediaItem != nil
    }

    private var videoAspectRatio: CGFloat? {
        guard let item = controller.mediaItem,
              let ratio = item.videoDisplayAspectRatio,
              ratio.isFinite, ratio > 0 else {
            return nil
        }
        return CGFloat(ratio)
    }

    var body: some View {
        ZStack {
            if controller.mediaItem != nil {
                PlayerView(
                    controller: controller,
                    item: controller.mediaItem!,
                    isEditingTimecode: $isEditingTimecode,
                    timecodeActivationTrigger: $timecodeActivationTrigger
                )
            } else {
                dropZone
            }

            // Overlay controls
            VStack(spacing: 0) {
                // Top toolbar (only when media is loaded)
                if isMediaLoaded {
                    topToolbar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                ControlsView(
                    controller: controller,
                    item: controller.mediaItem,
                    timecodeMode: $timecodeMode,
                    isEditingTimecode: $isEditingTimecode,
                    timecodeActivationTrigger: $timecodeActivationTrigger
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .onHover { hovering in
                isHoveringControls = hovering
                if hovering {
                    overlayHideTask?.cancel()
                }
            }
            .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
            .animation(.easeInOut(duration: 0.3), value: showOverlay)

            // Right-edge cursor hide zone (only when media is loaded and inspector is closed)
            if isMediaLoaded && !showInspector {
                HStack {
                    Spacer()
                    RightEdgeCursorHideZone { hovering in
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
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 400)
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
        }
        .onDisappear {
            removeMouseMoveMonitor()
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

    // MARK: - Mouse Hover

    private func installMouseMoveMonitor() {
        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            guard isMediaLoaded,
                  !isHoveringRightEdge,
                  let window = NSApp.keyWindow,
                  window.isKeyWindow else {
                return event
            }

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

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Drop a media file here")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("or use File \u{2192} Open")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            Button("Open File\u{2026}") {
                openFilePanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 95)
        )
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

// MARK: - Window Configurator

/// Configures the NSWindow for borderless video playback:
/// transparent titlebar, full-size content, aspect ratio lock, traffic light visibility.
private struct WindowConfigurator: NSViewRepresentable {
    let aspectRatio: CGFloat?
    let showTrafficLights: Bool

    final class Coordinator: NSObject {
        var lastAspectRatio: CGFloat?
        var savedAspectRatio: CGFloat?
        weak var observedWindow: NSWindow?
        var willEnterFullScreen: NSObjectProtocol?
        var didExitFullScreen: NSObjectProtocol?
        var didBecomeKey: NSObjectProtocol?
        var lastTrafficLightAlpha: CGFloat = 0

        deinit {
            if let token = willEnterFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didExitFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didBecomeKey { NotificationCenter.default.removeObserver(token) }
        }

        /// Re-apply window chrome properties. Cheap to call repeatedly.
        func applyWindowAppearance(_ window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.backgroundColor = .black
        }

        func applyTrafficLightAlpha(_ window: NSWindow, animated: Bool = true) {
            let alpha = lastTrafficLightAlpha
            for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(buttonType),
                   let container = button.superview {
                    if container.alphaValue != alpha {
                        if animated {
                            NSAnimationContext.runAnimationGroup { ctx in
                                ctx.duration = 0.2
                                container.animator().alphaValue = alpha
                            }
                        } else {
                            container.alphaValue = alpha
                        }
                    }
                    break
                }
            }
        }

        func observeWindow(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            willEnterFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.savedAspectRatio = self.lastAspectRatio
                self.lastAspectRatio = nil
                window.contentResizeIncrements = NSSize(width: 1, height: 1)
            }

            didExitFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                guard let self, let ratio = self.savedAspectRatio, ratio > 0 else { return }
                DispatchQueue.main.async {
                    window.contentAspectRatio = NSSize(width: ratio, height: 1)
                    self.lastAspectRatio = ratio
                }
            }

            didBecomeKey = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                // macOS resets titlebar and traffic lights on activation —
                // re-apply after macOS finishes its updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self else { return }
                    self.applyWindowAppearance(window)
                    self.applyTrafficLightAlpha(window, animated: false)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        let coordinator = context.coordinator

        coordinator.observeWindow(window)

        let ratio = aspectRatio
        let trafficLightAlpha: CGFloat = showTrafficLights ? 1 : 0
        let isFullScreen = window.styleMask.contains(.fullScreen)

        DispatchQueue.main.async {
            coordinator.applyWindowAppearance(window)

            // Aspect ratio — only apply when not in fullscreen
            if !isFullScreen {
                if let ratio, ratio > 0 {
                    if coordinator.lastAspectRatio != ratio {
                        coordinator.lastAspectRatio = ratio
                        coordinator.savedAspectRatio = ratio
                        window.contentAspectRatio = NSSize(width: ratio, height: 1)

                        if let contentView = window.contentView {
                            let currentWidth = contentView.bounds.width
                            let newHeight = currentWidth / ratio
                            let frame = window.frame
                            let titlebarHeight = frame.height - contentView.bounds.height
                            let contentRect = NSRect(
                                x: frame.origin.x,
                                y: frame.origin.y + frame.height - newHeight - titlebarHeight,
                                width: frame.width,
                                height: newHeight + titlebarHeight
                            )
                            window.setFrame(contentRect, display: true, animate: true)
                        }
                    }
                } else {
                    if coordinator.lastAspectRatio != nil {
                        coordinator.lastAspectRatio = nil
                        coordinator.savedAspectRatio = nil
                        window.contentResizeIncrements = NSSize(width: 1, height: 1)
                    }
                }
            }

            coordinator.lastTrafficLightAlpha = trafficLightAlpha
            coordinator.applyTrafficLightAlpha(window)
        }
    }
}

// MARK: - Right Edge Cursor Hide Zone

private struct RightEdgeCursorHideZone: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RightEdgeCursorHideNSView {
        let view = RightEdgeCursorHideNSView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: RightEdgeCursorHideNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }
}

private class RightEdgeCursorHideNSView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        NSCursor.hide()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        NSCursor.unhide()
        onHoverChanged?(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateTrackingAreas()
        }
    }

    override func removeFromSuperview() {
        if isHovering {
            NSCursor.unhide()
            isHovering = false
        }
        super.removeFromSuperview()
    }

    deinit {
        if isHovering {
            NSCursor.unhide()
        }
    }
}
