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
                    WaveformGraticuleView()
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
                waveformImage = nil
                vectorscopeImage = nil
                return
            }
            computeScopes(from: frame)
        }
        .onChange(of: waveformMode) {
            if let frame = frameCapture.currentFrame {
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
}

// MARK: - Waveform Graticule (Canvas-based, never stretches labels)

private struct WaveformGraticuleView: View {
    private let ireValues: [Int] = [0, 25, 50, 75, 100]
    private let lineColor = Color(white: 0.25)
    private let labelColor = Color(white: 0.4)

    var body: some View {
        Canvas { context, size in
            let lineStyle = StrokeStyle(lineWidth: 0.5)

            for ire in ireValues {
                let y = size.height * (1.0 - CGFloat(ire) / 100.0)

                // Horizontal line
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), style: lineStyle)

                // Label
                let text = Text("\(ire)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(labelColor)
                context.draw(text, at: CGPoint(x: 3, y: y + 8), anchor: .topLeading)
            }
        }
    }
}
