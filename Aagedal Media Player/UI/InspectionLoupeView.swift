// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Combine

@MainActor
final class InspectionLoupeState: ObservableObject {
    @Published var isEnabled = false
    @Published var isPinned = false
    @Published var usesNearestNeighbor = true
    @Published private(set) var magnification: LoupeMagnification = .twoTimes
    @Published var normalizedPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var pointer: CGPoint?
    @Published private(set) var overlayPosition: CGPoint?

    var canCenter: Bool {
        normalizedPoint != CGPoint(x: 0.5, y: 0.5)
            || pointer != nil
            || overlayPosition != nil
    }

    func follow(_ location: CGPoint, pictureRect: CGRect) {
        guard isEnabled, !isPinned,
              let point = LoupeGeometry.normalizedPoint(location: location, in: pictureRect) else { return }
        normalizedPoint = point
        pointer = location
    }

    /// Shared by the live canvas hover handler and pointer-to-lens rendering
    /// tests. Coordinates remain in the full canvas even at reduced render size.
    /// Blended/difference images use A as their picture-coordinate reference;
    /// a fully B overlay uses B, matching the picture actually visible.
    func follow(
        _ location: CGPoint,
        geometry: CompareDisplayGeometry,
        isComparing: Bool,
        mode: CompareViewMode,
        wipePosition: Double,
        overlayBlend: Double
    ) {
        let mode: CompareViewMode = isComparing ? mode : .primary
        let source: CompareSource = mode == .secondary
            || (mode == .sideBySide && location.x >= geometry.canvasSize.width / 2)
            || (mode.isWipe && geometry.secondaryClipRect(for: mode, wipePosition: wipePosition).contains(location))
            || (mode == .overlay && CompareSessionController.clampedUnitValue(overlayBlend) == 1)
            ? .secondary : .primary
        let rect = CompareDisplayGeometry.aspectFitRect(
            aspectRatio: source == .primary ? geometry.primaryAspectRatio : geometry.secondaryAspectRatio,
            in: geometry.presentationClipRect(for: source, mode: mode)
        )
        follow(location, pictureRect: rect)
    }

    func reset() {
        normalizedPoint = CGPoint(x: 0.5, y: 0.5)
        pointer = nil
        overlayPosition = nil
        isPinned = true
    }

    func moveOverlay(to position: CGPoint, canvasSize: CGSize, overlaySize: CGSize) {
        guard isEnabled else { return }
        isPinned = true
        overlayPosition = LoupeGeometry.clampedOverlayCenter(
            position, canvasSize: canvasSize, overlaySize: overlaySize
        )
    }

    func resetOverlayPosition() {
        overlayPosition = nil
    }

    func moveTarget(to location: CGPoint, pictureRect: CGRect) {
        guard isEnabled, pictureRect.width > 0, pictureRect.height > 0,
              location.x.isFinite, location.y.isFinite else { return }
        let location = CGPoint(
            x: min(max(location.x, pictureRect.minX), pictureRect.maxX),
            y: min(max(location.y, pictureRect.minY), pictureRect.maxY)
        )
        guard let point = LoupeGeometry.normalizedPoint(location: location, in: pictureRect) else { return }
        isPinned = true
        normalizedPoint = point
    }

    func close() {
        isEnabled = false
        isPinned = false
        normalizedPoint = CGPoint(x: 0.5, y: 0.5)
        pointer = nil
        overlayPosition = nil
    }

    func validateNativePixels(_ availability: LoupeNativePixelAvailability) {
        if magnification == .nativePixels, !availability.isAvailable {
            magnification = .twoTimes
        }
    }

    func selectMagnification(
        _ selection: LoupeMagnification,
        nativePixelAvailability: LoupeNativePixelAvailability
    ) {
        magnification = selection == .nativePixels && !nativePixelAvailability.isAvailable
            ? .twoTimes
            : selection
    }
}

struct InspectionLoupeControl: View {
    @ObservedObject var state: InspectionLoupeState
    @Binding var isPresented: Bool
    let nativePixelAvailability: LoupeNativePixelAvailability

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(state.isEnabled ? .orange : .white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .help("Inspection loupe controls (Command-Shift-M)")
        .accessibilityLabel("Inspection loupe")
        .accessibilityValue(state.isEnabled ? "Shown" : "Hidden")
        .accessibilityAddTraits(state.isEnabled ? .isSelected : [])
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inspection loupe").font(.headline)
                Toggle("Show loupe", isOn: $state.isEnabled)
                Picker("Magnification", selection: Binding(
                    get: { state.magnification },
                    set: {
                        state.selectMagnification(
                            $0, nativePixelAvailability: nativePixelAvailability
                        )
                    }
                )) {
                    ForEach(LoupeMagnification.allCases.filter { $0 != .nativePixels }) { value in
                        Text(value.label).tag(value)
                    }
                }
                Toggle("Nearest-neighbor scaling", isOn: $state.usesNearestNeighbor)
                    .help("Keep pixel edges sharp when enlarging. Turn off for smooth scaling.")
                Button("Center") { state.reset() }
                    .disabled(!state.canCenter)
                Text("Drag the target frame to move the inspected position. Drag the loupe to place it elsewhere. Compare Mode shows the same picture coordinate in A and B.")
                    .font(.caption)
                Text("Display-space preview • up to 10 fps. Captures may differ from the live HDR display and are not pixel-value measurements or frame-locked A/B samples.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("2×, 4×, 8× and 16× enlarge the displayed picture. Nearest-neighbor scaling keeps captured pixel edges sharp.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 320)
        }

    }

}

struct InspectionLoupeOverlay: View {
    @ObservedObject var state: InspectionLoupeState
    @ObservedObject var primary: PlayerController
    @ObservedObject var secondary: PlayerController
    @ObservedObject var primaryCapture: LoupeFrameCapture
    @ObservedObject var secondaryCapture: LoupeFrameCapture
    let isComparing: Bool
    let geometry: CompareDisplayGeometry
    let mode: CompareViewMode
    var wipePosition: Double = 0.5
    var overlayBlend: Double = 0.5
    @State private var dragOrigin: CGPoint?
    @State private var targetDragOrigin: CGPoint?
    var body: some View {
        let count: CGFloat = isComparing ? 2 : 1
        let width = min(180, max(64, (geometry.canvasSize.width - 24) / count))
        let lensSize = CGSize(width: width, height: min(140, max(60, geometry.canvasSize.height / 3)))
        let totalWidth = width * count + (isComparing ? 6 : 0)
        let totalHeight = lensSize.height + 26
        let overlaySize = CGSize(width: totalWidth, height: totalHeight)
        let center = state.overlayPosition.map {
            LoupeGeometry.clampedOverlayCenter(
                $0, canvasSize: geometry.canvasSize, overlaySize: overlaySize
            )
        } ?? LoupeGeometry.overlayCenter(
            canvasSize: geometry.canvasSize, overlaySize: overlaySize,
            pointer: state.pointer
        )

        ZStack(alignment: .topLeading) {
            if isComparing && mode == .sideBySide {
                target(for: .primary)
                target(for: .secondary)
            } else {
                target(for: targetSource)
            }

            HStack(spacing: 6) {
                lens(image: primaryCapture.image, source: isComparing ? "A" : "Picture", size: lensSize, pictureRect: pictureRect(for: .primary))
                if isComparing {
                    lens(image: secondaryCapture.image, source: "B", size: lensSize, pictureRect: pictureRect(for: .secondary))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                // The lens moves during the gesture, so its local coordinate space
                // would feed that movement back into the next translation sample.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        let origin = dragOrigin ?? center
                        if dragOrigin == nil { dragOrigin = origin }
                        state.moveOverlay(
                            to: CGPoint(
                                x: origin.x + value.translation.width,
                                y: origin.y + value.translation.height
                            ),
                            canvasSize: geometry.canvasSize, overlaySize: overlaySize
                        )
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .focusable()
            .onMoveCommand { direction in
                let step: CGFloat = 12
                let delta: CGSize
                switch direction {
                case .left: delta = CGSize(width: -step, height: 0)
                case .right: delta = CGSize(width: step, height: 0)
                case .up: delta = CGSize(width: 0, height: -step)
                case .down: delta = CGSize(width: 0, height: step)
                @unknown default: return
                }
                state.moveOverlay(
                    to: CGPoint(x: center.x + delta.width, y: center.y + delta.height),
                    canvasSize: geometry.canvasSize, overlaySize: overlaySize
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(isComparing ? "A and B" : "Picture") loupe, \(state.magnification.label)")
            .accessibilityHint("Drag to move. Focus and use arrow keys to move by small steps.")
            .position(center)
            .onAppear { refreshCaptures() }
            .onChange(of: primary.preparationID) { _, _ in refreshCaptures() }
            .onChange(of: secondary.preparationID) { _, _ in refreshCaptures() }
            .onChange(of: isComparing) { _, _ in refreshCaptures() }
            .onDisappear {
                dragOrigin = nil
                targetDragOrigin = nil
                primaryCapture.stop()
                secondaryCapture.stop()
            }
        }
        .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
        .coordinateSpace(name: "inspectionLoupeCanvas")
    }

    private var targetSource: CompareSource {
        guard isComparing else { return .primary }
        if mode == .secondary || (mode == .overlay && overlayBlend == 1) {
            return .secondary
        }
        if mode.isWipe, let pointer = state.pointer,
           geometry.secondaryClipRect(for: mode, wipePosition: wipePosition).contains(pointer) {
            return .secondary
        }
        return .primary
    }

    private func target(for source: CompareSource) -> some View {
        let rect = pictureRect(for: source)
        let center = CGPoint(
            x: rect.minX + state.normalizedPoint.x * rect.width,
            y: rect.minY + state.normalizedPoint.y * rect.height
        )
        return RoundedRectangle(cornerRadius: 3)
            .strokeBorder(.orange, lineWidth: 2)
            .background(.black.opacity(0.12))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.orange)
                    .allowsHitTesting(false)
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("inspectionLoupeCanvas"))
                    .onChanged { value in
                        let origin = targetDragOrigin ?? center
                        if targetDragOrigin == nil { targetDragOrigin = origin }
                        state.moveTarget(
                            to: CGPoint(x: origin.x + value.translation.width,
                                        y: origin.y + value.translation.height),
                            pictureRect: rect
                        )
                    }
                    .onEnded { _ in targetDragOrigin = nil }
            )
            .focusable()
            .onMoveCommand { direction in
                var location = center
                switch direction {
                case .left: location.x -= 4
                case .right: location.x += 4
                case .up: location.y -= 4
                case .down: location.y += 4
                @unknown default: return
                }
                state.moveTarget(to: location, pictureRect: rect)
            }
            .help("Drag to move the loupe target")
            .accessibilityLabel("\(isComparing ? (source == .primary ? "A" : "B") : "Picture") loupe target")
            .accessibilityHint("Drag to move the inspected position. Use arrow keys for small steps.")
            .position(center)
    }

    private func refreshCaptures() {
        primaryCapture.start(controller: primary)
        if isComparing { secondaryCapture.start(controller: secondary) }
        else { secondaryCapture.stop() }
    }

    private func pictureRect(for source: CompareSource) -> CGRect {
        CompareDisplayGeometry.aspectFitRect(
            aspectRatio: source == .primary ? geometry.primaryAspectRatio : geometry.secondaryAspectRatio,
            in: geometry.presentationClipRect(for: source, mode: isComparing ? mode : .primary)
        )
    }

    private func lens(image: CGImage?, source: String, size: CGSize, pictureRect: CGRect) -> some View {
        InspectionLoupeLens(
            image: image, source: source, size: size, pictureSize: pictureRect.size,
            normalizedPoint: state.normalizedPoint, magnification: state.magnification,
            usesNearestNeighbor: state.usesNearestNeighbor
        )
    }
}

/// The same lens used by the live overlay, isolated for hosted rendering tests.
struct InspectionLoupeLens: View {
    let image: CGImage?
    let source: String
    let size: CGSize
    let pictureSize: CGSize
    let normalizedPoint: CGPoint
    let magnification: LoupeMagnification
    var usesNearestNeighbor = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    let placement = LoupeGeometry.imagePlacement(
                        imageSize: CGSize(width: image.width, height: image.height),
                        pictureSize: pictureSize,
                        normalizedPoint: normalizedPoint,
                        lensSize: size,
                        magnification: magnification,
                        displayScale: displayScale
                    )
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(usesNearestNeighbor ? .none : .high)
                        .frame(width: placement.width, height: placement.height)
                        .offset(x: placement.minX, y: placement.minY)
                } else {
                    Text("Waiting for picture…")
                        .font(.caption2).foregroundStyle(.white)
                        .frame(width: size.width, height: size.height)
                }
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: .black, radius: 1)
                    .position(x: size.width / 2, y: size.height / 2)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            Text("\(source) · \(magnification.label) · \(magnification == .nativePixels ? "Verified decoded raster" : "Display preview")")
                .font(.caption2).foregroundStyle(.white)
                .frame(width: size.width, height: 26)
                .background(.black.opacity(0.85))
        }
        .overlay { Rectangle().stroke(.white.opacity(0.8), lineWidth: 1) }
        .shadow(color: .black.opacity(0.6), radius: 5)
    }
}
