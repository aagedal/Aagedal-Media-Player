// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Main window: drop zone when no file, player when file is loaded.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var controller = PlayerController()
    @StateObject private var windowCoordinator = PlayerWindowCoordinator()
    @StateObject private var overlayController = PlayerOverlayController()
    @State private var timecodeMode: TimecodeDisplayMode = .relative
    @State private var isDropTargeted = false
    @State private var showInspector = false
    @State private var isEditingTimecode = false
    @State private var isTimelineFocused = false
    @State private var timecodeActivationTrigger: String?
    @AppStorage(AppSettings.showCursorHideHint.key)
    private var showCursorHideHint = AppSettings.showCursorHideHint.defaultValue
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var updateBannerDismissed = false
    @State private var scopeWindowController: ScopeWindowController?
    @State private var showScopeOverlay = false
    @AppStorage(AppSettings.scopeBackground.key)
    private var scopeBackground = AppSettings.scopeBackground.defaultValue
    @State private var audioWaveformWindowController: AudioWaveformWindowController?
    @State private var showAudioWaveformOverlay = false
    @StateObject private var audioWaveformGenerator = AudioWaveformGenerator()
    @AppStorage(AppSettings.audioWaveformBackground.key)
    private var audioWaveformBackground = AppSettings.audioWaveformBackground.defaultValue

    private let rightEdgeWidth: CGFloat = 60

    private var isMediaLoaded: Bool { controller.mediaItem != nil }
    private var nsWindow: NSWindow? { windowCoordinator.window }
    private var showOverlay: Bool { overlayController.isVisible }

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
                overlayController: overlayController,
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
                    audioWaveformGenerator: audioWaveformGenerator,
                    item: controller.mediaItem!,
                    showsAudioWaveform: showAudioWaveformOverlay,
                    isEditingTimecode: $isEditingTimecode,
                    isTimelineFocused: $isTimelineFocused,
                    timecodeActivationTrigger: $timecodeActivationTrigger
                )
            } else {
                DropZoneView(isDropTargeted: isDropTargeted, onOpenFile: openFilePanel)
            }

            // Layer 2: export/screenshot feedback (fades with overlay controls)
            MediaOperationFeedbackOverlay(controller: controller)
            .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
            .animation(.easeInOut(duration: 0.3), value: showOverlay)

            // Layer 3: update banner
            if updateChecker.updateAvailable, !updateBannerDismissed {
                UpdateAvailableBanner(
                    updateChecker: updateChecker,
                    isDismissed: $updateBannerDismissed
                )
            }

            // Layer 4: overlay controls
            overlayControls

            // Layer 5: audio waveform overlay (always visible when active, independent of controls)
            if showAudioWaveformOverlay,
               isMediaLoaded,
               controller.mediaItem?.presentationKind != .audioOnly,
               !audioWaveformGenerator.channelImages.isEmpty || audioWaveformGenerator.isGenerating || audioWaveformGenerator.error != nil {
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
                showTrafficLights: overlayController.isWindowHovered && !overlayController.isRightEdgeHovered,
                onWindowAvailable: { window in
                    windowCoordinator.accept(window)
                }
            )
        )
        .onHover { hovering in
            overlayController.setWindowHovered(
                hovering,
                isEditingTimecode: isEditingTimecode
            )
        }
        .inspector(isPresented: $showInspector) {
            if let item = controller.mediaItem {
                MetadataInspectorView(item: item, useMPV: controller.useMPV, isPresented: $showInspector)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            windowCoordinator.handleDrop(providers)
        }
        .onChange(of: controller.screenshotState) { _, state in
            switch state {
            case .succeeded:
                announce("Screenshot saved.")
            case .failed(let message):
                announce(message)
            case .idle, .saving:
                break
            }
        }
        .onChange(of: controller.trimExportState) { _, state in
            switch state {
            case .succeeded:
                announce("Trimmed file saved.")
            case .cancelled:
                announce("Export cancelled.")
            case .failed(let message):
                announce(message)
            case .idle, .warning, .preparing, .exporting, .cancelling:
                break
            }
        }
        .onAppear {
            overlayController.install(
                isMediaLoaded: { controller.mediaItem != nil },
                isPlaying: { controller.isPlaying },
                isEditingTimecode: { isEditingTimecode }
            )
            windowCoordinator.configureWindowOpening { [openWindow] in
                openWindow(id: "player")
            }
        }
        .task {
            await windowCoordinator.consumePendingFile(
                controller: controller,
                onTimecodeModeChange: { timecodeMode = $0 },
                onMetadataLoaded: metadataDidLoad
            )
        }
        .onDisappear {
            overlayController.tearDown()
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
            windowCoordinator.tearDown()
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
                isTimelineFocused: $isTimelineFocused,
                timecodeActivationTrigger: $timecodeActivationTrigger
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .frame(minWidth: 20)
        }
        .onHover { hovering in
            overlayController.setControlsHovered(hovering)
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
            .accessibilityLabel(showInspector ? "Hide metadata inspector" : "Show metadata inspector")
            .accessibilityValue(showInspector ? "Shown" : "Hidden")
            .accessibilityAddTraits(showInspector ? .isSelected : [])
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

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - Cursor Hide Zone

    private var cursorHideZone: some View {
        HStack {
            Spacer()
            ZStack {
                CursorHideZone { hovering in
                    overlayController.setRightEdgeHovered(
                        hovering,
                        isPlaying: { controller.isPlaying },
                        isEditingTimecode: { isEditingTimecode }
                    )
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
                        .opacity(showOverlay && !overlayController.isRightEdgeHovered ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: showOverlay)
                        .animation(.easeInOut(duration: 0.3), value: overlayController.isRightEdgeHovered)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: rightEdgeWidth)
        }
        .padding(.bottom, 80)
    }

    // MARK: - File Opening

    func openFilePanel() {
        windowCoordinator.openFilePanel(
            controller: controller,
            onTimecodeModeChange: { timecodeMode = $0 },
            onMetadataLoaded: metadataDidLoad
        )
    }

    func openFile(url: URL) {
        windowCoordinator.openFile(
            url,
            controller: controller,
            onTimecodeModeChange: { timecodeMode = $0 },
            onMetadataLoaded: metadataDidLoad
        )
    }

    private func metadataDidLoad() {
        if showAudioWaveformOverlay {
            generateAudioWaveform()
        }
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

}
