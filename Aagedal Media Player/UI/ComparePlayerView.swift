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
            let displayGeometry = displayGeometry(for: size)
            let presentation = presentationGeometry(using: displayGeometry)

            // Keep exactly one native surface for each controller across every
            // presentation mode. MPV binds its drawable during setup, so
            // conditionally rebuilding either PlayerView can strand playback
            // on an obsolete Metal layer.
            ZStack(alignment: .topLeading) {
                comparisonSurfaces(size: size, presentation: presentation)

                if compareSession.viewMode == .sideBySide {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: size.height)
                        .offset(x: max(0, size.width / 2 - 0.5))
                        .allowsHitTesting(false)
                }

                sourceBadges

                if compareSession.viewMode.isWipe {
                    wipeInteractionOverlay(referenceRect: displayGeometry.comparisonReferenceRect)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .coordinateSpace(name: "compareCanvas")
        }
        .background(Color.black)
    }

    private func comparisonSurfaces(
        size: CGSize,
        presentation: PresentationGeometry
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black

            primaryPlayer
                .frame(width: size.width, height: size.height)
                .scaleEffect(presentation.primaryTransform.scale, anchor: .topLeading)
                .offset(
                    x: presentation.primaryTransform.offset.x,
                    y: presentation.primaryTransform.offset.y
                )
                .opacity(presentation.primaryOpacity)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(
                            width: presentation.primaryPresentationClipRect.width,
                            height: presentation.primaryPresentationClipRect.height
                        )
                        .offset(
                            x: presentation.primaryPresentationClipRect.minX,
                            y: presentation.primaryPresentationClipRect.minY
                        )
                }

            secondaryPlayer
                .frame(width: size.width, height: size.height)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(
                            width: presentation.secondaryClipRect.width,
                            height: presentation.secondaryClipRect.height
                        )
                        .offset(
                            x: presentation.secondaryClipRect.minX,
                            y: presentation.secondaryClipRect.minY
                        )
                }
                .scaleEffect(presentation.secondaryTransform.scale, anchor: .topLeading)
                .offset(
                    x: presentation.secondaryTransform.offset.x,
                    y: presentation.secondaryTransform.offset.y
                )
                .opacity(presentation.secondaryOpacity)
                .blendMode(compareSession.viewMode == .difference ? .difference : .normal)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(
                            width: presentation.secondaryPresentationClipRect.width,
                            height: presentation.secondaryPresentationClipRect.height
                        )
                        .offset(
                            x: presentation.secondaryPresentationClipRect.minX,
                            y: presentation.secondaryPresentationClipRect.minY
                        )
                }
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        // SwiftUI's Difference blend produces abs(A - B). Applying brightness
        // before contrast with this offset makes the contrast transform
        // simplify to abs(A - B) * gain, clamped by the compositor. Standard
        // layer effects also keep AppKit-backed MPV and AVPlayer surfaces in
        // the render tree, unlike stitchable color shaders.
        .brightness(differenceBrightness)
        .contrast(differenceContrast)
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
                acceptsKeyboardInput: false,
                // A paired reload rebuilds both controllers. When A is also
                // MPV-backed, let its surface own the window-level request so
                // one fullscreen/resize event cannot rebuild the pair twice.
                managesMPVSurfaceReloads: !primaryController.useMPV
            )
        } else {
            Color.black
        }
    }

    private var sourceBadges: some View {
        HStack(alignment: .top, spacing: 8) {
            if compareSession.viewMode != .secondary {
                sourceBadge("A", name: primaryItem.name, audioSource: .primary)
            }
            Spacer(minLength: 8)
            if compareSession.viewMode != .primary,
               let secondaryItem = secondaryController.mediaItem {
                sourceBadge("B", name: secondaryItem.name, audioSource: .secondary)
            }
        }
        .padding(.top, 44)
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }

    private func sourceBadge(
        _ source: String,
        name: String,
        audioSource: CompareAudioSource
    ) -> some View {
        HStack(spacing: 6) {
            Text(source)
                .fontWeight(.bold)
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
            Text(name)
                .lineLimit(1)
            if compareSession.audioSource == audioSource {
                Image(systemName: "speaker.wave.2.fill")
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
    }

    private func wipeInteractionOverlay(referenceRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if compareSession.viewMode == .verticalWipe {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 24, height: referenceRect.height)
                    .offset(
                        x: handleOffset(
                            origin: referenceRect.minX,
                            total: referenceRect.width
                        ),
                        y: referenceRect.minY
                    )
                    .gesture(wipeDragGesture(referenceRect: referenceRect))

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: referenceRect.height)
                    .offset(
                        x: dividerOffset(
                            origin: referenceRect.minX,
                            total: referenceRect.width
                        ),
                        y: referenceRect.minY
                    )
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: referenceRect.width, height: 24)
                    .offset(
                        x: referenceRect.minX,
                        y: handleOffset(
                            origin: referenceRect.minY,
                            total: referenceRect.height
                        )
                    )
                    .gesture(wipeDragGesture(referenceRect: referenceRect))

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: referenceRect.width, height: 2)
                    .offset(
                        x: referenceRect.minX,
                        y: dividerOffset(
                            origin: referenceRect.minY,
                            total: referenceRect.height
                        )
                    )
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func wipeDragGesture(referenceRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("compareCanvas"))
            .onChanged { value in
                let position: Double
                if compareSession.viewMode == .verticalWipe {
                    position = referenceRect.width > 0
                        ? Double((value.location.x - referenceRect.minX) / referenceRect.width)
                        : 0.5
                } else {
                    position = referenceRect.height > 0
                        ? Double((value.location.y - referenceRect.minY) / referenceRect.height)
                        : 0.5
                }
                compareSession.setWipePosition(position)
            }
    }

    private func dividerOffset(origin: CGFloat, total: CGFloat) -> CGFloat {
        let position = CGFloat(compareSession.wipePosition)
        return origin + max(0, min(total - 2, total * position - 1))
    }

    private func handleOffset(origin: CGFloat, total: CGFloat) -> CGFloat {
        let position = CGFloat(compareSession.wipePosition)
        return origin + max(0, min(total - 24, total * position - 12))
    }

    private func displayGeometry(for size: CGSize) -> CompareDisplayGeometry {
        CompareDisplayGeometry(
            canvasSize: size,
            primaryAspectRatio: resolvedAspectRatio(
                controller: primaryController,
                item: primaryItem
            ),
            secondaryAspectRatio: secondaryController.mediaItem.flatMap {
                resolvedAspectRatio(controller: secondaryController, item: $0)
            }
        )
    }

    private func resolvedAspectRatio(controller: PlayerController, item: MediaItem) -> CGFloat? {
        if let ratio = controller.videoAspectRatio, ratio.isFinite, ratio > 0 {
            return ratio
        }
        if let ratio = item.videoDisplayAspectRatio, ratio.isFinite, ratio > 0 {
            return CGFloat(ratio)
        }
        return nil
    }

    private func presentationGeometry(using displayGeometry: CompareDisplayGeometry) -> PresentationGeometry {
        let mode = compareSession.viewMode
        let sideBySide = mode == .sideBySide

        // Side-by-side is a visual transform over two full-size render
        // surfaces. Keeping their layout size stable avoids MPV's large-
        // surface-change reload path when the user switches modes.
        return PresentationGeometry(
            primaryTransform: sideBySide
                ? displayGeometry.sideBySideTransform(for: .primary)
                : .identity,
            secondaryTransform: sideBySide
                ? displayGeometry.sideBySideTransform(for: .secondary)
                : .identity,
            primaryOpacity: mode == .secondary ? 0 : 1,
            secondaryClipRect: displayGeometry.secondaryClipRect(
                for: mode,
                wipePosition: compareSession.wipePosition
            ),
            primaryPresentationClipRect: displayGeometry.presentationClipRect(
                for: .primary,
                mode: mode
            ),
            secondaryPresentationClipRect: displayGeometry.presentationClipRect(
                for: .secondary,
                mode: mode
            ),
            secondaryOpacity: secondaryOpacity(for: mode)
        )
    }

    private func secondaryOpacity(for mode: CompareViewMode) -> Double {
        switch mode {
        case .primary:
            0
        case .overlay:
            CompareSessionController.clampedUnitValue(compareSession.overlayBlend)
        case .sideBySide, .secondary, .verticalWipe, .horizontalWipe, .difference:
            1
        }
    }

    private var differenceContrast: Double {
        compareSession.viewMode == .difference ? compareSession.differenceGain : 1
    }

    private var differenceBrightness: Double {
        guard compareSession.viewMode == .difference else { return 0 }
        return CompareSessionController.differenceBrightness(
            forGain: compareSession.differenceGain
        )
    }

    private struct PresentationGeometry {
        let primaryTransform: CompareSurfaceTransform
        let secondaryTransform: CompareSurfaceTransform
        let primaryOpacity: Double
        let secondaryClipRect: CGRect
        let primaryPresentationClipRect: CGRect
        let secondaryPresentationClipRect: CGRect
        let secondaryOpacity: Double
    }
}
