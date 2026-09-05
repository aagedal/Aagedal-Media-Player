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
    @StateObject private var compareSession = CompareSessionController()
    @StateObject private var windowCoordinator = PlayerWindowCoordinator()
    @StateObject private var overlayController = PlayerOverlayController()
    @State private var timecodeMode: TimecodeDisplayMode = .relative
    @State private var isDropTargeted = false
    @State private var showInspector = false
    @State private var isEditingTimecode = false
    @State private var isTimelineFocused = false
    @State private var isPlaybackControlsFocused = false
    @State private var showReviewNotes = false
    @State private var showCompareModeCallout = false
    @FocusState private var isInspectorButtonFocused: Bool
    @State private var timecodeActivationTrigger: String?
    @AppStorage(AppSettings.showCursorHideHint.key)
    private var showCursorHideHint = AppSettings.showCursorHideHint.defaultValue
    @AppStorage(AppSettings.didShowCompareModeCallout.key)
    private var didShowCompareModeCallout = AppSettings.didShowCompareModeCallout.defaultValue
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
    private var isControlInteractionActive: Bool {
        isEditingTimecode
            || isPlaybackControlsFocused
            || isInspectorButtonFocused
            || showReviewNotes
            || showCompareModeCallout
    }

    private var videoAspectRatio: CGFloat? {
        // Keep one stable comparison canvas. Resizing the window as the view
        // mode changes can make MPV recreate its drawable and reload playback.
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
                compareSession: compareSession,
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
                openFile: openFile,
                openPreviousFile: openPreviousFile,
                openNextFile: openNextFile
            ))
    }

    // MARK: - Content Layers

    private var contentLayers: some View {
        ZStack {
            // Layer 1: content (player or drop zone)
            if let item = controller.mediaItem {
                if compareSession.isActive {
                    ComparePlayerView(
                        primaryController: controller,
                        compareSession: compareSession,
                        primaryWaveformGenerator: audioWaveformGenerator,
                        primaryItem: item,
                        showsAudioWaveform: showAudioWaveformOverlay,
                        isEditingTimecode: $isEditingTimecode,
                        isTimelineFocused: $isTimelineFocused,
                        isOverlayControlFocused: isControlInteractionActive,
                        isTextInputActive: showReviewNotes,
                        timecodeActivationTrigger: $timecodeActivationTrigger
                    )
                } else {
                    PlayerView(
                        controller: controller,
                        audioWaveformGenerator: audioWaveformGenerator,
                        item: item,
                        showsAudioWaveform: showAudioWaveformOverlay,
                        isEditingTimecode: $isEditingTimecode,
                        isTimelineFocused: $isTimelineFocused,
                        isOverlayControlFocused: isControlInteractionActive,
                        isTextInputActive: showReviewNotes,
                        timecodeActivationTrigger: $timecodeActivationTrigger,
                        compareSession: compareSession
                    )
                }
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
        .focusedSceneValue(\.isCompareModeActive, compareSession.isActive)
        .focusedSceneValue(\.canOpenPreviousFile, windowCoordinator.canOpenPreviousFile)
        .focusedSceneValue(\.canOpenNextFile, windowCoordinator.canOpenNextFile)
        .frame(minWidth: 270, minHeight: 200)
        .background(Color.black)
        .background(
            WindowConfigurator(
                aspectRatio: videoAspectRatio,
                videoSourceSize: videoSourceSize,
                showTrafficLights: overlayController.isWindowHovered && !overlayController.isRightEdgeHovered,
                onWindowAvailable: { window in
                    windowCoordinator.accept(
                        window,
                        onClose: { [controller, compareSession, audioWaveformGenerator] in
                            Self.stopPlaybackForWindowClose(
                                controller: controller,
                                compareSession: compareSession,
                                audioWaveformGenerator: audioWaveformGenerator
                            )
                        }
                    )
                }
            )
        )
        .onHover { hovering in
            overlayController.setWindowHovered(
                hovering,
                isControlInteractionActive: isControlInteractionActive
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
        .alert(
            "Compare Mode",
            isPresented: Binding(
                get: { compareSession.loadError != nil },
                set: { if !$0 { compareSession.dismissLoadError() } }
            )
        ) {
            Button("OK") { compareSession.dismissLoadError() }
        } message: {
            Text(compareSession.loadError ?? "The comparison file could not be loaded.")
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
        .onChange(of: compareSession.isActive) { _, isActive in
            if !isActive {
                showReviewNotes = false
            } else {
                showCompareModeCallout = false
            }
        }
        .onChange(of: isMediaLoaded) { _, isLoaded in
            if isLoaded {
                presentCompareModeCalloutIfNeeded()
            } else {
                showCompareModeCallout = false
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
                isKeyWindow: { nsWindow?.isKeyWindow == true },
                isPlaying: { controller.isPlaying },
                isControlInteractionActive: { isControlInteractionActive }
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
                compareSession.secondaryController.frameCapture.stopCapture()
                showScopeOverlay = false
            }
            audioWaveformWindowController?.close()
            audioWaveformWindowController = nil
            showAudioWaveformOverlay = false
            Self.stopPlaybackForWindowClose(
                controller: controller,
                compareSession: compareSession,
                audioWaveformGenerator: audioWaveformGenerator
            )
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
                compareSession: compareSession,
                item: controller.mediaItem,
                timecodeMode: $timecodeMode,
                isEditingTimecode: $isEditingTimecode,
                isTimelineFocused: $isTimelineFocused,
                isControlsFocused: $isPlaybackControlsFocused,
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
            primaryController: controller,
            secondaryController: compareSession.secondaryController,
            primaryFrameCapture: controller.frameCapture,
            secondaryFrameCapture: compareSession.secondaryController.frameCapture,
            compareSession: compareSession,
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
        let comparedChannels = compareSession.availableComparedAudioChannels(primary: controller)
        let overlapStatus = compareSession.overlapStatus(
            primaryDuration: controller.mediaItem?.durationSeconds ?? 0
        )

        return HStack(spacing: 10) {
            TransportSyncStatusView()
            Spacer()

            if compareSession.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading comparison file")

                Button("Cancel") {
                    compareSession.stop()
                }
                .buttonStyle(.plain)
                .help("Cancel loading the comparison file")
                .accessibilityLabel("Cancel loading comparison file")
            } else if compareSession.isActive {
                Picker("Compare view", selection: $compareSession.viewMode) {
                    ForEach(CompareViewMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .help("Choose comparison view. Press B to toggle A/B.")

                Menu {
                    Picker(
                        "Frame resolution",
                        selection: Binding(
                            get: { compareSession.frameResolution },
                            set: { compareSession.setFrameResolution($0, primary: controller) }
                        )
                    ) {
                        ForEach(CompareFrameResolution.allCases, id: \.self) { resolution in
                            Text(resolution.label).tag(resolution)
                        }
                    }
                } label: {
                    Label(
                        compareSession.frameResolution == .full ? "Full" : "½",
                        systemImage: "rectangle.on.rectangle"
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!compareSession.isSecondaryReady)
                .help(
                    "Choose the live comparison render resolution. Reduced Frame can improve playback performance; source files and exports remain full resolution."
                )
                .accessibilityLabel("Comparison frame resolution")
                .accessibilityValue(compareSession.frameResolution.label)

                Picker(
                    "Audio source",
                    selection: Binding(
                        get: { compareSession.audioSource },
                        set: { compareSession.selectAudioSource($0, primary: controller) }
                    )
                ) {
                    ForEach(CompareAudioSource.allCases, id: \.self) { source in
                        Text(source.label)
                            .tag(source)
                            .disabled(
                                source == .secondary
                                    && !compareSession.isSecondaryReady
                            )
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .help("Choose the only comparison source that is audible")
                .accessibilityLabel("Comparison audio source")
                .accessibilityValue(compareSession.audioSource.label)

                Menu {
                    Button {
                        compareSession.selectComparedAudioChannel(nil, primary: controller)
                    } label: {
                        HStack {
                            Text("All Channels")
                            if compareSession.comparedAudioChannel == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(comparedChannels) { channel in
                        Button {
                            compareSession.selectComparedAudioChannel(channel, primary: controller)
                        } label: {
                            HStack {
                                Text(channel.label)
                                if compareSession.comparedAudioChannel?.id == channel.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(
                        compareSession.comparedAudioChannel?.label ?? "All Channels",
                        systemImage: "speaker.wave.2"
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(comparedChannels.isEmpty)
                .help(
                    comparedChannels.isEmpty
                        ? "Matching channel monitoring is unavailable for these audio layouts"
                        : "Monitor all channels or isolate the matching channel in A and B"
                )
                .accessibilityLabel("Compared audio channel")
                .accessibilityValue(compareSession.comparedAudioChannel?.label ?? "All channels")

                Menu {
                    Picker("Safe Area", selection: $compareSession.safeAreaGuide) {
                        ForEach(CompareSafeAreaGuide.allCases, id: \.self) { guide in
                            Text(guide.label).tag(guide)
                        }
                    }

                    Picker("Aspect Ratio", selection: $compareSession.aspectRatioGuide) {
                        ForEach(CompareAspectRatioGuide.allCases, id: \.self) { guide in
                            Text(guide.label).tag(guide)
                        }
                    }
                } label: {
                    Image(
                        systemName: compareSession.safeAreaGuide != .none
                            || compareSession.aspectRatioGuide != .none
                            ? "viewfinder.circle.fill"
                            : "viewfinder.circle"
                    )
                    .foregroundColor(.white.opacity(0.9))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Configure safe-area and aspect-ratio guides shared by both sources")
                .accessibilityLabel("Comparison guides")
                .accessibilityValue(comparisonGuideAccessibilityValue)

                if compareSession.viewMode.isWipe {
                    Slider(
                        value: Binding(
                            get: { compareSession.wipePosition },
                            set: { compareSession.setWipePosition($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                    .frame(width: 110)
                    .help("Wipe position. Drag the divider or press [ and ].")
                    .accessibilityLabel("Wipe position")
                    .accessibilityValue("\(Int(compareSession.wipePosition * 100)) percent")
                } else if compareSession.viewMode == .overlay {
                    Slider(
                        value: Binding(
                            get: { compareSession.overlayBlend },
                            set: { compareSession.setOverlayBlend($0) }
                        ),
                        in: 0...1
                    )
                        .controlSize(.small)
                        .frame(width: 110)
                        .help("Overlay blend: A at the left, B at the right")
                        .accessibilityLabel("Overlay blend")
                        .accessibilityValue("\(Int(compareSession.overlayBlend * 100)) percent source B")
                } else if compareSession.viewMode == .difference {
                    Slider(
                        value: Binding(
                            get: { compareSession.differenceGain },
                            set: { compareSession.setDifferenceGain($0) }
                        ),
                        in: CompareSessionController.minimumDifferenceGain...CompareSessionController.maximumDifferenceGain,
                        step: 0.5
                    )
                        .controlSize(.small)
                        .frame(width: 110)
                        .help("Amplify the post-display RGB difference. This is not an objective image-quality metric.")
                        .accessibilityLabel("Difference gain")
                        .accessibilityValue("\(compareSession.differenceGain.formatted()) times")

                    Text("\(compareSession.differenceGain.formatted())× display-space")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.72))
                        .help("Difference is computed from post-display RGB, not normalized source pixels")
                }

                if showScopeOverlay {
                    Picker("Scope source", selection: $compareSession.scopeSource) {
                        ForEach(CompareScopeSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    .help("Choose whether scopes inspect source A, source B, or their display-space difference")

                    if compareSession.scopeSource == .difference,
                       compareSession.viewMode != .difference {
                        Slider(
                            value: Binding(
                                get: { compareSession.differenceGain },
                                set: { compareSession.setDifferenceGain($0) }
                            ),
                            in: CompareSessionController.minimumDifferenceGain...CompareSessionController.maximumDifferenceGain,
                            step: 0.5
                        )
                        .controlSize(.small)
                        .frame(width: 65)
                        .help("Amplify the display-space scope difference. This is not an objective image-quality metric.")
                        .accessibilityLabel("Scope difference gain")
                        .accessibilityValue("\(compareSession.differenceGain.formatted()) times")

                        Text("\(compareSession.differenceGain.formatted())× Δ")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                if let mapping = compareSession.mapping {
                    CompareAlignmentControl(session: compareSession, primary: controller)
                    Text("\(mapping.mode.label) · \(overlapStatus.label)")
                        .font(.caption)
                        .foregroundStyle(
                            overlapStatus == .none
                                ? Color.yellow
                                : Color.white.opacity(0.72)
                        )
                        .help(
                            overlapStatus == .none
                                ? "The aligned timelines do not overlap. Source B stays parked on its nearest boundary during playback."
                                : "How the source timelines align. The timeline shows the exact B offset and shared playable interval."
                        )
                        .accessibilityLabel("\(mapping.mode.label), \(overlapStatus.label)")
                }

                CompareMismatchIndicator(
                    primaryController: controller,
                    secondaryController: compareSession.secondaryController,
                    isActive: compareSession.isActive
                )

                Button(action: { showReviewNotes.toggle() }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 15))
                        if !compareSession.reviewNotes.isEmpty {
                            Text("\(compareSession.reviewNotes.count)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(2)
                                .background(.orange, in: Circle())
                                .offset(x: 7, y: -7)
                        }
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Add or edit frame-accurate comparison notes")
                .accessibilityLabel("Comparison review notes")
                .accessibilityValue("\(compareSession.reviewNotes.count) notes")
                .popover(isPresented: $showReviewNotes, arrowEdge: .bottom) {
                    CompareReviewView(
                        primaryController: controller,
                        compareSession: compareSession,
                        timecodeMode: timecodeMode
                    )
                }

                Button(action: { compareSession.captureComparisonStill(primary: controller) }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Export an annotated comparison still (Command-S)")
                .accessibilityLabel("Export comparison still")
                .disabled(!compareSession.isSecondaryReady)

                Button(action: openCompareFilePanel) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Replace comparison file")
                .accessibilityLabel("Replace comparison file")

                Button(action: {
                    showReviewNotes = false
                    compareSession.stop()
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Exit Compare Mode")
                .accessibilityLabel("Exit Compare Mode")
            } else {
                Button(action: openCompareFilePanel) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Add comparison file")
                .accessibilityLabel("Add comparison file")
                .disabled(controller.mediaItem == nil || compareSession.isLoading)
                .popover(isPresented: $showCompareModeCallout, arrowEdge: .top) {
                    compareModeCallout
                }
            }

            Button(action: { showInspector.toggle() }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .focused($isInspectorButtonFocused)
            .overlay {
                if isInspectorButtonFocused {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(1)
                        .allowsHitTesting(false)
                }
            }
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

    private var comparisonGuideAccessibilityValue: String {
        let safeArea = compareSession.safeAreaGuide == .none
            ? nil
            : compareSession.safeAreaGuide.label
        let aspectRatio = compareSession.aspectRatioGuide == .none
            ? nil
            : compareSession.aspectRatioGuide.label
        let labels = [safeArea, aspectRatio].compactMap { $0 }
        return labels.isEmpty ? "Off" : labels.joined(separator: ", ")
    }

    private var compareModeCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Compare two masters", systemImage: "rectangle.split.2x1")
                .font(.headline)

            Text(
                "Add source B to align it with this file, then inspect both with "
                    + "A/B switching, wipes, overlays, difference view, and one shared transport."
            )
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("Got It") {
                    showCompareModeCallout = false
                }

                Button("Choose Source B\u{2026}") {
                    showCompareModeCallout = false
                    DispatchQueue.main.async {
                        openCompareFilePanel()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func presentCompareModeCalloutIfNeeded() {
        guard isMediaLoaded,
              !compareSession.isActive,
              !didShowCompareModeCallout else { return }
        didShowCompareModeCallout = true
        showCompareModeCallout = true
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private static func stopPlaybackForWindowClose(
        controller: PlayerController,
        compareSession: CompareSessionController,
        audioWaveformGenerator: AudioWaveformGenerator
    ) {
        audioWaveformGenerator.cancel()
        if compareSession.isActive {
            compareSession.pause(primary: controller)
        }
        compareSession.stop()
        controller.cancelMediaOperationsForWindowClose()
        controller.teardown()
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
                        isControlInteractionActive: { isControlInteractionActive }
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
        windowCoordinator.openFilePanel(onSelection: openFile(url:))
    }

    func openFile(url: URL) {
        showReviewNotes = false
        if compareSession.isActive {
            compareSession.pause(primary: controller)
        }
        compareSession.stop()
        windowCoordinator.openFile(
            url,
            controller: controller,
            onTimecodeModeChange: { timecodeMode = $0 },
            onMetadataLoaded: metadataDidLoad
        )
    }

    func openPreviousFile() {
        guard let url = windowCoordinator.previousMediaURL() else { return }
        openFile(url: url)
    }

    func openNextFile() {
        guard let url = windowCoordinator.nextMediaURL() else { return }
        openFile(url: url)
    }

    private func metadataDidLoad() {
        if showAudioWaveformOverlay {
            generateAudioWaveform()
        }
    }

    private func openCompareFilePanel() {
        guard controller.mediaItem != nil else { return }
        didShowCompareModeCallout = true
        showCompareModeCallout = false
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = PlayerWindowCoordinator.supportedMediaTypes
        panel.message = "Choose a file to compare with source A"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        compareSession.loadSecondary(url, alignedWith: controller)
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
