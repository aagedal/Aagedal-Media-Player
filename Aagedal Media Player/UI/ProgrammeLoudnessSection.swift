// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ProgrammeLoudnessSection: View {
    let item: MediaItem
    let streams: [MediaMetadata.AudioStream]
    @ObservedObject var controller: ProgrammeLoudnessController
    @Binding var measureSelectedRange: Bool
    @Binding var isPresented: Bool
    let selectedRange: FFmpegService.LoudnessRange?

    private var duration: Double? { item.metadata?.duration }
    private var hasDuration: Bool { duration.map { $0.isFinite && $0 > 0 } ?? false }

    var body: some View {
        Section("Programme Loudness") {
            Text("Measure mono tracks together as one stereo or 5.1 programme. Confirm the speaker assignments; unassigned tracks are excluded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let mapping = controller.mapping {
                Picker("Programme Layout", selection: Binding(
                    get: { mapping.layout },
                    set: { controller.selectLayout($0) }
                )) {
                    ForEach(ProgrammeLoudnessLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .accessibilityHint("Choose the programme speaker layout. Track assignments reset when the layout changes.")

                ForEach(Array(mapping.layout.channelRoles.enumerated()), id: \.offset) { channel, role in
                    Picker(Self.speakerName(role), selection: Binding(
                        get: { mapping.audioStreamIndices[channel] },
                        set: { controller.assignStream($0, toChannel: channel) }
                    )) {
                        Text("Choose Track").tag(-1)
                        ForEach(streams.indices.filter { streams[$0].channels == 1 }, id: \.self) { index in
                            Text(Self.trackLabel(streams[index], index: index)).tag(index)
                        }
                    }
                    .accessibilityLabel("Programme \(Self.speakerName(role)) track")
                }
                if let message = controller.mappingError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Measurement Scope").font(.caption).foregroundStyle(.secondary)
                Picker("Programme measurement scope", selection: $measureSelectedRange) {
                    Text("Whole File").tag(false)
                    Text("In–Out Range").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Programme loudness measurement scope")
                .accessibilityHint("Changes the scope for programme and individual track measurements.")
            }
            if measureSelectedRange {
                Text(selectedRange.map { String(format: "Selected range: %.3f–%.3f s", $0.start, $0.end) }
                     ?? "Set valid In and Out points within the file to measure a range.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !hasDuration {
                Text("Programme analysis requires a known file duration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Original source levels are measured. Missing time in an assigned channel is treated as silence. Playback volume and mute do not affect the result.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let result = controller.result {
                measurement("Programme Integrated Loudness", value: result.loudness.integratedLoudness, unit: "LUFS")
                measurement("Programme Loudness Range", value: result.loudness.loudnessRange, unit: "LU")
                measurement("Programme True Peak", value: result.loudness.truePeak, unit: "dBTP")
            }
            if controller.isAnalyzing {
                HStack {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text("Analyzing programme loudness…").font(.caption)
                }
                Button("Cancel Programme Analysis") { controller.cancel(resetResult: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                if let error = controller.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    guard isPresented else { return }
                    controller.measure(duration: duration, range: measureSelectedRange ? selectedRange : nil)
                } label: {
                    Label(controller.result == nil ? "Measure Programme LUFS" : "Measure Programme Again",
                          systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(controller.mappingError != nil || !hasDuration || (measureSelectedRange && selectedRange == nil))
                .accessibilityHint("Measures the assigned mono tracks as one programme using the selected speaker layout.")
            }
        }
        .onAppear { controller.configure(url: item.url, audioStreams: streams) }
        .onChange(of: item.url) { controller.configure(url: item.url, audioStreams: streams) }
        .onChange(of: streams) { controller.configure(url: item.url, audioStreams: streams) }
    }

    private func measurement(_ label: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f %@", value, unit))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private static func speakerName(_ role: String) -> String {
        switch role {
        case "FL": "Left (L)"
        case "FR": "Right (R)"
        case "FC": "Centre (C)"
        case "LFE": "LFE"
        case "SL": "Left Surround (Ls)"
        case "SR": "Right Surround (Rs)"
        default: role
        }
    }

    private static func trackLabel(_ stream: MediaMetadata.AudioStream, index: Int) -> String {
        let name = stream.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return "Track \(index + 1): \(name)" }
        return "Track \(index + 1)"
    }
}
