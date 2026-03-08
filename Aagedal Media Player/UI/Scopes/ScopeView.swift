// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwiftUI view displaying waveform monitor and vectorscope side by side.

import SwiftUI

enum WaveformMode: String, CaseIterable {
    case luma = "Luma"
    case rgbParade = "RGB Parade"
}

struct ScopeView: View {
    @ObservedObject var frameCapture: FrameCapture
    @State private var waveformMode: WaveformMode = .luma
    @State private var waveformImage: CGImage?
    @State private var vectorscopeImage: CGImage?
    @State private var waveformGraticule: CGImage?
    @State private var vectorscopeGraticule: CGImage?

    private let scopeHeight: CGFloat = 256
    private let vectorscopeSize: CGFloat = 256

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Waveform", selection: $waveformMode) {
                    ForEach(WaveformMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Scopes
            HStack(spacing: 1) {
                // Waveform
                ZStack {
                    Color.black

                    if let graticule = waveformGraticule {
                        Image(decorative: graticule, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }

                    if let waveform = waveformImage {
                        Image(decorative: waveform, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(Rectangle())

                // Vectorscope
                ZStack {
                    Color.black

                    if let graticule = vectorscopeGraticule {
                        Image(decorative: graticule, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }

                    if let vectorscope = vectorscopeImage {
                        Image(decorative: vectorscope, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }
                }
                .aspectRatio(1.0, contentMode: .fit)
                .clipShape(Rectangle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .onChange(of: frameCapture.currentFrame) { _, newFrame in
            guard let frame = newFrame else {
                waveformImage = nil
                vectorscopeImage = nil
                return
            }
            computeScopes(from: frame)
        }
        .onAppear {
            // Generate graticules once
            let wfSize = CGSize(width: 480, height: 270)
            waveformGraticule = ScopeComputer.drawWaveformGraticule(size: wfSize)
            let vsSize = CGSize(width: 270, height: 270)
            vectorscopeGraticule = ScopeComputer.drawVectorscopeGraticule(size: vsSize)
        }
    }

    private func computeScopes(from frame: CGImage) {
        let wfSize = CGSize(width: 480, height: 270)
        let vsSize = CGSize(width: 270, height: 270)
        let mode = waveformMode

        Task.detached(priority: .userInitiated) {
            let wf: CGImage?
            switch mode {
            case .luma:
                wf = ScopeComputer.computeWaveform(from: frame, outputSize: wfSize)
            case .rgbParade:
                wf = ScopeComputer.computeRGBParade(from: frame, outputSize: wfSize)
            }

            let vs = ScopeComputer.computeVectorscope(from: frame, outputSize: vsSize)

            await MainActor.run {
                waveformImage = wf
                vectorscopeImage = vs
            }
        }
    }
}
