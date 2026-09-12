// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Presentation-only live source meter. The owner supplies immutable snapshots
/// and actions; this view does not own playback, decoding, or DSP work.
struct LiveAudioMeterView: View {
    struct Actions {
        var selectSource: @MainActor @Sendable (String) -> Void = { _ in }
        var selectPreset: @MainActor @Sendable (LiveAudioMeterReference.Preset) -> Void = { _ in }
        var setCustomLoudnessTarget: @MainActor @Sendable (Double) -> Void = { _ in }
        var setCustomTruePeakCeiling: @MainActor @Sendable (Double?) -> Void = { _ in }
        var clearMaxima: @MainActor @Sendable () -> Void = {}
        var resetMeters: @MainActor @Sendable () -> Void = {}
        var retry: @MainActor @Sendable () -> Void = {}
        var close: @MainActor @Sendable () -> Void = {}
    }

    let state: LiveAudioMeterViewState
    let preferences: LiveAudioMeterPreferences
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            status

            if !state.channels.isEmpty {
                channelMeters
                loudnessMeters
                thresholdAssessment
            }

            diagnostics
            actionBar
        }
        .padding(16)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 460)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Audio Meter").font(.title2.bold())
                Text("Decoded source PCM · \(state.measuredSourceLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Close", action: actions.close)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Closes the live meter and stops its measurement worker.")
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Measured source").foregroundStyle(.secondary)
                Picker("Measured source", selection: Binding(
                    get: { state.selectedSourceID },
                    set: actions.selectSource
                )) {
                    ForEach(state.sourceOptions) { source in
                        Text(source.detail.map { "\(source.label) · \($0)" } ?? source.label)
                            .tag(source.id)
                    }
                }
                .labelsHidden()
                .accessibilityHint("Selects the independently measured A or B source. It does not change audible monitoring.")
            }

            GridRow {
                Text("Reference").foregroundStyle(.secondary)
                Picker("Reference preset", selection: Binding(
                    get: { preferences.preset },
                    set: actions.selectPreset
                )) {
                    ForEach(LiveAudioMeterReference.Preset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .accessibilityHint("Changes reference labels and guides only. It does not change audio or measured values.")
            }

            if preferences.preset == .custom {
                GridRow {
                    Text("Loudness target").foregroundStyle(.secondary)
                    HStack {
                        TextField("Custom loudness target", value: Binding(
                            get: { preferences.customLoudnessTarget },
                            set: actions.setCustomLoudnessTarget
                        ), format: .number.precision(.fractionLength(1)))
                        .frame(width: 90)
                        Text("LUFS").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Toggle("True-peak ceiling", isOn: Binding(
                        get: { preferences.customTruePeakCeiling != nil },
                        set: { enabled in
                            actions.setCustomTruePeakCeiling(enabled
                                ? preferences.customTruePeakCeiling ?? -1
                                : nil)
                        }
                    ))
                    HStack {
                        if let ceiling = preferences.customTruePeakCeiling {
                            TextField("Custom true-peak ceiling", value: Binding(
                                get: { ceiling },
                                set: { actions.setCustomTruePeakCeiling($0) }
                            ), format: .number.precision(.fractionLength(1)))
                            .frame(width: 90)
                            Text("dBTP").foregroundStyle(.secondary)
                        } else {
                            Text("No ceiling").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusSymbol).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(state.status.title).font(.headline)
                    if let position = state.status.position {
                        Text("at \(position)").foregroundStyle(.secondary)
                    }
                }
                switch state.status {
                case .unavailable(let reason, let diagnostic):
                    Text(reason)
                    if let diagnostic { Text(diagnostic).font(.caption).foregroundStyle(.secondary) }
                case .warmingUp(_, let momentaryReady, let shortTermReady):
                    Text("Momentary \(momentaryReady ? "ready" : "warming") · Short-term \(shortTermReady ? "ready" : "warming")")
                        .font(.caption).foregroundStyle(.secondary)
                case .paused:
                    Text("Readings are frozen; paused wall time is excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                case .buffering:
                    Text("Readings are frozen while source samples are unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                case .ended:
                    Text("Final readings are frozen for this measurement segment.")
                        .font(.caption).foregroundStyle(.secondary)
                case .active:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var channelMeters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Channel peaks").font(.headline)
                Spacer()
                Text("Bar · held marker · segment maximum")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(state.channels) { channel in
                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.label).font(.subheadline.bold())
                    PeakMeterRow(label: "SP", unit: "dBFS", level: channel.samplePeak)
                    PeakMeterRow(label: "TP", unit: "dBTP", level: channel.truePeak)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var loudnessMeters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live loudness").font(.headline)
                Spacer()
                Text("Programme reference \(MeterText.level(state.reference.loudnessTarget)) \(state.reference.loudnessUnit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LoudnessMeterRow(
                label: "Momentary (400 ms)", value: state.loudness.momentary,
                maximum: state.loudness.maximumMomentary, target: state.reference.loudnessTarget,
                unit: state.reference.loudnessUnit
            )
            LoudnessMeterRow(
                label: "Short-term (3 s)", value: state.loudness.shortTerm,
                maximum: state.loudness.maximumShortTerm, target: state.reference.loudnessTarget,
                unit: state.reference.loudnessUnit
            )
            Text("The line is a programme reference, not a Momentary or Short-term pass region.")
                .font(.caption).foregroundStyle(.secondary)
            if state.reference.dialogueAssessmentUnavailable {
                Label("Dialogue assessment unavailable", systemImage: "exclamationmark.circle")
                    .font(.caption)
            }
        }
    }

    private var thresholdAssessment: some View {
        let assessment = state.truePeakAssessment
        return Label(
            assessment.text,
            systemImage: assessment.isExceeded ? "exclamationmark.triangle.fill" : "info.circle"
        )
        .foregroundStyle(assessment.isExceeded ? Color.orange : Color.secondary)
        .font(.callout)
        .accessibilityValue(assessment.diagnosticText)
    }

    @ViewBuilder private var diagnostics: some View {
        if let provenance = state.provenance {
            DisclosureGroup("Measurement provenance") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    provenanceRow("Source", provenance.sourceIdentity)
                    provenanceRow("Audio stream", "\(provenance.streamIndex) · \(provenance.trackLabel)")
                    provenanceRow("Format", "\(provenance.sampleRate) Hz · \(provenance.channelLayout)")
                    provenanceRow("Channel map", provenance.channelMap.joined(separator: ", "))
                    provenanceRow("Decoder", "\(provenance.decoder) \(provenance.decoderVersion)")
                    provenanceRow("Algorithm", provenance.algorithm)
                    provenanceRow("Generation", String(provenance.measurementGeneration))
                    provenanceRow("Source interval", provenance.sourceInterval)
                    provenanceRow("Segment start", provenance.segmentStart)
                    provenanceRow("Threshold math", state.truePeakAssessment.diagnosticText)
                }
                .font(.caption)
                .textSelection(.enabled)
            }
        }
        if !state.diagnostics.isEmpty {
            DisclosureGroup("Diagnostics") {
                ForEach(state.diagnostics) { diagnostic in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: diagnosticSymbol(diagnostic.severity)).accessibilityHidden(true)
                        Text("\(diagnostic.label): \(diagnostic.detail)")
                    }
                    .font(.caption)
                    .textSelection(.enabled)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        Text("Source measurement only. These live M/S readings and reference guides do not establish programme, delivery, EBU Mode, or CALM compliance.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionBar: some View {
        HStack {
            Button("Clear Maxima", action: actions.clearMaxima)
                .disabled(state.channels.isEmpty)
                .accessibilityHint("Clears peak and loudness maxima and threshold latches without resetting meter windows.")
            Button("Reset Meters", action: actions.resetMeters)
                .disabled(state.channels.isEmpty)
                .accessibilityHint("Starts a new measurement segment and clears meter filters, windows, bars, maxima, and latches.")
            if case .unavailable = state.status {
                Button("Retry", action: actions.retry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Starts a new meter generation for the selected source.")
            }
            Spacer()
        }
    }

    @ViewBuilder private func provenanceRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private var statusSymbol: String {
        switch state.status {
        case .unavailable: "exclamationmark.triangle"
        case .warmingUp, .buffering: "ellipsis.circle"
        case .active: "waveform"
        case .paused: "pause.circle"
        case .ended: "checkmark.circle"
        }
    }

    private func diagnosticSymbol(_ severity: LiveAudioMeterDiagnostic.Severity) -> String {
        switch severity {
        case .information: "info.circle"
        case .qualification: "exclamationmark.circle"
        case .failure: "xmark.octagon"
        }
    }
}

private struct PeakMeterRow: View {
    let label: String
    let unit: String
    let level: LiveAudioMeterLevelState

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(.caption, design: .monospaced).bold()).frame(width: 24)
            MeterTrack(value: level.bar, marker: level.marker, lowerBound: -60, upperBound: 6)
                .frame(height: 10)
            Text(MeterText.reading(level.current, unit: unit)).frame(width: 104, alignment: .trailing)
            Text("Max \(MeterText.reading(level.maximum, unit: unit))")
                .frame(width: 132, alignment: .trailing)
        }
        .font(.system(.caption, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "SP" ? "Sample peak" : "True peak")")
        .accessibilityValue("Current \(MeterText.reading(level.current, unit: unit)); bar \(MeterText.reading(level.bar, unit: unit)); marker \(MeterText.reading(level.marker, unit: unit)); maximum \(MeterText.reading(level.maximum, unit: unit))")
    }
}

private struct LoudnessMeterRow: View {
    let label: String
    let value: Double?
    let maximum: Double?
    let target: Double
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 132, alignment: .leading)
            MeterTrack(value: value, marker: target, lowerBound: -36, upperBound: -6)
                .frame(height: 10)
            Text(MeterText.reading(value, unit: unit)).frame(width: 104, alignment: .trailing)
            Text("Max \(MeterText.reading(maximum, unit: unit))")
                .frame(width: 132, alignment: .trailing)
        }
        .font(.system(.caption, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("Current \(MeterText.reading(value, unit: unit)); maximum \(MeterText.reading(maximum, unit: unit)); programme reference \(MeterText.reading(target, unit: unit))")
    }
}

private struct MeterTrack: View {
    let value: Double?
    let marker: Double?
    let lowerBound: Double
    let upperBound: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                if let value {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * fraction(value))
                }
                if let marker {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2)
                        .offset(x: max(0, geometry.size.width * fraction(marker) - 1))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fraction(_ level: Double) -> Double {
        guard level != -.infinity else { return 0 }
        return min(1, max(0, (level - lowerBound) / (upperBound - lowerBound)))
    }
}

private enum MeterText {
    static func level(_ value: Double) -> String {
        value == -.infinity ? "−∞" : String(format: "%.1f", value).replacingOccurrences(of: "-", with: "−")
    }

    static func reading(_ value: Double?, unit: String) -> String {
        guard let value else { return "Unavailable" }
        return "\(level(value)) \(unit)"
    }
}
