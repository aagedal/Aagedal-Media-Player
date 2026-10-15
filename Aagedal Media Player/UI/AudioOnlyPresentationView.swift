// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Primary playback surface for media that contains audio but no video.

import SwiftUI

struct AudioOnlyPresentationView: View {
    @ObservedObject var generator: AudioWaveformGenerator
    @ObservedObject var controller: PlayerController
    let item: MediaItem
    let showsWaveform: Bool

    private var trackDescription: String? {
        let selectedIndex = controller.selectedAudioTrackOrderIndex
        if controller.audioTrackOptions.indices.contains(selectedIndex) {
            let option = controller.audioTrackOptions[selectedIndex]
            return [option.title, option.subtitle]
                .compactMap { $0 }
                .joined(separator: " — ")
        }

        guard let stream = item.metadata?.audioStreams.first else { return nil }
        var parts: [String] = []
        if let codec = stream.codecLongName ?? stream.codec, !codec.isEmpty {
            parts.append(codec)
        }
        if let channels = stream.channels, channels > 0 {
            parts.append(channels == 1 ? "Mono" : "\(channels) channels")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 300
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.08, green: 0.05, blue: 0.12), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: compact ? 6 : 10) {
                    Spacer(minLength: 8)

                    if !compact {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: min(64, geometry.size.height * 0.13), weight: .light))
                            .foregroundStyle(.white.opacity(0.88), .pink.opacity(0.72))
                            .accessibilityHidden(true)
                    }

                    Text(item.name)
                        .font(compact ? .headline : .title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 28)

                    if let trackDescription, !trackDescription.isEmpty {
                        Text(trackDescription)
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .padding(.horizontal, 28)
                    }

                    if showsWaveform {
                        AudioWaveformView(
                            generator: generator,
                            controller: controller,
                            isOverlay: true,
                            transparentBackground: true
                        )
                        .frame(height: max(0, min(280, geometry.size.height - (compact ? 90 : 180))))
                        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, max(24, geometry.size.width * 0.07))
                        .padding(.top, 10)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio-only media")
        .onChange(of: showsWaveform) { _, isVisible in
            if !isVisible {
                generator.cancel()
            }
        }
        .onDisappear {
            generator.cancel()
        }
    }
}
