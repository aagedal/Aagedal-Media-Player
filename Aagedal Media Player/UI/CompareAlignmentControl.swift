// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CompareAlignmentControl: View {
    @ObservedObject var session: CompareSessionController
    @ObservedObject var primary: PlayerController
    @State private var isPresented = false
    @State private var offsetText = "0"
    @State private var usesFrames = false

    private var rate: TimecodeRate {
        TimecodeRate(frameRate: primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value ?? 30)
    }

    private var enteredSeconds: Double? {
        parsedSeconds(usesFrames: usesFrames)
    }

    private func parsedSeconds(usesFrames: Bool) -> Double? {
        let seconds: Double
        if usesFrames {
            guard let frames = Int64(offsetText.trimmingCharacters(in: .whitespaces)) else { return nil }
            seconds = rate.seconds(forFrameCount: frames)
        } else {
            guard let value = Double(offsetText) else { return nil }
            seconds = value
        }
        guard rate.frameCount(forSeconds: abs(seconds)) != nil else { return nil }
        return seconds
    }

    var body: some View {
        Button {
            refreshText()
            isPresented = true
        } label: {
            Image(systemName: "arrow.left.arrow.right")
        }
        .buttonStyle(.plain)
        .help("Adjust comparison alignment")
        .accessibilityLabel("Adjust comparison alignment")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Comparison alignment").font(.headline)
                Text("B time = A time + offset. Positive values show a later point in B; negative values delay B's start.")
                    .font(.caption)
                Picker("Offset units", selection: $usesFrames) {
                    Text("Seconds").tag(false)
                    Text("A frames").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: usesFrames) { oldValue, _ in
                    if let seconds = parsedSeconds(usesFrames: oldValue) {
                        refreshText(offset: seconds)
                    } else {
                        refreshText()
                    }
                }
                HStack {
                    TextField("Signed offset", text: $offsetText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(usesFrames ? "Offset in source A frames" : "Offset in seconds")
                        .onSubmit { applyOffset() }
                    Button("Apply") { applyOffset() }
                        .disabled(enteredSeconds == nil)
                }
                HStack {
                    Button("−1 A frame") { nudge(-1) }
                    Button("+1 A frame") { nudge(1) }
                    Spacer()
                    Button("Automatic") {
                        session.setManualOffset(nil, primary: primary)
                        refreshText()
                    }
                }
                Text("B = A + \((session.mapping?.offset ?? 0).formatted(.number.precision(.fractionLength(0...6)))) seconds")
                    .font(.caption.monospacedDigit())
                Text("Applies to this pair until B is replaced or Compare Mode closes. Existing review notes retain their recorded source positions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 390)
        }
    }

    private func applyOffset() {
        guard let enteredSeconds else { return }
        session.setManualOffset(enteredSeconds, primary: primary)
        refreshText()
    }

    private func nudge(_ frames: Int64) {
        session.setManualOffset(
            (session.mapping?.offset ?? 0) + rate.seconds(forFrameCount: frames),
            primary: primary
        )
        refreshText()
    }

    private func refreshText(offset: Double? = nil) {
        let offset = offset ?? session.mapping?.offset ?? 0
        offsetText = usesFrames
            ? String(rate.frameCount(forSeconds: offset) ?? 0)
            : String(offset)
    }
}
