// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Combine

@MainActor
final class InspectionLoupeState: ObservableObject {
    @Published var isEnabled = false
    @Published var isPinned = false
    @Published var magnification: LoupeMagnification = .twoTimes
    @Published var normalizedPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var pointer: CGPoint?

    func follow(_ location: CGPoint, pictureRect: CGRect) {
        guard isEnabled, !isPinned,
              let point = LoupeGeometry.normalizedPoint(location: location, in: pictureRect) else { return }
        normalizedPoint = point
        pointer = location
    }

    func reset() {
        normalizedPoint = CGPoint(x: 0.5, y: 0.5)
        pointer = nil
        isPinned = true
    }

    func close() {
        isEnabled = false
        isPinned = false
        normalizedPoint = CGPoint(x: 0.5, y: 0.5)
        pointer = nil
    }
}

struct InspectionLoupeControl: View {
    @ObservedObject var state: InspectionLoupeState
    @Binding var isPresented: Bool

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
                Picker("Magnification", selection: $state.magnification) {
                    ForEach([LoupeMagnification.twoTimes, .fourTimes, .eightTimes]) { value in
                        Text(value.label).tag(value)
                    }
                }
                Toggle("Pin picture position", isOn: $state.isPinned)
                Slider(value: coordinate(\.x), in: 0...1) {
                    Text("Horizontal picture position")
                }
                .accessibilityValue("\(Int(state.normalizedPoint.x * 100)) percent")
                Slider(value: coordinate(\.y), in: 0...1) {
                    Text("Vertical picture position")
                }
                .accessibilityValue("\(Int(state.normalizedPoint.y * 100)) percent")
                Button("Center and pin") { state.reset() }
                Text("Move over the picture to inspect it. Pin the position to use playback controls. Compare Mode shows the same picture coordinate in A and B.")
                    .font(.caption)
                Text("Display-space preview • up to 10 fps. Captures may differ from the live HDR display and are not pixel-value measurements or frame-locked A/B samples.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 320)
        }

    }

    private func coordinate(_ keyPath: WritableKeyPath<CGPoint, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(state.normalizedPoint[keyPath: keyPath]) },
            set: {
                state.isPinned = true
                state.normalizedPoint[keyPath: keyPath] = CGFloat($0)
            }
        )
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
    var body: some View {
        let count: CGFloat = isComparing ? 2 : 1
        let width = min(180, max(64, (geometry.canvasSize.width - 24) / count))
        let lensSize = CGSize(width: width, height: min(140, max(60, geometry.canvasSize.height / 3)))
        let totalWidth = width * count + (isComparing ? 6 : 0)
        let totalHeight = lensSize.height + 26
        let pointer = state.pointer ?? CGPoint(x: geometry.canvasSize.width / 2, y: geometry.canvasSize.height / 2)
        let x = min(max(totalWidth / 2 + 8, pointer.x), max(totalWidth / 2 + 8, geometry.canvasSize.width - totalWidth / 2 - 8))
        let preferredY = pointer.y + totalHeight / 2 + 24
        let y = preferredY + totalHeight / 2 < geometry.canvasSize.height - 8
            ? preferredY : max(totalHeight / 2 + 8, pointer.y - totalHeight / 2 - 24)

        HStack(spacing: 6) {
            lens(image: primaryCapture.image, source: isComparing ? "A" : "Picture", size: lensSize, pictureRect: pictureRect(for: .primary))
            if isComparing {
                lens(image: secondaryCapture.image, source: "B", size: lensSize, pictureRect: pictureRect(for: .secondary))
            }
        }
        .position(x: x, y: y)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isComparing ? "A and B" : "Picture") loupe, \(state.magnification.label), \(state.isPinned ? "pinned" : "following pointer")")
        .onAppear { refreshCaptures() }
        .onChange(of: primary.preparationID) { _, _ in refreshCaptures() }
        .onChange(of: secondary.preparationID) { _, _ in refreshCaptures() }
        .onChange(of: isComparing) { _, _ in refreshCaptures() }
        .onDisappear {
            primaryCapture.stop()
            secondaryCapture.stop()
        }
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
            normalizedPoint: state.normalizedPoint, magnification: state.magnification
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
                        .interpolation(.none)
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
            Text("\(source) · \(magnification.label) · Display preview")
                .font(.caption2).foregroundStyle(.white)
                .frame(width: size.width, height: 26)
                .background(.black.opacity(0.85))
        }
        .overlay { Rectangle().stroke(.white.opacity(0.8), lineWidth: 1) }
        .shadow(color: .black.opacity(0.6), radius: 5)
    }
}
