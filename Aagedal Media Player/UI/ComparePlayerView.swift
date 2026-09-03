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
        GeometryReader { geometry in
            let size = geometry.size
            let presentation = presentationGeometry(for: size)

            // Keep exactly one native surface for each controller across every
            // presentation mode. MPV binds its drawable during setup, so
            // conditionally rebuilding either PlayerView can strand playback
            // on an obsolete Metal layer.
            ZStack(alignment: .topLeading) {
                primaryPlayer
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(presentation.sourceScale, anchor: .topLeading)
                    .offset(y: presentation.sourceOffsetY)
                    .opacity(presentation.primaryOpacity)

                secondaryPlayer
                    .frame(width: size.width, height: size.height)
                    .frame(
                        width: presentation.secondaryClipWidth,
                        height: presentation.secondaryClipHeight,
                        alignment: .topLeading
                    )
                    .clipped()
                    .scaleEffect(presentation.sourceScale, anchor: .topLeading)
                    .offset(
                        x: presentation.secondaryOffsetX,
                        y: presentation.sourceOffsetY
                    )
                    .opacity(presentation.secondaryOpacity)

                if compareSession.viewMode == .sideBySide {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: size.height)
                        .offset(x: max(0, size.width / 2 - 0.5))
                        .allowsHitTesting(false)
                }

                sourceBadges

                if compareSession.viewMode.isWipe {
                    wipeInteractionOverlay(size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .coordinateSpace(name: "compareCanvas")
        }
        .background(Color.black)
    }

    private var primaryPlayer: some View {
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

    @ViewBuilder
    private var secondaryPlayer: some View {
        if let item = secondaryController.mediaItem {
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
        } else {
            Color.black
        }
    }

    private var sourceBadges: some View {
        HStack(alignment: .top, spacing: 8) {
            if compareSession.viewMode != .secondary {
                sourceBadge("A", name: primaryItem.name)
            }
            Spacer(minLength: 8)
            if compareSession.viewMode != .primary,
               let secondaryItem = secondaryController.mediaItem {
                sourceBadge("B", name: secondaryItem.name)
            }
        }
        .padding(.top, 44)
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }

    private func sourceBadge(_ source: String, name: String) -> some View {
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
    }

    private func wipeInteractionOverlay(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if compareSession.viewMode == .verticalWipe {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 24, height: size.height)
                    .offset(x: handleOffset(total: size.width))
                    .gesture(wipeDragGesture(size: size))

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: size.height)
                    .offset(x: dividerOffset(total: size.width))
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: size.width, height: 24)
                    .offset(y: handleOffset(total: size.height))
                    .gesture(wipeDragGesture(size: size))

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: size.width, height: 2)
                    .offset(y: dividerOffset(total: size.height))
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func wipeDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("compareCanvas"))
            .onChanged { value in
                let position: Double
                if compareSession.viewMode == .verticalWipe {
                    position = size.width > 0 ? Double(value.location.x / size.width) : 0.5
                } else {
                    position = size.height > 0 ? Double(value.location.y / size.height) : 0.5
                }
                compareSession.setWipePosition(position)
            }
    }

    private func dividerOffset(total: CGFloat) -> CGFloat {
        let position = CGFloat(compareSession.wipePosition)
        return max(0, min(total - 2, total * position - 1))
    }

    private func handleOffset(total: CGFloat) -> CGFloat {
        let position = CGFloat(compareSession.wipePosition)
        return max(0, min(total - 24, total * position - 12))
    }

    private func presentationGeometry(for size: CGSize) -> PresentationGeometry {
        let mode = compareSession.viewMode
        let sideBySide = mode == .sideBySide
        let secondaryClipWidth = mode == .verticalWipe
            ? size.width * CGFloat(compareSession.wipePosition)
            : size.width
        let secondaryClipHeight = mode == .horizontalWipe
            ? size.height * CGFloat(compareSession.wipePosition)
            : size.height

        // Side-by-side is a visual transform over two full-size render
        // surfaces. Keeping their layout size stable avoids MPV's large-
        // surface-change reload path when the user switches modes.
        return PresentationGeometry(
            sourceScale: sideBySide ? 0.5 : 1,
            sourceOffsetY: sideBySide ? size.height / 4 : 0,
            primaryOpacity: mode == .secondary ? 0 : 1,
            secondaryClipWidth: secondaryClipWidth,
            secondaryClipHeight: secondaryClipHeight,
            secondaryOffsetX: sideBySide ? size.width / 2 : 0,
            secondaryOpacity: secondaryOpacity(for: mode)
        )
    }

    private func secondaryOpacity(for mode: CompareViewMode) -> Double {
        switch mode {
        case .primary:
            0
        case .overlay:
            CompareSessionController.clampedUnitValue(compareSession.overlayBlend)
        case .sideBySide, .secondary, .verticalWipe, .horizontalWipe:
            1
        }
    }

    private struct PresentationGeometry {
        let sourceScale: CGFloat
        let sourceOffsetY: CGFloat
        let primaryOpacity: Double
        let secondaryClipWidth: CGFloat
        let secondaryClipHeight: CGFloat
        let secondaryOffsetX: CGFloat
        let secondaryOpacity: Double
    }
}
