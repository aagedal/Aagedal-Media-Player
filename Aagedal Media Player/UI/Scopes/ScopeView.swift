// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwiftUI view displaying waveform monitor and vectorscope side by side.

import SwiftUI

enum WaveformMode: String, CaseIterable {
    case luma = "Luma"
    case parade = "Parade"
}

struct ScopeView: View {
    @ObservedObject var frameCapture: FrameCapture
    var isOverlay = false
    var transparentBackground = false
    @State private var waveformMode: WaveformMode = .luma
    @State private var waveformImage: CGImage?
    @State private var vectorscopeImage: CGImage?
    @State private var vectorscopeGraticule: CGImage?
    @State private var hdrPeakNits: Float = 10000

    private var isHDR: Bool {
        frameCapture.transferFunction != .sdr
    }

    private var transferLabel: String? {
        switch frameCapture.transferFunction {
        case .pq: return "PQ"
        case .hlg: return "HLG"
        case .sdr: return nil
        }
    }

    private var backgroundColor: Color {
        transparentBackground ? Color.black.opacity(0.5) : Color.black
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar (window mode only)
            if !isOverlay {
                HStack {
                    Picker("", selection: $waveformMode) {
                        ForEach(WaveformMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    if let label = transferLabel {
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()
            }

            // Scopes
            HStack(spacing: 1) {
                // Waveform — stretches to fill remaining width
                ZStack {
                    backgroundColor

                    if let waveform = waveformImage {
                        Image(decorative: waveform, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }

                    // Graticule drawn via Canvas so labels don't stretch
                    WaveformGraticuleView(isHDR: isHDR, peakNits: hdrPeakNits)
                }
                .clipShape(Rectangle())

                // Vectorscope — fixed 1:1 aspect ratio
                ZStack {
                    backgroundColor

                    if let vectorscope = vectorscopeImage {
                        Image(decorative: vectorscope, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }

                    if let graticule = vectorscopeGraticule {
                        Image(decorative: graticule, scale: 2.0)
                            .resizable()
                            .interpolation(.high)
                    }
                }
                .aspectRatio(1.0, contentMode: .fit)
                .clipShape(Rectangle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isOverlay ? Color.clear : Color.black)
        }
        .onChange(of: frameCapture.currentFrame) { _, newFrame in
            guard let frame = newFrame else {
                if !isHDR {
                    waveformImage = nil
                    vectorscopeImage = nil
                }
                return
            }
            if isHDR {
                // Only update vectorscope from SDR frame in HDR mode
                computeVectorscopeOnly(from: frame)
            } else {
                computeScopes(from: frame)
            }
        }
        .onChange(of: frameCapture.currentHDRFrame) { _, newFrame in
            guard let frame = newFrame else {
                if isHDR {
                    waveformImage = nil
                }
                return
            }
            hdrPeakNits = frame.contentPeakNits
            computeHDRScopes(from: frame)
        }
        .onChange(of: waveformMode) {
            if isHDR {
                if let frame = frameCapture.currentHDRFrame {
                    computeHDRScopes(from: frame)
                }
            } else if let frame = frameCapture.currentFrame {
                computeScopes(from: frame)
            }
        }
        .onAppear {
            let res = UserDefaults.standard.integer(forKey: "scopeResolution")
            let w = CGFloat(res > 0 ? res : 720)
            let h = round(w * 9.0 / 16.0)
            vectorscopeGraticule = ScopeComputer.drawVectorscopeGraticule(size: CGSize(width: h, height: h))
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleScopeParade)) { _ in
            waveformMode = waveformMode == .luma ? .parade : .luma
        }
    }

    private func computeScopes(from frame: CGImage) {
        let res = UserDefaults.standard.integer(forKey: "scopeResolution")
        let w = CGFloat(res > 0 ? res : 720)
        let h = round(w * 9.0 / 16.0)
        let wfSize = CGSize(width: w, height: h)
        let vsSize = CGSize(width: h, height: h)
        let mode = waveformMode

        Task.detached(priority: .userInitiated) {
            let wf: CGImage?
            switch mode {
            case .luma:
                wf = ScopeComputer.computeWaveform(from: frame, outputSize: wfSize)
            case .parade:
                wf = ScopeComputer.computeParade(from: frame, outputSize: wfSize)
            }

            let vs = ScopeComputer.computeVectorscope(from: frame, outputSize: vsSize)

            await MainActor.run {
                waveformImage = wf
                vectorscopeImage = vs
            }
        }
    }

    private func computeHDRScopes(from frame: HDRFrameData) {
        let res = UserDefaults.standard.integer(forKey: "scopeResolution")
        let w = CGFloat(res > 0 ? res : 720)
        let h = round(w * 9.0 / 16.0)
        let wfSize = CGSize(width: w, height: h)
        let mode = waveformMode

        Task.detached(priority: .userInitiated) {
            let wf: CGImage?
            switch mode {
            case .luma:
                wf = ScopeComputer.computeHDRWaveform(from: frame, outputSize: wfSize)
            case .parade:
                wf = ScopeComputer.computeHDRParade(from: frame, outputSize: wfSize)
            }

            await MainActor.run {
                waveformImage = wf
            }
        }
    }

    private func computeVectorscopeOnly(from frame: CGImage) {
        let res = UserDefaults.standard.integer(forKey: "scopeResolution")
        let w = CGFloat(res > 0 ? res : 720)
        let h = round(w * 9.0 / 16.0)
        let vsSize = CGSize(width: h, height: h)

        Task.detached(priority: .userInitiated) {
            let vs = ScopeComputer.computeVectorscope(from: frame, outputSize: vsSize)
            await MainActor.run {
                vectorscopeImage = vs
            }
        }
    }
}

// MARK: - Waveform Graticule (Canvas-based, never stretches labels)

private struct WaveformGraticuleView: View {
    var isHDR: Bool = false
    var peakNits: Float = 10000

    private let ireValues: [Int] = [0, 25, 50, 75, 100]
    private let lineColor = Color(white: 0.25)
    private let labelColor = Color(white: 0.4)

    // Decade-based HDR nit markers — filtered at draw time to only show those ≤ peakNits.
    // Covers each decade: 0.1–1, 1–10, 10–100, 100–1K, 1K–10K.
    private let allHDRMarkers: [(nits: Float, label: String, isMajor: Bool)] = [
        (0.1,    "0.1",  true),
        (1,      "1",    true),
        (10,     "10",   true),
        (100,    "100",  true),
        (203,    "203",  false),   // HDR reference white
        (1000,   "1K",   true),
        (4000,   "4K",   false),
        (10000,  "10K",  true),
    ]

    var body: some View {
        Canvas { context, size in
            if isHDR {
                drawHDRGraticule(context: context, size: size)
            } else {
                drawSDRGraticule(context: context, size: size)
            }
        }
    }

    private func drawSDRGraticule(context: GraphicsContext, size: CGSize) {
        let lineStyle = StrokeStyle(lineWidth: 0.5)

        for ire in ireValues {
            let y = size.height * (1.0 - CGFloat(ire) / 100.0)

            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(lineColor), style: lineStyle)

            let text = Text("\(ire)")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(labelColor)
            context.draw(text, at: CGPoint(x: 3, y: y + 8), anchor: .topLeading)
        }
    }

    private func drawHDRGraticule(context: GraphicsContext, size: CGSize) {
        let normalLineStyle = StrokeStyle(lineWidth: 0.5)
        let refWhiteStyle = StrokeStyle(lineWidth: 0.5, dash: [4, 3])
        let minNits = ScopeComputer.hdrMinNits
        let logMin = CGFloat(log10(minNits))
        let logMax = CGFloat(log10(peakNits))
        let logRange = logMax - logMin
        guard logRange > 0 else { return }

        // Filter markers to those within the current scale range
        let markers = allHDRMarkers.filter { $0.nits >= minNits && $0.nits <= peakNits }

        for marker in markers {
            let normalized = (CGFloat(log10(marker.nits)) - logMin) / logRange  // 0…1
            let y = size.height * (1.0 - normalized)

            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))

            if marker.nits == 203 {
                // Reference white — dashed, slightly brighter
                context.stroke(path, with: .color(Color(white: 0.35)), style: refWhiteStyle)
            } else {
                context.stroke(path, with: .color(lineColor), style: normalLineStyle)
            }

            // Position label just below the line, except for the top marker which goes above
            let isTopMarker = (marker.nits == peakNits)
            let labelY = isTopMarker ? y + 2 : y + 8
            let anchor: UnitPoint = isTopMarker ? .topLeading : .topLeading

            let text = Text(marker.label)
                .font(.system(size: 9, weight: marker.nits == 203 ? .medium : .regular, design: .monospaced))
                .foregroundColor(marker.nits == 203 ? Color(white: 0.5) : labelColor)
            context.draw(text, at: CGPoint(x: 3, y: labelY), anchor: anchor)
        }
    }
}
