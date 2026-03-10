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

    @AppStorage(SettingsView.audioWaveformBoostKey) private var waveformBoost: Double = 0
    @AppStorage(SettingsView.audioWaveformColorKey) private var waveformColor: String = AudioWaveformColor.pink.rawValue

    @State private var isDragging = false
    @State private var rerenderTask: Task<Void, Never>?

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
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Slider(value: $waveformBoost, in: 0...100)
                            .frame(width: 80)
                            .controlSize(.mini)
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
            } else if !isOverlay {
                if let error = generator.error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else {
                    Color.black
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
            } else if oldValue?.metadata == nil && newValue?.metadata != nil {
                // Metadata just arrived for the same file — trigger generation
                // in case audioTrackOptions already fired before metadata was available.
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
            rerenderTask?.cancel()
            rerenderTask = Task {
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                generator.rerender()
            }
        }
        .onChange(of: waveformColor) {
            if generator.hasCachedAmplitudes {
                generator.rerender()
            } else {
                triggerGeneration()
            }
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
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.medium)

                            // Channel label
                            if index < generator.channelLabels.count {
                                Text(generator.channelLabels[index])
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(white: 0.5))
                                    .padding(.leading, 4)
                                    .padding(.top, 2)
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

                // Playhead
                let fraction = duration > 0 ? controller.currentPlaybackTime / duration : 0
                let xPos = geo.size.width * CGFloat(fraction)

                Path { path in
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: geo.size.height))
                }
                .stroke(Color.white, lineWidth: 1.5)
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        seekToPosition(value.location.x, in: geo.size.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }

    private var activeStreamIndex: Int? {
        guard controller.showAllMonoWaveforms, controller.isMultiMonoFile else { return nil }
        let idx = controller.selectedAudioTrackOrderIndex
        guard idx < controller.audioTrackOptions.count else { return nil }
        return controller.audioTrackOptions[idx].streamIndex
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

    private func seekToPosition(_ x: CGFloat, in width: CGFloat) {
        guard width > 0, duration > 0 else { return }
        let fraction = max(0, min(1, x / width))
        let time = fraction * duration
        controller.seekTo(time)
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
                } else if let option = controller.audioTrackOptions.first(where: { $0.streamIndex == offset }) {
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
        let streamIndex = option.streamIndex

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
