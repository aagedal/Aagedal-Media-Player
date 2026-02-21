// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Bottom controls bar with timeline, transport, timecode, audio/subtitle pickers.

import SwiftUI
import AVFoundation

struct ControlsView: View {
    @ObservedObject var controller: PlayerController
    let item: MediaItem?
    @Binding var timecodeMode: TimecodeDisplayMode
    @Binding var isEditingTimecode: Bool
    @Binding var timecodeActivationTrigger: String?

    @State private var isDragging = false
    @State private var dragTime: Double = 0
    @State private var wasPrecision = false
    @State private var precisionAnchorFraction: Double = 0
    @State private var precisionAnchorX: CGFloat = 0
    @State private var timecodeInput = ""
    @State private var pendingCharacter: String?
    @State private var justActivated = false
    @State private var isNarrow = false
    @FocusState private var isTimecodeFocused: Bool

    private var isLoaded: Bool { item != nil }

    private var displayTime: Double {
        isDragging ? dragTime : controller.currentPlaybackTime
    }

    private var isPlaying: Bool { controller.isPlaying }

    var body: some View {
        VStack(spacing: 8) {
            // Timeline scrubber
            timelineSlider

            // Controls row — responsive layout
            if isNarrow {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        transportButtons
                    }
                    timecodeDisplay
                }
            } else {
                HStack(spacing: 12) {
                    transportButtons
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
                    .onAppear { isNarrow = geo.size.width < 490 }
                    .onChange(of: geo.size.width) { _, newWidth in isNarrow = newWidth < 490 }
            }
            .allowsHitTesting(false)
        )
        .onChange(of: timecodeActivationTrigger) { _, newValue in
            if let text = newValue {
                startTimecodeEdit(withInitialText: text)
                timecodeActivationTrigger = nil
            }
        }
    }

    // MARK: - Transport Buttons

    @ViewBuilder
    private var transportButtons: some View {
        // Play/Pause
        Button(action: { controller.togglePlayback() }) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(red: 1.0, green: 0.071, blue: 0.361))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)

        Divider()
            .frame(height: 18)

        // Audio track picker
        audioTrackPicker

        // Subtitle track picker
        subtitleTrackPicker

        // Loop toggle
        Button(action: {
            if let item = item {
                controller.updateLoopPlayback(!item.loopPlayback)
            }
        }) {
            Image(systemName: (item?.loopPlayback ?? false) ? "repeat.1" : "repeat")
                .font(.system(size: 14))
                .foregroundColor((item?.loopPlayback ?? false) ? .accentColor : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help((item?.loopPlayback ?? false) ? "Disable loop" : "Enable loop")

        // Fullscreen
        Button(action: { controller.toggleFullscreen() }) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Toggle fullscreen")
    }

    // MARK: - Timeline

    private var timelineSlider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let duration = item?.durationSeconds ?? 0
            let progress = duration > 0 ? displayTime / duration : 0

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)

                // Trim region overlay
                if duration > 0 {
                    let trimInFrac = controller.trimIn.map { CGFloat($0 / duration) } ?? 0
                    let trimOutFrac = controller.trimOut.map { CGFloat($0 / duration) } ?? 1

                    if controller.trimIn != nil || controller.trimOut != nil {
                        // Shaded region between trim points
                        Rectangle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: max(0, (trimOutFrac - trimInFrac) * width), height: 6)
                            .offset(x: trimInFrac * width)
                    }

                    // Trim-in marker
                    if controller.trimIn != nil {
                        Rectangle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 2, height: 14)
                            .offset(x: max(0, min(width - 2, trimInFrac * width - 1)))
                    }

                    // Trim-out marker
                    if controller.trimOut != nil {
                        Rectangle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 2, height: 14)
                            .offset(x: max(0, min(width - 2, trimOutFrac * width - 1)))
                    }
                }

                // Playhead — thin vertical line
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.071, blue: 0.361)) // #FF125C
                    .frame(width: 2, height: 14)
                    .offset(x: max(0, min(width - 2, width * CGFloat(progress) - 1)))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            wasPrecision = false
                            // Jump to click position
                            let clickFraction = max(0, min(1, value.location.x / width))
                            dragTime = Double(clickFraction) * duration
                        }
                        let isPrecision = NSEvent.modifierFlags.contains(.option)
                        if isPrecision {
                            if !wasPrecision {
                                // Entering precision: anchor at current playhead position
                                precisionAnchorFraction = duration > 0 ? dragTime / duration : 0
                                precisionAnchorX = value.location.x
                                wasPrecision = true
                            }
                            let delta = (value.location.x - precisionAnchorX) / width
                            let fraction = max(0, min(1, precisionAnchorFraction + delta / 10.0))
                            dragTime = Double(fraction) * duration
                        } else {
                            wasPrecision = false
                            let fraction = max(0, min(1, value.location.x / width))
                            dragTime = Double(fraction) * duration
                        }
                        controller.seekTo(dragTime)
                    }
                    .onEnded { value in
                        let isPrecision = NSEvent.modifierFlags.contains(.option)
                        if isPrecision && wasPrecision {
                            let delta = (value.location.x - precisionAnchorX) / width
                            let fraction = max(0, min(1, precisionAnchorFraction + delta / 10.0))
                            dragTime = Double(fraction) * duration
                        } else {
                            let fraction = max(0, min(1, value.location.x / width))
                            dragTime = Double(fraction) * duration
                        }
                        controller.seekTo(dragTime)
                        isDragging = false
                        wasPrecision = false
                    }
            )
        }
        .frame(height: 20)
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
            guard isLoaded else { return }
            let hasSourceTC = item.flatMap { TimecodeFormatter.effectiveStartTimecode(for: $0) } != nil
            timecodeMode.toggle(hasSourceTimecode: hasSourceTC)
        }
        .onTapGesture(count: 2) {
            guard isLoaded else { return }
            startTimecodeEdit()
        }
        .help("Click to cycle mode, double-click or type numbers to edit")
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
            .focused($isTimecodeFocused)
            .onSubmit {
                seekToTimecode()
            }
            .onExitCommand {
                cancelTimecodeEdit()
            }
    }

    // MARK: - Timecode Edit Methods

    private func startTimecodeEdit() {
        guard let item = item else { return }
        timecodeInput = TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: controller.currentPlaybackTime,
            item: item,
            mode: timecodeMode
        )
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingTimecode = true
        }
        isTimecodeFocused = true
    }

    private func startTimecodeEdit(withInitialText text: String) {
        timecodeInput = ""
        pendingCharacter = text
        justActivated = true

        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingTimecode = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTimecodeFocused = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let char = pendingCharacter {
                    timecodeInput = char
                    pendingCharacter = nil
                    justActivated = false
                }
            }
        }
    }

    private func cancelTimecodeEdit() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingTimecode = false
        }
        isTimecodeFocused = false
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
        controller.seekTo(clampedTime)
        cancelTimecodeEdit()
    }

    // MARK: - Timecode Parsing

    private func parseTimecodeToSeconds(_ timecode: String) -> Double? {
        let trimmed = timecode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        guard let item = item else { return nil }
        let frameRate = TimecodeFormatter.effectiveFrameRate(for: item)
        let fps = Int(frameRate.rounded())

        // Frames mode
        if timecodeMode == .frames {
            if trimmed.hasPrefix("+") || trimmed.hasPrefix("-") {
                let isPositive = trimmed.hasPrefix("+")
                if let frameOffset = Int(String(trimmed.dropFirst())), frameOffset >= 0 {
                    let offsetSeconds = Double(frameOffset) / frameRate
                    return isPositive ? controller.currentPlaybackTime + offsetSeconds : controller.currentPlaybackTime - offsetSeconds
                }
            }

            if let frameNumber = Int(trimmed), frameNumber >= 0 {
                return Double(frameNumber) / frameRate
            }
        }

        // Frame-only navigation (..<number>)
        if trimmed.hasPrefix("..") {
            let frameString = String(trimmed.dropFirst(2))
            guard let frames = Int(frameString), frames >= 0, frames < fps else {
                return nil
            }
            let currentSeconds = floor(controller.currentPlaybackTime)
            let newTime = currentSeconds + (Double(frames) / frameRate)
            let duration = max(item.durationSeconds, 0)
            return max(0, min(newTime, duration))
        }

        // Relative frame seeking (+..<number> or -..<number>)
        if trimmed.hasPrefix("+..") || trimmed.hasPrefix("-..") {
            let isPositive = trimmed.hasPrefix("+")
            let frameString = String(trimmed.dropFirst(3))
            guard let frames = Int(frameString), frames >= 0 else {
                return nil
            }
            let frameOffset = Double(frames) / frameRate
            let newTime = isPositive ? controller.currentPlaybackTime + frameOffset : controller.currentPlaybackTime - frameOffset
            let duration = max(item.durationSeconds, 0)
            return max(0, min(newTime, duration))
        }

        // Relative seeking (+/-)
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("-") {
            let isPositive = trimmed.hasPrefix("+")
            let offsetString = String(trimmed.dropFirst())

            guard let offsetSeconds = parseTimecodeOffset(offsetString, frameRate: frameRate, fps: fps) else {
                return nil
            }

            let newTime = isPositive ? controller.currentPlaybackTime + offsetSeconds : controller.currentPlaybackTime - offsetSeconds
            let duration = max(item.durationSeconds, 0)
            return max(0, min(newTime, duration))
        }

        // Absolute timecode
        return parseAbsoluteTimecode(trimmed, frameRate: frameRate, fps: fps)
    }

    private func parseTimecodeOffset(_ input: String, frameRate: Double, fps: Int) -> Double? {
        let components = input.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." })

        guard !components.isEmpty, components.count <= 4 else { return nil }

        var hours = 0
        var minutes = 0
        var seconds = 0
        var frames = 0

        switch components.count {
        case 1:
            guard let value = Int(components[0]) else { return nil }
            seconds = value
        case 2:
            guard let first = Int(components[0]),
                  let second = Int(components[1]) else { return nil }
            if first < 60 && second < 60 {
                minutes = first
                seconds = second
            } else {
                seconds = first
                frames = second
            }
        case 3:
            guard let h = Int(components[0]),
                  let m = Int(components[1]),
                  let s = Int(components[2]) else { return nil }
            hours = h
            minutes = m
            seconds = s
        case 4:
            guard let h = Int(components[0]),
                  let m = Int(components[1]),
                  let s = Int(components[2]),
                  let f = Int(components[3]) else { return nil }
            hours = h
            minutes = m
            seconds = s
            frames = f
        default:
            return nil
        }

        let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds)
        let frameSeconds = Double(frames) / frameRate
        return totalSeconds + frameSeconds
    }

    private func parseAbsoluteTimecode(_ input: String, frameRate: Double, fps: Int) -> Double? {
        let components = input.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." })

        guard !components.isEmpty, components.count <= 4 else { return nil }

        var hours = 0
        var minutes = 0
        var seconds = 0
        var frames = 0

        switch components.count {
        case 1:
            guard let s = Int(components[0]) else { return nil }
            seconds = s
        case 2:
            guard let m = Int(components[0]),
                  let s = Int(components[1]) else { return nil }
            minutes = m
            seconds = s
        case 3:
            guard let h = Int(components[0]),
                  let m = Int(components[1]),
                  let s = Int(components[2]) else { return nil }
            hours = h
            minutes = m
            seconds = s
        case 4:
            guard let h = Int(components[0]),
                  let m = Int(components[1]),
                  let s = Int(components[2]),
                  let f = Int(components[3]) else { return nil }
            hours = h
            minutes = m
            seconds = s
            frames = f
        default:
            return nil
        }

        guard hours >= 0, hours < 24,
              minutes >= 0, minutes < 60,
              seconds >= 0, seconds < 60,
              frames >= 0, frames < fps else {
            return nil
        }

        guard let item = item else { return nil }
        let startTC: String? = (timecodeMode == .source) ? TimecodeFormatter.effectiveStartTimecode(for: item) : nil

        if let startTC = startTC {
            let startComponents = startTC.split(whereSeparator: { $0 == ":" || $0 == ";" })
            guard startComponents.count == 4,
                  let startHours = Int(startComponents[0]),
                  let startMinutes = Int(startComponents[1]),
                  let startSeconds = Int(startComponents[2]),
                  let startFrames = Int(startComponents[3]) else {
                return nil
            }

            var inputTotalFrames = hours * 3600 * fps
            inputTotalFrames += minutes * 60 * fps
            inputTotalFrames += seconds * fps
            inputTotalFrames += frames

            var startTotalFrames = startHours * 3600 * fps
            startTotalFrames += startMinutes * 60 * fps
            startTotalFrames += startSeconds * fps
            startTotalFrames += startFrames

            let frameOffset = inputTotalFrames - startTotalFrames
            return Double(frameOffset) / frameRate
        } else {
            let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds)
            let frameSeconds = Double(frames) / frameRate
            return totalSeconds + frameSeconds
        }
    }

    // MARK: - Audio Track Picker

    private var audioTrackPicker: some View {
        Menu {
            ForEach(controller.audioTrackOptions) { option in
                Button(action: { controller.selectAudioTrack(at: option.position) }) {
                    HStack {
                        Text(option.title)
                        if option.position == controller.selectedAudioTrackOrderIndex {
                            Image(systemName: "checkmark")
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
        .frame(width: 28)
        .help("Audio track")
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
        .help("Subtitles")
    }
}
