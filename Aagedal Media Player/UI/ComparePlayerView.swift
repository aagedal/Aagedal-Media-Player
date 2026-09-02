// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ComparePlayerView: View {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    @ObservedObject var primaryWaveformGenerator: AudioWaveformGenerator
    let primaryItem: MediaItem
    let showsAudioWaveform: Bool
    @Binding var isEditingTimecode: Bool
    @Binding var isTimelineFocused: Bool
    let isOverlayControlFocused: Bool
    @Binding var timecodeActivationTrigger: String?

    private var secondaryController: PlayerController {
        compareSession.secondaryController
    }

    var body: some View {
        Group {
            switch compareSession.viewMode {
            case .sideBySide:
                HStack(spacing: 1) {
                    labeledPrimary
                    labeledSecondary
                }
                .background(Color.white.opacity(0.25))

            case .primary:
                labeledPrimary

            case .secondary:
                labeledSecondary
            }
        }
        .background(Color.black)
    }

    private var labeledPrimary: some View {
        sourceLabel("A", name: primaryItem.name) {
            PlayerView(
                controller: primaryController,
                audioWaveformGenerator: primaryWaveformGenerator,
                item: primaryItem,
                showsAudioWaveform: showsAudioWaveform,
                isEditingTimecode: $isEditingTimecode,
                isTimelineFocused: $isTimelineFocused,
                isOverlayControlFocused: isOverlayControlFocused,
                timecodeActivationTrigger: $timecodeActivationTrigger,
                compareSession: compareSession
            )
        }
    }

    @ViewBuilder
    private var labeledSecondary: some View {
        if let item = secondaryController.mediaItem {
            sourceLabel("B", name: item.name) {
                PlayerView(
                    controller: secondaryController,
                    audioWaveformGenerator: compareSession.secondaryWaveformGenerator,
                    item: item,
                    showsAudioWaveform: false,
                    isEditingTimecode: $isEditingTimecode,
                    isTimelineFocused: $isTimelineFocused,
                    isOverlayControlFocused: isOverlayControlFocused,
                    timecodeActivationTrigger: $timecodeActivationTrigger,
                    acceptsKeyboardInput: false
                )
            }
        } else {
            Color.black
        }
    }

    private func sourceLabel<Content: View>(
        _ source: String,
        name: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Text(source)
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                    Text(name)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
                .padding(.top, 44)
                .padding(.leading, 8)
                .allowsHitTesting(false)
            }
    }
}
