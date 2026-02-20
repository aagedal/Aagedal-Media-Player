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

    @State private var isDragging = false
    @State private var dragTime: Double = 0

    private var isLoaded: Bool { item != nil }

    private var displayTime: Double {
        isDragging ? dragTime : controller.currentPlaybackTime
    }

    private var isPlaying: Bool {
        if controller.useMPV {
            return controller.mpvPlayer?.isPlaying ?? false
        }
        return (controller.player?.rate ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Timeline scrubber
            timelineSlider

            // Controls row
            HStack(spacing: 12) {
                // Play/Pause
                Button(action: { controller.togglePlayback() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                // Timecode display
                timecodeDisplay

                Spacer()

                // Audio track picker
                if controller.audioTrackOptions.count > 1 {
                    audioTrackPicker
                }

                // Subtitle track picker
                if !controller.subtitleTrackOptions.isEmpty {
                    subtitleTrackPicker
                }

                // Volume control
                volumeControl

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
        }
        .disabled(!isLoaded)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .onReceive(NotificationCenter.default.publisher(for: .cycleTimecodeMode)) { _ in
            timecodeMode.toggle()
            UserDefaults.standard.set(timecodeMode.rawValue, forKey: "preferredTimecodeDisplayMode")
        }
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
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: max(0, width * CGFloat(progress)), height: 4)

                // Playhead
                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 14 : 10, height: isDragging ? 14 : 10)
                    .shadow(radius: 2)
                    .offset(x: max(0, width * CGFloat(progress) - (isDragging ? 7 : 5)))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let fraction = max(0, min(1, value.location.x / width))
                        dragTime = Double(fraction) * duration
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        let seekTime = Double(fraction) * duration
                        controller.seekTo(seekTime)
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }

    // MARK: - Timecode Display

    private var timecodeDisplay: some View {
        HStack(spacing: 4) {
            if let item = item {
                Text(timecodeMode.prefix)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: displayTime,
                    item: item,
                    mode: timecodeMode
                ))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

                Text("/")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(TimecodeFormatter.formatTimeForDisplayWithMode(
                    seconds: item.durationSeconds,
                    item: item,
                    mode: timecodeMode,
                    isDuration: true
                ))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            } else {
                Text("00:00:00:00")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("/")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("00:00:00:00")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            guard isLoaded else { return }
            timecodeMode.toggle()
            UserDefaults.standard.set(timecodeMode.rawValue, forKey: "preferredTimecodeDisplayMode")
        }
        .help("Click or press T to cycle timecode mode")
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

    // MARK: - Volume Control

    private var volumeControl: some View {
        HStack(spacing: 4) {
            Button(action: { controller.isMuted.toggle() }) {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { controller.isMuted ? 0 : controller.volume },
                set: { newValue in
                    controller.volume = newValue
                    if newValue > 0 { controller.isMuted = false }
                }
            ), in: 0...100)
            .frame(width: 80)
        }
    }
}
