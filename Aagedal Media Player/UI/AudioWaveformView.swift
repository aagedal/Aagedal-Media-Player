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

    @State private var isDragging = false

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
            if generator.channelImages.isEmpty && !generator.isGenerating {
                if !isOverlay {
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
            } else {
                waveformContent
            }
        }
        .background(isOverlay ? Color.clear : Color.black)
        .onChange(of: controller.selectedAudioTrackOrderIndex) {
            triggerGeneration()
        }
        .onChange(of: controller.mediaItem) {
            generator.reset()
            if let name = controller.mediaItem?.name {
                onMediaChange?(name)
            }
            // Waveform generation deferred to audioTrackOptions change,
            // since metadata/tracks aren't available yet when mediaItem changes.
        }
        .onChange(of: controller.audioTrackOptions) {
            triggerGeneration()
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

    private var currentTrackTitle: String? {
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
