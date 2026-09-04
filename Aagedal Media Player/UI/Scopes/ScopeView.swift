// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwiftUI view displaying waveform monitor and vectorscope side by side.

import SwiftUI

enum WaveformMode: String, CaseIterable, Sendable {
    case luma = "Luma"
    case parade = "Parade"
}

struct ScopeView: View {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var secondaryController: PlayerController
    @ObservedObject var primaryFrameCapture: FrameCapture
    @ObservedObject var secondaryFrameCapture: FrameCapture
    @ObservedObject var compareSession: CompareSessionController
    var isOverlay = false
    var transparentBackground = false
    /// Optional profiler hook fired only after both scope images are published.
    var onRender: ((CompareScopeSource) -> Void)? = nil
    @StateObject private var renderWorker = ScopeRenderWorker()
    @State private var waveformMode: WaveformMode = .luma
    @State private var vectorscopeGraticule: CGImage?
    @State private var pairedPrimarySample: ScopeFrameSample?
    @State private var pairedSecondarySample: ScopeFrameSample?

    private var selectedSource: CompareScopeSource {
        compareSession.isActive ? compareSession.scopeSource : .primary
    }

    private var selectedFrameCapture: FrameCapture {
        selectedSource == .secondary ? secondaryFrameCapture : primaryFrameCapture
    }

    private var isHDR: Bool {
        selectedSource != .difference && selectedFrameCapture.transferFunction != .sdr
    }

    private var transferLabel: String? {
        if selectedSource == .difference { return "DISPLAY RGB" }
        switch selectedFrameCapture.transferFunction {
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
                    .frame(width: 145)
                    .accessibilityLabel("Waveform display")

                    if compareSession.isActive {
                        scopeSourcePicker

                        if selectedSource == .difference {
                            differenceGainControl
                        }
                    }

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

                    if let waveform = renderWorker.waveformImage {
                        Image(decorative: waveform, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                    }

                    // Graticule drawn via Canvas so labels don't stretch
                    WaveformGraticuleView(isHDR: isHDR, peakNits: renderWorker.hdrPeakNits)
                }
                .clipShape(Rectangle())

                // Vectorscope — fixed 1:1 aspect ratio
                ZStack {
                    backgroundColor

                    if let vectorscope = renderWorker.vectorscopeImage {
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
        .onChange(of: primaryFrameCapture.currentSample) {
            handlePrimaryCapturedSample()
        }
        .onChange(of: secondaryFrameCapture.currentSample) {
            handleSecondaryCapturedSample()
        }
        .onChange(of: compareSession.scopeSource) {
            renderWorker.cancel(clearImages: false)
            resetDifferencePair()
            if selectedSource == .difference {
                refreshDifferencePair()
            }
            submitScopeFrame()
        }
        .onChange(of: compareSession.differenceGain) {
            guard selectedSource == .difference else { return }
            submitScopeFrame()
        }
        .onChange(of: renderWorker.renderSequence) {
            guard renderWorker.waveformImage != nil,
                  renderWorker.vectorscopeImage != nil else { return }
            onRender?(selectedSource)
        }
        .onChange(of: compareSession.isActive) {
            renderWorker.cancel(clearImages: false)
            resetDifferencePair()
            if compareSession.isActive, selectedSource == .difference {
                refreshDifferencePair()
            }
            submitScopeFrame()
        }
        .onChange(of: compareSession.mapping) {
            if selectedSource == .difference {
                renderWorker.cancel(clearImages: false)
            }
            resetDifferencePair()
            if selectedSource == .difference {
                refreshDifferencePair()
            }
            submitScopeFrame()
        }
        .onChange(of: primaryController.videoAspectRatio) {
            guard selectedSource != .secondary else { return }
            submitScopeFrame()
        }
        .onChange(of: secondaryController.videoAspectRatio) {
            guard selectedSource != .primary else { return }
            submitScopeFrame()
        }
        .onChange(of: waveformMode) {
            submitScopeFrame()
        }
        .onAppear {
            let res = UserDefaults.standard.value(for: AppSettings.scopeResolution)
            let w = CGFloat(res)
            let h = round(w * 9.0 / 16.0)
            vectorscopeGraticule = ScopeComputer.drawVectorscopeGraticule(size: CGSize(width: h, height: h))
            if selectedSource == .difference {
                refreshDifferencePair()
            }
            submitScopeFrame()
        }
        .onDisappear { renderWorker.cancel(clearImages: true) }
        .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
            guard let command = notification.appCommand,
                  case .toggleScopeParade = command else { return }
            waveformMode = waveformMode == .luma ? .parade : .luma
        }
    }

    private var scopeSourcePicker: some View {
        Picker("Scope source", selection: $compareSession.scopeSource) {
            ForEach(CompareScopeSource.allCases, id: \.self) { source in
                Text(source.label).tag(source)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 130)
        .help("\(selectedSourceLabel). Choose whether scopes inspect source A, source B, or their display-space difference.")
        .accessibilityLabel("Scope source")
    }

    private var selectedSourceLabel: String {
        switch selectedSource {
        case .primary:
            return "A: \(primaryController.mediaItem?.name ?? "Unavailable")"
        case .secondary:
            return "B: \(secondaryController.mediaItem?.name ?? "Unavailable")"
        case .difference:
            let primary = primaryController.mediaItem?.name ?? "Unavailable"
            let secondary = secondaryController.mediaItem?.name ?? "Unavailable"
            return "Δ: \(primary) / \(secondary)"
        }
    }

    private var differenceGainControl: some View {
        HStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { compareSession.differenceGain },
                    set: { compareSession.setDifferenceGain($0) }
                ),
                in: CompareSessionController.minimumDifferenceGain...CompareSessionController.maximumDifferenceGain,
                step: 0.5
            )
            .controlSize(.small)
            .frame(width: 65)

            Text("\(compareSession.differenceGain.formatted())×")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help("Amplify the display-space RGB difference. This is not an objective image-quality metric.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scope difference gain")
        .accessibilityValue("\(compareSession.differenceGain.formatted()) times")
    }

    private func submitScopeFrame() {
        let res = UserDefaults.standard.value(for: AppSettings.scopeResolution)
        let primarySample = selectedSource == .difference
            ? pairedPrimarySample
            : primaryFrameCapture.currentSample
        let secondarySample = selectedSource == .difference
            ? pairedSecondarySample
            : secondaryFrameCapture.currentSample
        renderWorker.submit(
            primary: scopeInput(
                sample: primarySample,
                frameCapture: primaryFrameCapture,
                controller: primaryController
            ),
            secondary: compareSession.isActive ? scopeInput(
                sample: secondarySample,
                frameCapture: secondaryFrameCapture,
                controller: secondaryController
            ) : nil,
            source: selectedSource,
            differenceGain: compareSession.differenceGain,
            mode: waveformMode,
            resolution: res
        )
    }

    private func scopeInput(
        sample: ScopeFrameSample?,
        frameCapture: FrameCapture,
        controller: PlayerController
    ) -> ScopeFrameInput {
        ScopeFrameInput(
            sdrFrame: sample?.sdrFrame,
            hdrFrame: sample?.hdrFrame,
            transferFunction: frameCapture.transferFunction,
            displayAspectRatio: controller.videoAspectRatio
        )
    }

    private func handlePrimaryCapturedSample() {
        switch selectedSource {
        case .primary:
            submitScopeFrame()
        case .secondary:
            return
        case .difference:
            guard refreshDifferencePair() else { return }
            submitScopeFrame()
        }
    }

    private func handleSecondaryCapturedSample() {
        switch selectedSource {
        case .primary:
            return
        case .secondary:
            submitScopeFrame()
        case .difference:
            // A owns the comparison timeline. A new B capture is matched to
            // the current A frame instead of attempting to invert a clamped
            // A→B mapping at an overlap boundary.
            guard refreshDifferencePair() else { return }
            submitScopeFrame()
        }
    }

    @discardableResult
    private func refreshDifferencePair() -> Bool {
        guard compareSession.isActive else { return false }
        let tolerance = ScopeFramePairer.tolerance(
            primaryFrameRate: primaryController.mediaItem?
                .metadata?.primaryVideoStream?.frameRate?.value,
            secondaryFrameRate: secondaryController.mediaItem?
                .metadata?.primaryVideoStream?.frameRate?.value
        )

        guard let primary = primaryFrameCapture.currentSample,
              let secondary = ScopeFramePairer.closestSecondary(
                to: primary,
                mapping: compareSession.mapping,
                secondaryDuration: secondaryController.mediaItem?.durationSeconds ?? 0,
                candidates: secondaryFrameCapture.recentSamplesSnapshot(),
                tolerance: tolerance
              ) else { return false }
        // Pairing state needs display-space SDR pixels only. Avoid extending
        // the lifetime of an expensive Float HDR payload via SwiftUI state.
        pairedPrimarySample = ScopeFrameSample(
            sequence: primary.sequence,
            playbackTime: primary.playbackTime,
            timestampUncertainty: primary.timestampUncertainty,
            timestampQuality: primary.timestampQuality,
            sdrFrame: primary.sdrFrame,
            hdrFrame: nil
        )
        pairedSecondarySample = secondary
        return true
    }

    private func resetDifferencePair() {
        pairedPrimarySample = nil
        pairedSecondarySample = nil
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
