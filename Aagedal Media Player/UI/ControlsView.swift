// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Bottom controls bar with timeline, transport, timecode, audio/subtitle pickers.

import SwiftUI
import AVFoundation

private enum PlaybackControlFocus: Hashable {
    case timeline
    case timelineZoom
    case timelineOverview
    case timelineFit
    case playPause
    case mute
    case volume
    case audioTrack
    case subtitles
    case chapters
    case loop
    case fullscreen
    case timecode
    case timecodeEditor
}

private struct PlaybackControlFocusRing: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ControlsView: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    let item: MediaItem?
    @Binding var timecodeMode: TimecodeDisplayMode
    @Binding var isEditingTimecode: Bool
    @Binding var isTimelineFocused: Bool
    @Binding var isControlsFocused: Bool
    @Binding var timecodeActivationTrigger: String?

    @AppStorage(AppSettings.audioWaveformColor.key)
    private var waveformColorRaw = AppSettings.audioWaveformColor.defaultValue
    @AppStorage(AppSettings.precisionScrubFactor.key)
    private var precisionScrubFactor = AppSettings.precisionScrubFactor.defaultValue
    @AppStorage(AppSettings.showTimelineDetails.key)
    private var showTimelineDetails = AppSettings.showTimelineDetails.defaultValue
    @StateObject private var timelineThumbnail = TimelineThumbnailLoader()
    @State private var thumbnailHoverX: CGFloat?
    @State private var timelineZoom: Double = 1
    @State private var timelineCenter: Double = 0
    @State private var isPanningOverview = false
    @State private var isDragging = false
    @State private var dragTime: Double = 0
    @State private var wasPrecision = false
    @State private var precisionAnchorFraction: Double = 0
    @State private var precisionAnchorX: CGFloat = 0
    @State private var timecodeInput = ""
    @State private var pendingCharacter: String?
    @State private var justActivated = false
    @State private var isNarrow = false
    @State private var deferredTimecodeActivation = DeferredMainActorTask()
    @FocusState private var focusedControl: PlaybackControlFocus?

    private var isLoaded: Bool { item != nil }

    private var displayTime: Double {
        isDragging ? dragTime : controller.currentPlaybackTime
    }

    private var isPlaying: Bool { controller.isPlaying }

    private var audioController: PlayerController {
        if compareSession.isActive, compareSession.audioSource == .secondary {
            return compareSession.secondaryController
        }
        return controller
    }

    var body: some View {
        VStack(spacing: 8) {
            if let item,
               showTimelineDetails,
               compareSession.isActive,
               let mapping = compareSession.mapping {
                comparisonTimelineLegend(mapping: mapping, item: item)
            }

            timelineNavigation

            // Timeline scrubber
            timelineSlider

            // Controls row — responsive layout
            if isNarrow {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        primaryTransportControls
                    }
                    HStack(spacing: 8) {
                        secondaryTransportControls
                    }
                    timecodeDisplay
                }
            } else {
                HStack(spacing: 12) {
                    primaryTransportControls
                    secondaryTransportControls
                    Spacer()
                    timecodeDisplay
                }
            }
        }
        .disabled(!isLoaded)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .onAppear { isNarrow = geo.size.width < 495 }
                    .onChange(of: geo.size.width) { _, newWidth in isNarrow = newWidth < 495 }
            }
            .allowsHitTesting(false)
        )
        .onChange(of: timecodeActivationTrigger) { _, newValue in
            if let text = newValue {
                startTimecodeEdit(withInitialText: text)
                timecodeActivationTrigger = nil
            }
        }
        .onChange(of: focusedControl) { _, focus in
            isTimelineFocused = focus == .timeline || focus == .timelineOverview
            isControlsFocused = focus != nil
        }
        .onChange(of: item?.id) { _, _ in
            timelineThumbnail.hide(clearCache: true)
            thumbnailHoverX = nil
            timelineZoom = 1
            timelineCenter = 0
            isPanningOverview = false
            isDragging = false
            wasPrecision = false
        }
        .onChange(of: controller.currentPlaybackTime) { _, time in
            if !isDragging, !isPanningOverview, !timelineViewport.contains(time) {
                timelineCenter = time
            }
        }
        .onChange(of: showTimelineDetails) { _, visible in
            if !visible { timelineThumbnail.hide(); thumbnailHoverX = nil }
        }
        .onChange(of: timelineViewport) { _, _ in
            // Zoom, panning, and playhead following change the time under a
            // stationary pointer. Never retain a preview from the old mapping.
            timelineThumbnail.hide()
            thumbnailHoverX = nil
        }
        .onDisappear {
            timelineThumbnail.hide(clearCache: true)
            deferredTimecodeActivation.cancel()
            isPanningOverview = false
            isTimelineFocused = false
            isControlsFocused = false
        }
    }

    // MARK: - Transport Buttons

    @ViewBuilder
    private var primaryTransportControls: some View {
        // Play/Pause
        Button(action: togglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16))
                .foregroundColor((AudioWaveformColor(rawValue: waveformColorRaw) ?? .pink).swiftUIColor)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: .playPause)
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .playPause))
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityValue(isPlaying ? "Playing" : "Paused")

        Divider()
            .frame(height: 18)

        volumeControl

        if !isNarrow {
            Divider()
                .frame(height: 18)
        }
    }

    @ViewBuilder
    private var secondaryTransportControls: some View {
        // Audio track picker
        audioTrackPicker

        // Subtitle track picker
        subtitleTrackPicker

        // Chapter picker (only when chapters exist)
        if !controller.chapterOptions.isEmpty {
            chapterPicker
        }

        // Loop toggle
        Button(action: {
            if let item = item {
                if compareSession.isActive {
                    compareSession.setLoopPlayback(!item.loopPlayback, primary: controller)
                } else {
                    controller.updateLoopPlayback(!item.loopPlayback)
                }
            }
        }) {
            Image(systemName: (item?.loopPlayback ?? false) ? "repeat.1" : "repeat")
                .font(.system(size: 14))
                .foregroundColor((item?.loopPlayback ?? false) ? .accentColor : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: .loop)
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .loop))
        .help((item?.loopPlayback ?? false) ? "Disable loop" : "Enable loop")
        .accessibilityLabel("Loop playback")
        .accessibilityValue((item?.loopPlayback ?? false) ? "On" : "Off")
        .accessibilityAddTraits((item?.loopPlayback ?? false) ? .isSelected : [])

        // Fullscreen
        Button(action: { controller.toggleFullscreen() }) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: .fullscreen)
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .fullscreen))
        .help("Toggle fullscreen")
        .accessibilityLabel("Toggle fullscreen")
    }

    private var volumeControl: some View {
        HStack(spacing: 5) {
            Button(action: toggleMute) {
                Image(systemName: volumeSymbolName)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .mute)
            .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .mute))
            .help(controller.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { controller.volume },
                    set: { volume in
                        if compareSession.isActive {
                            compareSession.setMonitoringVolume(volume, primary: controller)
                        } else {
                            controller.volume = volume
                        }
                    }
                ),
                in: 0...100,
                step: 1
            )
            .frame(width: isNarrow ? 54 : 72)
            .focused($focusedControl, equals: .volume)
            .help("Volume: \(Int(controller.volume)) percent")
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int(controller.volume)) percent")
        }
    }

    private var volumeSymbolName: String {
        if controller.isMuted || controller.volume == 0 { return "speaker.slash.fill" }
        if controller.volume < 34 { return "speaker.wave.1.fill" }
        if controller.volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Timeline

    private var timelineViewport: TimelineViewport {
        TimelineViewport(
            duration: item?.durationSeconds ?? 0,
            zoom: timelineZoom,
            center: timelineCenter
        )
    }

    private var timelineNavigation: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([1, 2, 4, 8, 16, 32, 64], id: \.self) { zoom in
                    Button(zoom == 1 ? "Fit Entire Timeline" : "\(zoom)× Around Playhead") {
                        timelineCenter = displayTime
                        timelineZoom = Double(zoom)
                    }
                }
            } label: {
                Label(timelineZoom == 1 ? "Fit" : "\(Int(timelineZoom))×", systemImage: "plus.magnifyingglass")
                    .font(.caption)
            }
            .fixedSize()
            .focused($focusedControl, equals: .timelineZoom)
            .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .timelineZoom))
            .accessibilityLabel("Timeline zoom")
            .accessibilityValue(timelineZoom == 1 ? "Entire duration" : "\(Int(timelineZoom)) times")
            .help("Zoom around the playhead, or fit the entire duration.")

            if timelineZoom > 1 {
                timelineOverview
                Button("Fit") {
                    timelineZoom = 1
                    focusedControl = .timelineZoom
                }
                    .font(.caption)
                    .focused($focusedControl, equals: .timelineFit)
                    .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .timelineFit))
                    .help("Show the entire timeline")
                    .accessibilityLabel("Fit entire timeline")
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    /// Panning this full-duration overview changes only the visible interval.
    /// Playback/seek updates reveal the playhead if it leaves that interval.
    private var timelineOverview: some View {
        GeometryReader { geometry in
            let viewport = timelineViewport
            let full = TimelineViewport(duration: viewport.duration)
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor))
                    .frame(width: max(1, width / viewport.zoom), height: 12)
                    .offset(x: width * full.fraction(for: viewport.start))
                Rectangle().fill(.pink).frame(width: 2, height: 12)
                    .offset(x: max(0, min(width - 2, width * full.fraction(for: displayTime))))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard width > 0 else { return }
                    isPanningOverview = true
                    focusedControl = .timelineOverview
                    timelineCenter = full.time(at: value.location.x / width)
                }
                .onEnded { _ in isPanningOverview = false }
            )
            .focusable()
            .focused($focusedControl, equals: .timelineOverview)
            .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .timelineOverview))
            .onKeyPress(.leftArrow) { panTimeline(-1); return .handled }
            .onKeyPress(.rightArrow) { panTimeline(1); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timeline overview")
            .accessibilityValue("Visible seconds \(viewport.start.formatted(.number.precision(.fractionLength(1)))) to \(viewport.end.formatted(.number.precision(.fractionLength(1)))) of \(viewport.duration.formatted(.number.precision(.fractionLength(1))))")
            .accessibilityHint("Use Left and Right Arrow to move the visible interval without seeking.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: panTimeline(1)
                case .decrement: panTimeline(-1)
                @unknown default: break
                }
            }
            .help("Full-duration overview. Drag to move the visible interval without seeking.")
        }
        .frame(height: 20)
    }

    private func panTimeline(_ direction: Double) {
        let viewport = timelineViewport
        timelineCenter = TimelineViewport(
            duration: viewport.duration,
            zoom: viewport.zoom,
            center: viewport.center + direction * viewport.span / 2
        ).center
    }

    private func comparisonTimelineLegend(
        mapping: CompareTimelineMapping,
        item: MediaItem
    ) -> some View {
        let status = compareSession.overlapStatus(
            primaryDuration: item.durationSeconds
        )
        let frameRate = item.metadata?.primaryVideoStream?.frameRate?.value
        let dropFrame = item.metadata?.timecode?.contains(";") ?? false
        let offsetLabel = mapping.offsetLabel(
            primaryFrameRate: frameRate,
            dropFrame: dropFrame
        )
        let statusColor: Color
        let statusHelp: String
        switch status {
        case .none:
            statusColor = .yellow
            statusHelp = "The sources have no playable overlap. Source B stays parked on its nearest boundary."
        case .unknown:
            statusColor = .secondary
            statusHelp = "The shared interval is unavailable until both source durations are known."
        case .full, .partial:
            statusColor = .cyan
            statusHelp = "The cyan interval is playable in both sources. The equation shows how A's relative time maps to B."
        }

        return HStack(spacing: 6) {
            Capsule()
                .fill(statusColor)
                .frame(width: 18, height: 4)

            Text(status.label)
                .foregroundStyle(statusColor)

            Spacer(minLength: 8)

            Text(offsetLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .lineLimit(1)
        .help(statusHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.label). \(offsetLabel)")
    }

    private var timelineSlider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let duration = item?.durationSeconds ?? 0
            let viewport = timelineViewport
            let progress = viewport.fraction(for: displayTime)

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)

                // Compare overlap is expressed on A's authoritative timeline.
                // Outside this interval B is held on its nearest boundary, so
                // showing it here makes that transport behavior predictable.
                if showTimelineDetails,
                   compareSession.isActive,
                   duration > 0,
                   let overlap = compareSession.primaryOverlapRange(
                       primaryDuration: duration
                   ), let visibleOverlap = viewport.clipped(overlap) {
                    let overlapStart = CGFloat(viewport.fraction(for: visibleOverlap.lowerBound))
                    let overlapEnd = CGFloat(viewport.fraction(for: visibleOverlap.upperBound))

                    Capsule()
                        .fill(Color.cyan.opacity(0.7))
                        .frame(
                            width: max(0, (overlapEnd - overlapStart) * width),
                            height: 6
                        )
                        .offset(x: overlapStart * width)
                        .allowsHitTesting(false)

                    if overlap.lowerBound > 0, viewport.contains(overlap.lowerBound) {
                        comparisonOverlapBoundary(
                            x: overlapStart * width,
                            width: width
                        )
                    }
                    if overlap.upperBound < duration, viewport.contains(overlap.upperBound) {
                        comparisonOverlapBoundary(
                            x: overlapEnd * width,
                            width: width
                        )
                    }
                }

                // Trim region overlay
                if duration > 0 {
                    let trimInFrac = controller.trimIn.map { CGFloat(viewport.fraction(for: $0)) } ?? 0
                    let trimOutFrac = controller.trimOut.map { CGFloat(viewport.fraction(for: $0)) } ?? 1

                    if controller.trimIn != nil || controller.trimOut != nil {
                        // Shaded region between trim points
                        Rectangle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: max(0, (trimOutFrac - trimInFrac) * width), height: 6)
                            .offset(x: trimInFrac * width)
                    }

                    // Trim-in marker
                    if let trimIn = controller.trimIn, viewport.contains(trimIn) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 2, height: 14)
                            .offset(x: max(0, min(width - 2, trimInFrac * width - 1)))
                    }

                    // Trim-out marker
                    if let trimOut = controller.trimOut, viewport.contains(trimOut) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 2, height: 14)
                            .offset(x: max(0, min(width - 2, trimOutFrac * width - 1)))
                    }

                    // Review markers are display-only here so the timeline's
                    // zero-distance scrub gesture remains unambiguous. The
                    // Review popover provides selection, editing, and delete.
                    if showTimelineDetails {
                        ForEach(compareSession.filteredReviewNotes) { note in
                            let noteTime = item.map {
                                compareSession.reviewNotePrimaryTime(note, primaryItem: $0)
                            } ?? note.primaryTime
                            let markerFraction = CGFloat(viewport.fraction(for: noteTime))
                            if let endFrame = note.primaryEndFrame {
                                let rate = Double(note.primaryRateNumerator) / Double(note.primaryRateDenominator)
                                let endTime = min(duration, (Double(endFrame) + 1) / rate)
                                let startX = max(0, min(width, markerFraction * width))
                                let endX = max(startX, min(width, CGFloat(viewport.fraction(for: endTime)) * width))
                                Rectangle()
                                    .fill(Color.orange.opacity(0.3))
                                    .frame(width: endX - startX, height: 8)
                                    .offset(x: startX)
                                    .allowsHitTesting(false)
                            }
                            if viewport.contains(noteTime) {
                                Capsule()
                                    .fill(Color.orange)
                                    .frame(width: 3, height: 14)
                                    .offset(x: max(0, min(width - 3, markerFraction * width - 1.5)))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }

                if showTimelineDetails {
                    ChapterTimelineMarkers(
                        chapters: controller.chapterOptions,
                        duration: duration,
                        width: width,
                        viewport: viewport
                    )
                }

                // Playhead — thin vertical line
                if viewport.contains(displayTime) {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.071, blue: 0.361)) // #FF125C
                        .frame(width: 2, height: 14)
                        .offset(x: max(0, min(width - 2, width * CGFloat(progress) - 1)))
                }
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0, viewport.span > 0 else { return }
                        if !isDragging {
                            focusedControl = .timeline
                            isDragging = true
                            timelineThumbnail.hide()
                            thumbnailHoverX = nil
                            wasPrecision = false
                            // Jump to click position
                            let clickFraction = max(0, min(1, value.location.x / width))
                            dragTime = viewport.time(at: Double(clickFraction))
                        }
                        let isPrecision = NSEvent.modifierFlags.contains(.option)
                        if isPrecision {
                            if !wasPrecision {
                                // Entering precision: anchor at current playhead position
                                precisionAnchorFraction = viewport.fraction(for: dragTime)
                                precisionAnchorX = value.location.x
                                wasPrecision = true
                            }
                            let delta = (value.location.x - precisionAnchorX) / width
                            let fraction = max(0, min(1, precisionAnchorFraction + delta / precisionScrubFactor))
                            dragTime = viewport.time(at: Double(fraction))
                        } else {
                            wasPrecision = false
                            let fraction = max(0, min(1, value.location.x / width))
                            dragTime = viewport.time(at: Double(fraction))
                        }
                        scrub(to: dragTime)
                    }
                    .onEnded { value in
                        guard width > 0, viewport.span > 0 else { return }
                        let isPrecision = NSEvent.modifierFlags.contains(.option)
                        if isPrecision && wasPrecision {
                            let delta = (value.location.x - precisionAnchorX) / width
                            let fraction = max(0, min(1, precisionAnchorFraction + delta / precisionScrubFactor))
                            dragTime = viewport.time(at: Double(fraction))
                        } else {
                            let fraction = max(0, min(1, value.location.x / width))
                            dragTime = viewport.time(at: Double(fraction))
                        }
                        endScrubbing(at: dragTime)
                        isDragging = false
                        wasPrecision = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard showTimelineDetails, !isDragging, width > 0,
                          let item, item.hasVideoStream else { return }
                    thumbnailHoverX = max(0, min(width, location.x))
                    timelineThumbnail.request(item: item, time: viewport.time(at: location.x / width))
                case .ended:
                    thumbnailHoverX = nil
                    timelineThumbnail.hide()
                }
            }
            .overlay(alignment: .topLeading) {
                if let x = thumbnailHoverX, let preview = timelineThumbnail.image,
                   let time = timelineThumbnail.imageTime, let item {
                    VStack(spacing: 4) {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 90)
                        Text("≈ " + TimecodeFormatter.formatTimeForDisplayWithMode(
                            seconds: time, item: item, mode: timecodeMode
                        ))
                        .font(.caption.monospacedDigit())
                    }
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: max(0, min(max(0, width - 172), x - 86)), y: -126)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .focusable()
            .focused($focusedControl, equals: .timeline)
            .onKeyPress(.leftArrow) {
                adjustTimeline(byFrames: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                adjustTimeline(byFrames: 1)
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue(timelineAccessibilityValue)
            .accessibilityHint("Use Left and Right Arrow to seek one frame.")
            .help(!showTimelineDetails || controller.chapterOptions.isEmpty
                  ? "Drag to seek. Hold Option for precision scrubbing."
                  : "Diamonds mark chapters. Use the Chapters menu to jump to a chapter. Hold Option for precision scrubbing.")
            .contextMenu {
                Toggle("Show Timeline Details", isOn: $showTimelineDetails)
                if compareSession.isActive {
                    Divider()
                    Button("Previous Matching Note") {
                        compareSession.seekToAdjacentReviewNote(.previous, primary: controller)
                    }
                    .disabled(compareSession.adjacentReviewNote(.previous, primary: controller) == nil)
                    Button("Next Matching Note") {
                        compareSession.seekToAdjacentReviewNote(.next, primary: controller)
                    }
                    .disabled(compareSession.adjacentReviewNote(.next, primary: controller) == nil)
                }
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    adjustTimeline(byFrames: 1)
                case .decrement:
                    adjustTimeline(byFrames: -1)
                @unknown default:
                    break
                }
            }
            .overlay {
                if focusedControl == .timeline {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .frame(height: 20)
    }

    private var timelineAccessibilityValue: String {
        guard let item else { return "No media loaded" }
        let current = TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: displayTime,
            item: item,
            mode: timecodeMode
        )
        let duration = TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: item.durationSeconds,
            item: item,
            mode: timecodeMode,
            isDuration: true
        )
        let chapterTitle = controller.chapterOptions.last {
            $0.time.isFinite && $0.time <= displayTime + 0.001
        }?.title
        let playbackValue = "\(current) of \(duration)" + (chapterTitle.map { ". Chapter: \($0)" } ?? "")
        guard compareSession.isActive else {
            return playbackValue
        }
        guard let overlap = compareSession.primaryOverlapRange(
            primaryDuration: item.durationSeconds
        ) else {
            return compareSession.overlapStatus(primaryDuration: item.durationSeconds) == .none
                ? "\(playbackValue). No comparison overlap"
                : playbackValue
        }
        let dropFrame = item.metadata?.timecode?.contains(";") ?? false
        let rate = TimecodeFormatter.effectiveTimecodeRate(
            for: item,
            dropFrame: dropFrame
        )
        let overlapStartFrames = rate.frameCount(forSeconds: overlap.lowerBound) ?? 0
        let overlapEndFrames = rate.frameCount(forSeconds: overlap.upperBound) ?? 0
        let overlapStart = rate.timecode(forFrameCount: overlapStartFrames)
        let overlapEnd = rate.timecode(forFrameCount: overlapEndFrames)
        return "\(playbackValue). Comparison overlap \(overlapStart) to \(overlapEnd)"
    }

    private func comparisonOverlapBoundary(x: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.cyan)
            .frame(width: 2, height: 12)
            .offset(x: max(0, min(width - 2, x - 1)))
            .allowsHitTesting(false)
    }

    private func adjustTimeline(byFrames frameCount: Int) {
        guard isLoaded else { return }
        if compareSession.isActive {
            compareSession.seekByFrames(primary: controller, frameCount: frameCount)
        } else {
            controller.seekByFrames(frameCount)
        }
    }

    // MARK: - Timecode Display

    private var timecodeDisplay: some View {
        Group {
            if isEditingTimecode {
                timecodeEditor
            } else {
                timecodeReadonly
            }
        }
    }

    private var timecodeReadonly: some View {
        HStack(spacing: 4) {
            if let item = item {
                Text(timecodeMode.prefix)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: displayTime,
                    item: item,
                    mode: timecodeMode
                ))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

                Text("/")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: item.durationSeconds,
                    item: item,
                    mode: timecodeMode,
                    isDuration: true
                ))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            } else {
                Text("00:00:00:00")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("/")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("00:00:00:00")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            cycleTimecodeMode()
        }
        .onTapGesture(count: 2) {
            guard isLoaded else { return }
            startTimecodeEdit()
        }
        .help("Click to cycle mode, double-click or type numbers to edit")
        .focusable()
        .focused($focusedControl, equals: .timecode)
        .onKeyPress(.space) {
            cycleTimecodeMode()
            return .handled
        }
        .onKeyPress(.return) {
            cycleTimecodeMode()
            return .handled
        }
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .timecode))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timecode")
        .accessibilityValue(timelineAccessibilityValue)
        .accessibilityHint("Activate to cycle display mode. Enter a timecode by typing numbers.")
        .accessibilityAction {
            cycleTimecodeMode()
        }
    }

    private var timecodeEditor: some View {
        TextField("0:00 or +10", text: $timecodeInput)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .textFieldStyle(.plain)
            .frame(width: 140)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.1))
            .cornerRadius(4)
            .focused($focusedControl, equals: .timecodeEditor)
            .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .timecodeEditor))
            .onSubmit {
                seekToTimecode()
            }
            .onExitCommand {
                cancelTimecodeEdit()
            }
    }

    // MARK: - Timecode Edit Methods

    private func cycleTimecodeMode() {
        guard isLoaded else { return }
        let hasSourceTC = item.flatMap { TimecodeFormatter.effectiveStartTimecode(for: $0) } != nil
        timecodeMode.toggle(hasSourceTimecode: hasSourceTC)
    }

    private func startTimecodeEdit() {
        guard let item = item else { return }
        deferredTimecodeActivation.cancel()
        timecodeInput = TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: controller.currentPlaybackTime,
            item: item,
            mode: timecodeMode
        )
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingTimecode = true
        }
        focusedControl = .timecodeEditor
    }

    private func startTimecodeEdit(withInitialText text: String) {
        timecodeInput = ""
        pendingCharacter = text
        justActivated = true

        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingTimecode = true
        }

        deferredTimecodeActivation.scheduleAsync(after: .milliseconds(50)) {
            guard isEditingTimecode, justActivated else { return }
            focusedControl = .timecodeEditor

            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  isEditingTimecode,
                  justActivated,
                  let char = pendingCharacter else { return }
            timecodeInput = char
            pendingCharacter = nil
            justActivated = false
        }
    }

    private func cancelTimecodeEdit() {
        deferredTimecodeActivation.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingTimecode = false
        }
        focusedControl = nil
        timecodeInput = ""
        justActivated = false
        pendingCharacter = nil
    }

    private func seekToTimecode() {
        justActivated = false
        pendingCharacter = nil

        guard let seekTime = parseTimecodeToSeconds(timecodeInput) else {
            cancelTimecodeEdit()
            return
        }

        let duration = max(item?.durationSeconds ?? 0, 0)
        let clampedTime = max(0, min(seekTime, duration))
        seek(to: clampedTime)
        cancelTimecodeEdit()
    }

    // MARK: - Timecode Parsing

    private func parseTimecodeToSeconds(_ timecode: String) -> Double? {
        guard let item = item else { return nil }
        return TimecodeFormatter.parseInputToSeconds(
            timecode,
            item: item,
            mode: timecodeMode,
            currentSeconds: controller.currentPlaybackTime,
            duration: item.durationSeconds
        )
    }

    // MARK: - Audio Track Picker

    private var audioTrackPicker: some View {
        AudioTrackPicker(
            controller: audioController,
            sourceName: compareSession.isActive
                ? (compareSession.audioSource == .primary ? "source A" : "source B")
                : nil,
            showsWaveformOption: !compareSession.isActive || compareSession.audioSource == .primary,
            showsChannelControls: !compareSession.isActive,
            onSelect: { position in
                if compareSession.isActive {
                    compareSession.selectAudioTrack(
                        at: position,
                        for: compareSession.audioSource,
                        primary: controller
                    )
                } else {
                    controller.selectAudioTrack(at: position)
                }
            }
        )
        .frame(width: 28)
        .focused($focusedControl, equals: .audioTrack)
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .audioTrack))
    }

    // MARK: - Subtitle Track Picker

    private var subtitleTrackPicker: some View {
        Menu {
            Button(action: { controller.selectSubtitleTrack(at: -1) }) {
                HStack {
                    Text("Off")
                    if controller.selectedSubtitleTrackOrderIndex < 0 {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(controller.subtitleTrackOptions) { option in
                Button(action: { controller.selectSubtitleTrack(at: option.position) }) {
                    HStack {
                        Text(option.title)
                        if option.position == controller.selectedSubtitleTrackOrderIndex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .focused($focusedControl, equals: .subtitles)
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .subtitles))
        .help("Subtitles")
        .accessibilityLabel("Subtitles")
        .accessibilityValue(selectedSubtitleTrackTitle)
    }

    // MARK: - Chapter Picker

    private var chapterPicker: some View {
        Menu {
            ForEach(controller.chapterOptions) { option in
                Button(action: { seek(to: option.time) }) {
                    HStack {
                        Text("\(formatChapterTime(option.time))  \(option.title)")
                        if option.position == controller.currentChapterPosition {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .focused($focusedControl, equals: .chapters)
        .modifier(PlaybackControlFocusRing(isFocused: focusedControl == .chapters))
        .help("Chapters")
        .accessibilityLabel("Chapters")
        .accessibilityValue(selectedChapterTitle)
    }

    private func formatChapterTime(_ t: Double) -> String {
        let s = max(0, Int(t))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private func toggleMute() {
        if compareSession.isActive {
            compareSession.toggleMonitoringMute(primary: controller)
        } else {
            controller.toggleMute()
        }
    }

    private var selectedSubtitleTrackTitle: String {
        guard controller.selectedSubtitleTrackOrderIndex >= 0 else { return "Off" }
        return controller.subtitleTrackOptions.first {
            $0.position == controller.selectedSubtitleTrackOrderIndex
        }?.title ?? "Off"
    }

    private var selectedChapterTitle: String {
        guard let position = controller.currentChapterPosition else { return "No chapter selected" }
        return controller.chapterOptions.first { $0.position == position }?.title ?? "No chapter selected"
    }

    // MARK: - Compare-aware transport

    private func togglePlayback() {
        if compareSession.isActive {
            compareSession.togglePlayback(primary: controller)
        } else {
            controller.togglePlayback()
        }
    }

    private func seek(to time: TimeInterval) {
        if compareSession.isActive {
            compareSession.seek(primary: controller, to: time)
        } else {
            controller.seekTo(time)
        }
    }

    private func scrub(to time: TimeInterval) {
        if compareSession.isActive {
            compareSession.scrub(primary: controller, to: time)
        } else {
            controller.scrub(to: time)
        }
    }

    private func endScrubbing(at time: TimeInterval) {
        if compareSession.isActive {
            compareSession.endScrubbing(primary: controller, at: time)
        } else {
            controller.endScrubbing(at: time)
        }
    }
}

private struct AudioTrackPicker: View {
    @ObservedObject var controller: PlayerController
    let sourceName: String?
    let showsWaveformOption: Bool
    let showsChannelControls: Bool
    let onSelect: (Int) -> Void

    private var label: String {
        sourceName.map { "Audio track for \($0)" } ?? "Audio track"
    }

    private var selectedTitle: String {
        controller.audioTrackOptions.first {
            $0.position == controller.selectedAudioTrackOrderIndex
        }?.title ?? "Default"
    }

    var body: some View {
        Menu {
            ForEach(controller.audioTrackOptions) { option in
                Button(action: { onSelect(option.position) }) {
                    HStack {
                        Text(option.title)
                        if option.position == controller.selectedAudioTrackOrderIndex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if showsWaveformOption, controller.isMultiMonoFile {
                Divider()
                Button(action: { controller.showAllMonoWaveforms.toggle() }) {
                    HStack {
                        Text("Show All Waveforms")
                        if controller.showAllMonoWaveforms {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if showsChannelControls, controller.selectedAudioChannelLabels.count > 1 {
                Divider()
                Menu("Channel Monitoring") {
                    Button {
                        controller.clearAudioChannelRouting()
                    } label: {
                        HStack {
                            Text("All Channels")
                            if controller.audioChannelRouting.isBypassed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Menu("Solo") {
                        ForEach(Array(controller.selectedAudioChannelLabels.enumerated()), id: \.offset) { channel, name in
                            Button {
                                controller.toggleAudioChannelSolo(channel)
                            } label: {
                                HStack {
                                    Text(name)
                                    if controller.audioChannelRouting.soloedChannels == [channel] {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Menu("Mute") {
                        ForEach(Array(controller.selectedAudioChannelLabels.enumerated()), id: \.offset) { channel, name in
                            Button {
                                controller.toggleAudioChannelMute(channel)
                            } label: {
                                HStack {
                                    Text(name)
                                    if controller.audioChannelRouting.mutedChannels.contains(channel) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(selectedTitle)
    }
}
