// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwiftUI view displaying per-channel audio waveforms with a synced playhead.

import SwiftUI

struct AudioWaveformView: View {
    @ObservedObject var generator: AudioWaveformGenerator
    @ObservedObject var controller: PlayerController
    var isOverlay = false
    var transparentBackground = false
    var onMediaChange: ((String) -> Void)?

    @AppStorage(AppSettings.audioWaveformBoost.key)
    private var waveformBoost = AppSettings.audioWaveformBoost.defaultValue
    @AppStorage(AppSettings.audioWaveformColor.key)
    private var waveformColor = AppSettings.audioWaveformColor.defaultValue

    @State private var isDragging = false
    @State private var dragTime: Double = 0
    @State private var deferredRerender = DeferredMainActorTask()
    @State private var deferredResize = DeferredMainActorTask()
    @Environment(\.displayScale) private var displayScale

    private var duration: Double {
        controller.mediaItem?.durationSeconds ?? 0
    }

    private var backgroundColor: Color {
        transparentBackground ? Color.black.opacity(0.5) : Color.black
    }

    var body: some View {
        VStack(spacing: 0) {
            // Track info toolbar (window mode only)
            if !isOverlay {
                HStack {
                    if let trackTitle = currentTrackTitle {
                        Text(trackTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if hasLoudnessAnalysis { loudnessMenu }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Slider(value: $waveformBoost, in: 0...100)
                            .frame(width: 80)
                            .controlSize(.mini)
                            .accessibilityLabel("Waveform gain")
                            .accessibilityValue("\(Int(waveformBoost)) percent")
                        Text("\(Int(waveformBoost))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                    if generator.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating\u{2026}")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()
            }

            // Keep the graph control at the left, outside the player's explicit
            // right-edge cursor-hide zone. Reserve space rather than covering
            // channel labels or putting the menu back over the picture edge.
            if isOverlay && hasLoudnessAnalysis {
                HStack {
                    loudnessMenu
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor)
            }

            // Waveform channels
            if !generator.channelImages.isEmpty {
                waveformContent
            } else if generator.isGenerating {
                // Loading state
                ZStack {
                    backgroundColor
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating waveform\u{2026}")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = generator.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Couldn’t generate the waveform")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Button("Retry") {
                        triggerGeneration()
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor)
            } else if !isOverlay {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(isOverlay ? Color.clear : Color.black)
        .onChange(of: controller.selectedAudioTrackOrderIndex) {
            triggerGeneration()
        }
        .onChange(of: controller.mediaItem) { oldValue, newValue in
            if oldValue?.url != newValue?.url {
                generator.reset()
                if let name = newValue?.name {
                    onMediaChange?(name)
                }
                // Waveform generation deferred to audioTrackOptions change,
                // since metadata/tracks aren't available yet when mediaItem changes.
            } else if oldValue?.metadata != newValue?.metadata || oldValue?.durationSeconds != newValue?.durationSeconds {
                // Same-file metadata can change duration, layout and channel labels.
                triggerGeneration()
            }
        }
        .onChange(of: controller.audioTrackOptions) {
            triggerGeneration()
        }
        .onChange(of: controller.showAllMonoWaveforms) {
            generator.reset()
            triggerGeneration()
        }
        .onChange(of: waveformBoost) {
            deferredRerender.schedule(after: .milliseconds(30)) {
                generator.rerender()
            }
        }
        .onChange(of: waveformColor) {
            deferredRerender.cancel()
            if generator.hasCachedAmplitudes {
                generator.rerender()
            } else {
                triggerGeneration()
            }
        }
        .onAppear {
            triggerGeneration()
        }
        .onDisappear {
            deferredRerender.cancel()
            deferredResize.cancel()
        }
    }

    private var waveformContent: some View {
        GeometryReader { geo in
            ZStack {
                backgroundColor

                // Channel waveforms
                VStack(spacing: 0) {
                    ForEach(Array(generator.channelImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1 / displayScale)
                                .frame(maxHeight: .infinity, alignment: .center)

                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.none)

                            // Channel label
                            if index < generator.channelLabels.count {
                                Text(generator.channelLabels[index])
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                                    .padding(4)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }

                            // Subtle separator line at bottom
                            if index < generator.channelImages.count - 1 {
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color(white: 0.2))
                                        .frame(height: 0.5)
                                }
                            }
                        }
                        .opacity(activeStreamIndex.map { $0 == index ? 1.0 : 0.4 } ?? 1.0)
                        .animation(.easeInOut(duration: 0.2), value: activeStreamIndex)
                    }
                }

                if controller.showsWaveformLoudness, let result = loudnessResult {
                    let row = loudnessRow
                    let height = row == nil ? geo.size.height : geo.size.height / CGFloat(max(1, generator.channelImages.count))
                    WaveformLoudnessOverlay(result: result, duration: duration, title: loudnessTitle)
                        .equatable()
                        .frame(width: geo.size.width, height: height)
                        .position(x: geo.size.width / 2, y: height * (CGFloat(row ?? 0) + 0.5))
                }

                // Playhead
                let displayedTime = isDragging ? dragTime : controller.currentPlaybackTime
                let fraction = duration.isFinite && duration > 0 && displayedTime.isFinite
                    ? min(1, max(0, displayedTime / duration)) : 0
                let xPos = min(max(0, geo.size.width - 1 / displayScale),
                               (geo.size.width * CGFloat(fraction) * displayScale).rounded() / displayScale)

                Path { path in
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: geo.size.height))
                }
                .stroke(Color.white, lineWidth: 1.5)
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
            }
            .clipped()
            .onAppear { generator.setRenderWidth(geo.size.width * displayScale) }
            .onChange(of: geo.size.width) {
                deferredResize.schedule(after: .milliseconds(80)) {
                    generator.setRenderWidth(geo.size.width * displayScale)
                }
            }
            .onChange(of: displayScale) {
                generator.setRenderWidth(geo.size.width * displayScale)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio waveform, \(generator.channelLabels.joined(separator: ", "))")
            .accessibilityValue("\((controller.currentPlaybackTime.isFinite ? max(0, controller.currentPlaybackTime) : 0).formatted(.number.precision(.fractionLength(0)))) seconds\(loudnessAccessibilityDescription)")
            .accessibilityAdjustableAction { direction in
                guard duration.isFinite, duration > 0 else { return }
                let step = max(1, duration / 100)
                let delta: Double
                switch direction {
                case .increment: delta = step
                case .decrement: delta = -step
                @unknown default: return
                }
                controller.seekTo(min(duration, max(0, controller.currentPlaybackTime + delta)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragTime = time(at: value.location.x, in: geo.size.width)
                        controller.scrub(to: dragTime)
                    }
                    .onEnded { value in
                        dragTime = time(at: value.location.x, in: geo.size.width)
                        controller.endScrubbing(at: dragTime)
                        isDragging = false
                    }
            )

        }
    }

    private var loudnessMenu: some View {
        Menu {
            Text(loudnessTitle)
            Toggle("Show LUFS graph", isOn: $controller.showsWaveformLoudness)
            if controller.waveformProgrammeLoudness?.loudness.samples?.isEmpty == false {
                Toggle("Use programme loudness", isOn: $controller.waveformUsesProgrammeLoudness)
            }
        } label: {
            Text("LUFS").font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.white)
        .accessibilityLabel("Waveform LUFS graph options")
        .help("Show or hide analyzed momentary (M) and short-term (S) loudness")
    }

    private var selectedTrackLoudness: FFmpegService.LUFSResult? {
        let index = controller.selectedAudioTrackOrderIndex
        guard controller.audioTrackOptions.indices.contains(index) else { return nil }
        return controller.waveformLoudnessResults[controller.audioTrackOptions[index].audioStreamOrderIndex]
    }

    private var hasLoudnessAnalysis: Bool {
        selectedTrackLoudness?.samples?.isEmpty == false || controller.waveformProgrammeLoudness?.loudness.samples?.isEmpty == false
    }

    private var loudnessResult: FFmpegService.LUFSResult? {
        let result = controller.waveformUsesProgrammeLoudness
            ? controller.waveformProgrammeLoudness?.loudness : selectedTrackLoudness
        guard let result, result.samples?.isEmpty == false else { return nil }
        return result
    }

    private var loudnessTitle: String {
        let range = loudnessResult?.analysisRange.map {
            String(format: " · %.1f–%.1f s", $0.start, $0.end)
        } ?? ""
        if controller.waveformUsesProgrammeLoudness {
            let tracks = controller.waveformProgrammeLoudness?.mapping.audioStreamIndices.map { String($0 + 1) }.joined(separator: "+") ?? ""
            return "Programme \(tracks)" + range
        }
        let index = controller.selectedAudioTrackOrderIndex
        guard controller.audioTrackOptions.indices.contains(index) else { return "Track" + range }
        return "Track \(controller.audioTrackOptions[index].audioStreamOrderIndex + 1)" + range
    }

    private var loudnessRow: Int? {
        guard !controller.waveformUsesProgrammeLoudness, let index = activeStreamIndex,
              generator.channelImages.indices.contains(index) else { return nil }
        return index
    }

    private var loudnessAccessibilityDescription: String {
        guard controller.showsWaveformLoudness, let result = loudnessResult else { return "" }
        return ", \(loudnessTitle) momentary and short-term LUFS graph, integrated \(String(format: "%.1f", result.integratedLoudness)) LUFS"
    }

    private var activeStreamIndex: Int? {
        guard controller.showAllMonoWaveforms, controller.isMultiMonoFile else { return nil }
        let idx = controller.selectedAudioTrackOrderIndex
        guard idx < controller.audioTrackOptions.count else { return nil }
        return controller.audioTrackOptions[idx].audioStreamOrderIndex
    }

    private var currentTrackTitle: String? {
        if controller.showAllMonoWaveforms && controller.isMultiMonoFile {
            return "All Tracks (\(controller.audioTrackOptions.count))"
        }
        let idx = controller.selectedAudioTrackOrderIndex
        guard idx < controller.audioTrackOptions.count else { return nil }
        let option = controller.audioTrackOptions[idx]
        var parts = [option.title]
        if let subtitle = option.subtitle {
            parts.append(subtitle)
        }
        return parts.joined(separator: " \u{2014} ")
    }

    private func time(at x: CGFloat, in width: CGFloat) -> Double {
        guard x.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return 0 }
        let fraction = max(0, min(1, x / width))
        return fraction * duration
    }

    func triggerGeneration() {
        guard let item = controller.mediaItem,
              let metadata = item.metadata else { return }

        // Multi-mono: render all streams stacked
        if controller.showAllMonoWaveforms && controller.isMultiMonoFile {
            let streams: [(index: Int, label: String)] = metadata.audioStreams.enumerated().map { offset, stream in
                let label: String
                if let title = stream.title, !title.isEmpty {
                    label = title
                } else if let option = controller.audioTrackOptions.first(where: { $0.audioStreamOrderIndex == offset }) {
                    label = option.title
                } else {
                    label = "Track \(offset + 1)"
                }
                return (index: offset, label: label)
            }
            guard !streams.isEmpty else { return }
            generator.generateAllMonoStreams(url: item.url, streams: streams, duration: item.durationSeconds)
            return
        }

        let trackIdx = controller.selectedAudioTrackOrderIndex
        guard trackIdx < controller.audioTrackOptions.count else { return }

        let option = controller.audioTrackOptions[trackIdx]
        let streamIndex = option.audioStreamOrderIndex

        // Find the audio stream metadata for channel info
        let audioStreams = metadata.audioStreams
        guard streamIndex < audioStreams.count else { return }

        let stream = audioStreams[streamIndex]
        let channels = stream.channels ?? 2

        generator.generate(
            url: item.url,
            streamIndex: streamIndex,
            channels: channels,
            channelLayout: stream.channelLayout,
            duration: item.durationSeconds
        )
    }
}
