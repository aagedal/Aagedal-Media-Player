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
    @State private var scopeWindowController: ScopeWindowController?
    @State private var showScopeOverlay = false
    @AppStorage(SettingsView.scopeDisplayModeKey) private var scopeDisplayMode: String = ScopeDisplayMode.overlay.rawValue
    @AppStorage(SettingsView.scopeBackgroundKey) private var scopeBackground: String = ScopeBackground.transparent.rawValue
    @State private var audioWaveformWindowController: AudioWaveformWindowController?
    @State private var showAudioWaveformOverlay = false
    @StateObject private var audioWaveformGenerator = AudioWaveformGenerator()
    @AppStorage(SettingsView.audioWaveformDisplayModeKey) private var audioWaveformDisplayMode: String = AudioWaveformDisplayMode.overlay.rawValue
    @AppStorage(SettingsView.audioWaveformBackgroundKey) private var audioWaveformBackground: String = AudioWaveformBackground.transparent.rawValue

    private let windowID = UUID()
    private let rightEdgeWidth: CGFloat = 60
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "ContentView")

    private var isPlaying: Bool { controller.isPlaying }
    private var isMediaLoaded: Bool { controller.mediaItem != nil }

    private var videoAspectRatio: CGFloat? {
        controller.videoAspectRatio
    }

    private var videoSourceSize: NSSize? {
        controller.videoSourceSize
    }

    // MARK: - Body

    var body: some View {
        contentLayers
            .modifier(NotificationHandlers(
                controller: controller,
                nsWindow: nsWindow,
                isEditingTimecode: $isEditingTimecode,
                showInspector: $showInspector,
                scopeWindowController: $scopeWindowController,
                showScopeOverlay: $showScopeOverlay,
                audioWaveformWindowController: $audioWaveformWindowController,
                showAudioWaveformOverlay: $showAudioWaveformOverlay,
                audioWaveformGenerator: audioWaveformGenerator,
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

            // Layer 2: export/screenshot feedback (fades with overlay controls)
            Group {
                if controller.isSavingScreenshot || controller.screenshotDone {
                    if controller.isSavingScreenshot {
                        exportOverlay(statusText: "Saving\u{2026}", showSpinner: true)
                    } else {
                        exportOverlay(statusIcon: "checkmark.circle.fill", iconColor: .green, statusText: "Screenshot saved.")
                    }
                }
                if controller.isExportingTrim || controller.trimExportDone || controller.trimExportCancelling || controller.trimExportCancelled {
                    trimExportOverlay
                }
                if let warning = controller.trimExportWarning {
                    warningOverlay(warning)
                }
            }
            .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
            .animation(.easeInOut(duration: 0.3), value: showOverlay)

            // Layer 3: update banner
            if updateChecker.updateAvailable, !updateBannerDismissed {
                updateBanner
            }

            // Layer 4: overlay controls
            overlayControls

            // Layer 5: audio waveform overlay (always visible when active, independent of controls)
            if showAudioWaveformOverlay && isMediaLoaded && (!audioWaveformGenerator.channelImages.isEmpty || audioWaveformGenerator.isGenerating) {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        audioWaveformOverlay(containerHeight: geo.size.height)
                    }
                    .padding(.bottom, showOverlay ? 80 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showOverlay)
                }
                .allowsHitTesting(true)
            }

            // Layer 6: scope overlay (sits above audio waveform when both active)
            if showScopeOverlay && isMediaLoaded {
                GeometryReader { geo in
                    let audioWaveformHeight = showAudioWaveformOverlay ? max(60, geo.size.height / 4) : 0
                    VStack {
                        Spacer()
                        scopeOverlay(containerHeight: geo.size.height)
                    }
                    .padding(.bottom, (showOverlay ? 80 : 0) + audioWaveformHeight)
                    .animation(.easeInOut(duration: 0.3), value: showOverlay)
                }
                .allowsHitTesting(false)
            }

            // Layer 7: right-edge cursor hide zone
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
                videoSourceSize: videoSourceSize,
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
            scopeWindowController?.close()
            scopeWindowController = nil
            if showScopeOverlay {
                controller.frameCapture.stopCapture()
                showScopeOverlay = false
            }
            audioWaveformWindowController?.close()
            audioWaveformWindowController = nil
            showAudioWaveformOverlay = false
            audioWaveformGenerator.cancel()
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

    // MARK: - Scope Overlay

    private func scopeOverlay(containerHeight: CGFloat) -> some View {
        let targetHeight = max(80, containerHeight / 4)
        let isTransparent = scopeBackground == ScopeBackground.transparent.rawValue

        return ScopeView(
            frameCapture: controller.frameCapture,
            isOverlay: true,
            transparentBackground: isTransparent
        )
        .frame(height: targetHeight)
        .clipped()
    }

    // MARK: - Audio Waveform Overlay

    private func audioWaveformOverlay(containerHeight: CGFloat) -> some View {
        // Target ~1/3 of the container; if window is too small, fill available space
        let targetHeight = max(60, containerHeight / 4)
        let isTransparent = audioWaveformBackground == AudioWaveformBackground.transparent.rawValue

        return AudioWaveformView(
            generator: audioWaveformGenerator,
            controller: controller,
            isOverlay: true,
            transparentBackground: isTransparent
        )
        .frame(height: targetHeight)
        .clipped()
    }

    // MARK: - Export Overlay

    @ViewBuilder
    private var trimExportOverlay: some View {
        if controller.trimExportCancelling {
            exportOverlay(statusIcon: nil, statusText: "Cancelling\u{2026}", showSpinner: true)
        } else if controller.trimExportCancelled {
            exportOverlay(statusIcon: "xmark.circle.fill", iconColor: .orange, statusText: "Export cancelled.")
        } else if controller.isExportingTrim {
            if let progress = controller.trimExportProgress {
                exportOverlay(
                    statusText: "Exporting \(Int(progress * 100))%",
                    progress: progress,
                    onCancel: { controller.cancelExport() }
                )
            } else {
                exportOverlay(
                    statusText: "Preparing export\u{2026}",
                    showSpinner: true,
                    onCancel: { controller.cancelExport() }
                )
            }
        } else if controller.trimExportDone {
            exportOverlay(statusIcon: "checkmark.circle.fill", iconColor: .green, statusText: "Trimmed file saved.")
        }
    }

    private func exportOverlay(
        statusIcon: String? = nil,
        iconColor: Color = .green,
        statusText: String,
        showSpinner: Bool = false,
        progress: Double? = nil,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                if showSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
                if let statusIcon {
                    Image(systemName: statusIcon)
                        .foregroundStyle(iconColor)
                }
                Text(statusText)
                if let onCancel {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18, height: 18)
                            .background(.white.opacity(0.15), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: .capsule)
            .overlay {
                if let progress {
                    ProgressCapsuleBorder(progress: progress)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .animation(.linear(duration: 0.2), value: progress)
                }
            }
            .padding(.bottom, 80)
        }
        .transition(.opacity)
    }

    // MARK: - Progress Capsule Border

    /// A shape that traces a capsule's perimeter from top-center clockwise,
    /// drawing only the fraction specified by `progress` (0...1).
    private struct ProgressCapsuleBorder: Shape {
        var progress: Double

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let r = rect.height / 2
            // Total perimeter: two semicircles + two straight edges
            let straightLen = rect.width - 2 * r
            let semicircleLen = .pi * r
            let totalLen = 2 * semicircleLen + 2 * straightLen
            let target = totalLen * min(max(progress, 0), 1)

            var path = Path()
            var drawn: CGFloat = 0

            // Segment 1: top edge, from center-top rightward
            let seg1 = straightLen / 2
            if drawn >= target { return path }
            let s1 = min(seg1, target - drawn)
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + s1, y: rect.minY))
            drawn += s1

            // Segment 2: right semicircle (top to bottom, clockwise)
            if drawn >= target { return path }
            let s2 = min(semicircleLen, target - drawn)
            let angle2 = s2 / r // radians to sweep
            let center2 = CGPoint(x: rect.maxX - r, y: rect.midY)
            path.addArc(center: center2, radius: r,
                        startAngle: .radians(-.pi / 2),
                        endAngle: .radians(-.pi / 2 + angle2),
                        clockwise: false)
            drawn += s2

            // Segment 3: bottom edge, right to left
            if drawn >= target { return path }
            let s3 = min(straightLen, target - drawn)
            let bottomRight = CGPoint(x: rect.maxX - r, y: rect.maxY)
            path.addLine(to: CGPoint(x: bottomRight.x - s3, y: rect.maxY))
            drawn += s3

            // Segment 4: left semicircle (bottom to top, clockwise)
            if drawn >= target { return path }
            let s4 = min(semicircleLen, target - drawn)
            let angle4 = s4 / r
            let center4 = CGPoint(x: rect.minX + r, y: rect.midY)
            path.addArc(center: center4, radius: r,
                        startAngle: .radians(.pi / 2),
                        endAngle: .radians(.pi / 2 + angle4),
                        clockwise: false)
            drawn += s4

            // Segment 5: top edge, left to center
            if drawn >= target { return path }
            let s5 = min(straightLen / 2, target - drawn)
            let topLeft = CGPoint(x: rect.minX + r, y: rect.minY)
            path.addLine(to: CGPoint(x: topLeft.x + s5, y: rect.minY))

            return path
        }
    }

    private func warningOverlay(_ message: String) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: .capsule)
            .padding(.bottom, 80)
        }
        .transition(.opacity)
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
        ) { [self] _ in
            MainActor.assumeIsolated {
                // Returning from another app — cursor must be visible.
                isHoveringRightEdge = false
                CursorHideNSView.ensureCursorVisible()
                overlayHideTask?.cancel()
            }
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
                if showAudioWaveformOverlay {
                    generateAudioWaveform()
                }
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

    func generateAudioWaveform() {
        guard let item = controller.mediaItem,
              let metadata = item.metadata else { return }

        let trackIdx = controller.selectedAudioTrackOrderIndex
        guard trackIdx < controller.audioTrackOptions.count else { return }

        let option = controller.audioTrackOptions[trackIdx]
        let streamIndex = option.streamIndex
        let audioStreams = metadata.audioStreams
        guard streamIndex < audioStreams.count else { return }

        let stream = audioStreams[streamIndex]
        let channels = stream.channels ?? 2

        audioWaveformGenerator.generate(
            url: item.url,
            streamIndex: streamIndex,
            channels: channels,
            channelLayout: stream.channelLayout,
            duration: item.durationSeconds
        )
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
    @Binding var scopeWindowController: ScopeWindowController?
    @Binding var showScopeOverlay: Bool
    @Binding var audioWaveformWindowController: AudioWaveformWindowController?
    @Binding var showAudioWaveformOverlay: Bool
    @ObservedObject var audioWaveformGenerator: AudioWaveformGenerator
    @Binding var timecodeMode: TimecodeDisplayMode
    @Binding var showOverlay: Bool
    @Binding var overlayHideTask: Task<Void, Never>?
    let isMediaLoaded: Bool
    let openFilePanel: () -> Void
    let openFile: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(FileAndWindowHandlers(
                controller: controller, nsWindow: nsWindow,
                showInspector: $showInspector,
                scopeWindowController: $scopeWindowController,
                showScopeOverlay: $showScopeOverlay,
                audioWaveformWindowController: $audioWaveformWindowController,
                showAudioWaveformOverlay: $showAudioWaveformOverlay,
                audioWaveformGenerator: audioWaveformGenerator,
                openFilePanel: openFilePanel, openFile: openFile
            ))
            .modifier(PlaybackHandlers(controller: controller, nsWindow: nsWindow))
            .modifier(TimecodeAndSyncHandlers(
                controller: controller, nsWindow: nsWindow,
                isEditingTimecode: $isEditingTimecode,
                timecodeMode: $timecodeMode,
                showOverlay: $showOverlay,
                overlayHideTask: $overlayHideTask,
                isMediaLoaded: isMediaLoaded
            ))
    }
}

// MARK: - File & Window Handlers

private struct FileAndWindowHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    let nsWindow: NSWindow?
    @Binding var showInspector: Bool
    @Binding var scopeWindowController: ScopeWindowController?
    @Binding var showScopeOverlay: Bool
    @Binding var audioWaveformWindowController: AudioWaveformWindowController?
    @Binding var showAudioWaveformOverlay: Bool
    @ObservedObject var audioWaveformGenerator: AudioWaveformGenerator
    let openFilePanel: () -> Void
    let openFile: (URL) -> Void
    @AppStorage(SettingsView.scopeDisplayModeKey) private var scopeDisplayMode: String = ScopeDisplayMode.overlay.rawValue
    @AppStorage(SettingsView.audioWaveformDisplayModeKey) private var audioWaveformDisplayMode: String = AudioWaveformDisplayMode.overlay.rawValue

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                openFilePanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
                if let targetWindow = notification.userInfo?["targetWindow"] as? NSWindow {
                    guard targetWindow === nsWindow else { return }
                } else {
                    guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                }
                if let url = notification.object as? URL {
                    openFile(url)
                }
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .toggleFullscreen)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                controller.toggleFullscreen()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleScopes)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                let isOverlayMode = scopeDisplayMode == ScopeDisplayMode.overlay.rawValue

                if isOverlayMode {
                    // Close any existing window
                    scopeWindowController?.close()
                    scopeWindowController = nil

                    // Toggle overlay
                    showScopeOverlay.toggle()
                    if showScopeOverlay {
                        controller.frameCapture.startCapture()
                    } else {
                        // Only stop capture if the scope window isn't also open
                        if scopeWindowController == nil {
                            controller.frameCapture.stopCapture()
                        }
                    }
                } else {
                    // Close overlay if open
                    if showScopeOverlay {
                        showScopeOverlay = false
                        // Only stop capture if transitioning to window mode
                    }

                    // Toggle window
                    if let existing = scopeWindowController {
                        existing.toggle()
                        if !existing.isVisible {
                            scopeWindowController = nil
                        }
                    } else {
                        let filename = controller.mediaItem?.name ?? "Untitled"
                        let sc = ScopeWindowController(
                            frameCapture: controller.frameCapture,
                            filename: filename,
                            parentWindow: nsWindow
                        )
                        scopeWindowController = sc
                        sc.show()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleAudioWaveform)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow) else { return }
                let isOverlayMode = audioWaveformDisplayMode == AudioWaveformDisplayMode.overlay.rawValue

                if isOverlayMode {
                    // Close any existing window
                    audioWaveformWindowController?.close()
                    audioWaveformWindowController = nil

                    // Toggle overlay
                    showAudioWaveformOverlay.toggle()
                    if showAudioWaveformOverlay {
                        triggerOverlayWaveformGeneration()
                    } else {
                        audioWaveformGenerator.cancel()
                    }
                } else {
                    // Close overlay if open
                    showAudioWaveformOverlay = false
                    audioWaveformGenerator.cancel()

                    // Toggle window
                    if let existing = audioWaveformWindowController {
                        existing.toggle()
                        if !existing.isVisible {
                            audioWaveformWindowController = nil
                        }
                    } else {
                        let filename = controller.mediaItem?.name ?? "Untitled"
                        let wc = AudioWaveformWindowController(
                            controller: controller,
                            filename: filename,
                            parentWindow: nsWindow
                        )
                        audioWaveformWindowController = wc
                        wc.show()
                    }
                }
            }
    }

    private func triggerOverlayWaveformGeneration() {
        guard let item = controller.mediaItem,
              let metadata = item.metadata else { return }

        let trackIdx = controller.selectedAudioTrackOrderIndex
        guard trackIdx < controller.audioTrackOptions.count else { return }

        let option = controller.audioTrackOptions[trackIdx]
        let streamIndex = option.streamIndex
        let audioStreams = metadata.audioStreams
        guard streamIndex < audioStreams.count else { return }

        let stream = audioStreams[streamIndex]
        let channels = stream.channels ?? 2

        audioWaveformGenerator.generate(
            url: item.url,
            streamIndex: streamIndex,
            channels: channels,
            channelLayout: stream.channelLayout,
            duration: item.durationSeconds
        )
    }
}

// MARK: - Playback Handlers

private struct PlaybackHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    let nsWindow: NSWindow?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.togglePlayback()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reverse)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.startReverse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fastForward)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.fastForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .slowForward)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.slowForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .slowReverse)) { _ in
                guard WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                controller.slowReverse()
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
    }
}

// MARK: - Timecode, Sync & Clipboard Handlers

private struct TimecodeAndSyncHandlers: ViewModifier {
    @ObservedObject var controller: PlayerController
    let nsWindow: NSWindow?
    @Binding var isEditingTimecode: Bool
    @Binding var timecodeMode: TimecodeDisplayMode
    @Binding var showOverlay: Bool
    @Binding var overlayHideTask: Task<Void, Never>?
    let isMediaLoaded: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .cycleTimecodeMode)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow), !isEditingTimecode else { return }
                let hasSourceTC = controller.mediaItem.flatMap { TimecodeFormatter.effectiveStartTimecode(for: $0) } != nil
                timecodeMode.toggle(hasSourceTimecode: hasSourceTC)
            }
            // Sync timecode — active window reads its time and broadcasts
            .onReceive(NotificationCenter.default.publisher(for: .syncTimecode)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                let relTime = controller.currentPlaybackTime
                var userInfo: [String: Double] = ["relTime": relTime]
                if let item = controller.mediaItem,
                   let startSeconds = TimecodeFormatter.startTimecodeInSeconds(for: item) {
                    userInfo["srcTime"] = relTime + startSeconds
                }
                NotificationCenter.default.post(name: .seekToSyncedTime, object: nil, userInfo: userInfo)
            }
            // Sync timecode — non-active windows seek to the broadcast time
            .onReceive(NotificationCenter.default.publisher(for: .seekToSyncedTime)) { notification in
                guard !WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                guard let info = notification.userInfo as? [String: Double] else { return }
                if let srcTime = info["srcTime"],
                   let item = controller.mediaItem,
                   let receiverStartSeconds = TimecodeFormatter.startTimecodeInSeconds(for: item) {
                    let seekPosition = srcTime - receiverStartSeconds
                    controller.seekTo(max(0, seekPosition))
                } else if let relTime = info["relTime"] {
                    controller.seekTo(relTime)
                }
            }
            // Copy timecode — copies the current timecode display to the clipboard
            .onReceive(NotificationCenter.default.publisher(for: .copyTimecode)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                guard let item = controller.mediaItem else { return }
                let tc = TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: controller.currentPlaybackTime,
                    item: item,
                    mode: timecodeMode,
                    includePrefix: false
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tc, forType: .string)
            }
            // Paste timecode — reads a timecode from clipboard and seeks to it
            .onReceive(NotificationCenter.default.publisher(for: .pasteTimecode)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                guard let item = controller.mediaItem,
                      let clipboardString = NSPasteboard.general.string(forType: .string),
                      let seekTime = TimecodeFormatter.parseAbsoluteTimecodeToSeconds(
                          clipboardString, item: item, mode: timecodeMode
                      ) else { return }
                let duration = max(item.durationSeconds, 0)
                controller.seekTo(max(0, min(seekTime, duration)))
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadPlayer)) { _ in
                guard WindowManager.shared.isActiveWindow(nsWindow), isMediaLoaded else { return }
                let time = controller.currentPlaybackTime
                controller.preparePlayback(startTime: time, resetAudioSelection: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                guard isMediaLoaded, !isEditingTimecode else { return }
                overlayHideTask?.cancel()
                showOverlay = false
            }
    }
}
