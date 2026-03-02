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
    @Environment(\.openWindow) private var openWindow
    @StateObject private var controller = PlayerController()
    @State private var timecodeMode: TimecodeDisplayMode = .relative
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
    @State private var nsWindow: NSWindow?
    @AppStorage("showCursorHideHint") private var showCursorHideHint = true
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var updateBannerDismissed = false

    private let windowID = UUID()
    private let rightEdgeWidth: CGFloat = 60
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "ContentView")

    private var isPlaying: Bool { controller.isPlaying }
    private var isMediaLoaded: Bool { controller.mediaItem != nil }

    private var videoAspectRatio: CGFloat? {
        controller.videoAspectRatio
    }

    // MARK: - Body

    var body: some View {
        contentLayers
            .modifier(NotificationHandlers(
                controller: controller,
                nsWindow: nsWindow,
                isEditingTimecode: $isEditingTimecode,
                showInspector: $showInspector,
                timecodeMode: $timecodeMode,
                showOverlay: $showOverlay,
                overlayHideTask: $overlayHideTask,
                isMediaLoaded: isMediaLoaded,
                openFilePanel: openFilePanel,
                openFile: openFile
            ))
    }

    // MARK: - Content Layers

    private var contentLayers: some View {
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

            // Layer 2: export/screenshot feedback
            if controller.isSavingScreenshot || controller.screenshotDone {
                exportOverlay(
                    isWorking: controller.isSavingScreenshot,
                    workingText: "Saving\u{2026}",
                    doneText: "Screenshot saved."
                )
            }
            if controller.isExportingTrim || controller.trimExportDone {
                exportOverlay(
                    isWorking: controller.isExportingTrim,
                    workingText: "Exporting\u{2026}",
                    doneText: "Trimmed file saved."
                )
            }

            // Layer 3: update banner
            if updateChecker.updateAvailable, !updateBannerDismissed {
                updateBanner
            }

            // Layer 4: overlay controls
            overlayControls

            // Layer 5: right-edge cursor hide zone
            if isMediaLoaded && !showInspector {
                cursorHideZone
            }
        }
        .ignoresSafeArea()
        .focusedSceneValue(\.isMediaLoaded, isMediaLoaded)
        .frame(minWidth: 270, minHeight: 200)
        .background(Color.black)
        .background(
            WindowConfigurator(
                aspectRatio: videoAspectRatio,
                showTrafficLights: isHoveringWindow && !isHoveringRightEdge,
                onWindowAvailable: { window in
                    if nsWindow !== window {
                        let wm = WindowManager.shared
                        // Allow the very first window unconditionally.
                        // For subsequent windows, only allow if explicitly
                        // requested (windowsToAllow > 0). This blocks unwanted
                        // windows that SwiftUI creates via URL routing.
                        if wm.hasWindows && wm.windowsToAllow <= 0 {
                            window.orderOut(nil)
                            DispatchQueue.main.async {
                                window.close()
                            }
                            return
                        }
                        if wm.windowsToAllow > 0 { wm.windowsToAllow -= 1 }

                        // Cascade new windows so they don't stack on top of each other.
                        // Count before registering so the current window isn't included.
                        // Deferred so it runs after SwiftUI finishes positioning the window.
                        let existingCount = wm.windows.values.filter({ $0.window != nil }).count
                        if existingCount > 0 {
                            DispatchQueue.main.async {
                                guard window.isVisible else { return }
                                let offset = CGFloat(existingCount) * 12
                                var frame = window.frame
                                frame.origin.x += offset
                                frame.origin.y -= offset
                                window.setFrameOrigin(frame.origin)
                            }
                        }

                        nsWindow = window
                        wm.register(id: windowID, window: window)
                    }
                }
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
        .onAppear {
            installMouseMoveMonitor()
            installAppActiveObserver()
            WindowManager.shared.openNewWindow = { [openWindow] in
                openWindow(id: "player")
            }

            // On first launch with multiple files, the first window spawns
            // additional windows for the remaining URLs.
            let wm = WindowManager.shared
            if !wm.pendingWindowsSpawned && wm.pendingFileURLs.count > 1 {
                wm.pendingWindowsSpawned = true
                let extra = wm.pendingFileURLs.count - 1
                wm.windowsToAllow += extra
                for _ in 0..<extra {
                    openWindow(id: "player")
                }
            }
        }
        .task {
            // Wait for this window to be accepted by onWindowAvailable.
            // Rejected windows (closed by the guard) never get nsWindow set
            // and must not consume pending URLs.
            for _ in 0..<20 {
                if nsWindow != nil { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard nsWindow != nil else { return }

            // Handle file(s) passed via Finder: application(_:open:) may
            // populate pendingFileURLs before or after this view appears.
            for _ in 0..<10 {
                if controller.mediaItem != nil { return }
                if !WindowManager.shared.pendingFileURLs.isEmpty {
                    let url = WindowManager.shared.pendingFileURLs.removeFirst()
                    openFile(url: url)
                    nsWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            // Safety net: if the app was opened with files but this window
            // didn't receive one (e.g. system-created extra window), close
            // it once another window has successfully loaded media.
            guard WindowManager.shared.fileOpenInProgress else { return }
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if controller.mediaItem != nil { return }
                if WindowManager.shared.otherWindowsHaveMedia(excluding: windowID) {
                    nsWindow?.close()
                    return
                }
            }
        }
        .onDisappear {
            removeMouseMoveMonitor()
            removeAppActiveObserver()
            controller.teardown()
            WindowManager.shared.unregister(id: windowID)
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

    // MARK: - Export Overlay

    private func exportOverlay(isWorking: Bool, workingText: String, doneText: String) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text(workingText)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(doneText)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: .capsule)
            .padding(.bottom, 80)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: isWorking)
        .allowsHitTesting(false)
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
            ZStack {
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

                // Discoverability hint — visible with overlay, hidden with it
                if showCursorHideHint {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.white.opacity(0.25))
                        .overlay {
                            ZStack {
                                Image(systemName: "cursorarrow")
                                    .font(.system(size: 14))
                                // Diagonal slash through the cursor
                                Rectangle()
                                    .frame(width: 18, height: 1.5)
                                    .rotationEffect(.degrees(-45))
                            }
                            .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(6)
                        .opacity(showOverlay && !isHoveringRightEdge ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: showOverlay)
                        .animation(.easeInOut(duration: 0.3), value: isHoveringRightEdge)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: rightEdgeWidth)
        }
        .padding(.bottom, 80)
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.white)

                Text("Version \(updateChecker.latestVersion ?? "") available")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Link(destination: URL(string: "https://github.com/aagedal/Aagedal-Media-Player/releases")!) {
                    Text("Download")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: .capsule)
                }

                Button {
                    withAnimation { updateBannerDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.85), in: .capsule)
            .padding(.top, 36)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(true)
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
                  isHoveringWindow,
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
            overlayHideTask?.cancel()
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
        WindowManager.shared.markHasMedia(id: windowID)
        (nsWindow ?? NSApp.keyWindow)?.title = item.name

        Task {
            do {
                let metadata = try await MetadataService.shared.metadata(for: url)
                item.metadata = metadata
                item.durationSeconds = metadata.duration ?? 0
                item.hasVideoStream = !metadata.videoStreams.isEmpty
                controller.updateMetadata(item)
                timecodeMode = metadata.timecode != nil ? .source : .relative
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
            UTType("org.webmproject.webm") ?? .movie,
            UTType("com.apple.quicktime-movie") ?? .quickTimeMovie,
            UTType("public.mp3") ?? .audio,
            UTType("public.aiff-audio") ?? .audio,
            UTType("org.xiph.flac") ?? .audio,
            UTType("com.microsoft.waveform-audio") ?? .audio,
        ]
    }
}

// MARK: - Notification Handlers (split out to help Swift type-checker)

private struct NotificationHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    let nsWindow: NSWindow?
    @Binding var isEditingTimecode: Bool
    @Binding var showInspector: Bool
    @Binding var timecodeMode: TimecodeDisplayMode
    @Binding var showOverlay: Bool
    @Binding var overlayHideTask: Task<Void, Never>?
    let isMediaLoaded: Bool
    let openFilePanel: () -> Void
    let openFile: (URL) -> Void

    func body(content: Content) -> some View {
        content
            // File commands — key window only
            .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                openFilePanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
                // When a target window is specified, only that window handles the file.
                // Otherwise fall back to key-window routing via isActiveWindow.
                if let targetWindow = notification.userInfo?["targetWindow"] as? NSWindow {
                    guard targetWindow === nsWindow else { return }
                } else {
                    guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                }
                if let url = notification.object as? URL {
                    openFile(url)
                }
            }
            // Window-specific commands — key window only
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                showInspector.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureScreenshot)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                Task { await controller.captureScreenshot() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportTrim)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                Task { await controller.exportTrim() }
            }
            // Syncable playback commands — all windows when sync is ON, key window otherwise
            .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.togglePlayback()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reverse)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.startReverseSimulation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fastForward)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.fastForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekByFrames)) { notification in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if let count = (notification.object as? NSNumber)?.intValue {
                    controller.seekByFrames(count)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekBySeconds)) { notification in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if let seconds = (notification.object as? NSNumber)?.doubleValue {
                    controller.seek(by: seconds)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekToEdge)) { notification in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if let value = (notification.object as? NSNumber)?.doubleValue {
                    if value == 0 {
                        controller.seekTo(0)
                    } else {
                        let duration = controller.mediaItem?.durationSeconds ?? 0
                        controller.seekTo(max(0, duration))
                    }
                }
            }
            // Window-specific — key window only
            .onReceive(NotificationCenter.default.publisher(for: .toggleFullscreen)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                controller.toggleFullscreen()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cycleTimecodeMode)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow), !isEditingTimecode else { return }
                let hasSourceTC = controller.mediaItem.flatMap { TimecodeFormatter.effectiveStartTimecode(for: $0) } != nil
                timecodeMode.toggle(hasSourceTimecode: hasSourceTC)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                guard isMediaLoaded, !isEditingTimecode else { return }
                overlayHideTask?.cancel()
                showOverlay = false
            }
    }
}
