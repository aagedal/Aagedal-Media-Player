// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PlaybackInspectorView: View {
    @ObservedObject var primary: PlayerController
    @ObservedObject var comparison: CompareSessionController
    @State private var selectsSecondary = false

    private var selectedPlayer: PlayerController {
        selectsSecondary && comparison.isActive ? comparison.secondaryController : primary
    }

    var body: some View {
        VStack(spacing: 0) {
            if comparison.isActive {
                Picker("Playback source", selection: $selectsSecondary) {
                    Text("Source A").tag(false)
                    Text("Source B").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(12)
                .accessibilityIdentifier("playback-inspector-source")
            }
            PlaybackSettingsView(controller: selectedPlayer, primary: primary, comparison: comparison)
                .id(ObjectIdentifier(selectedPlayer))
        }
        .accessibilityIdentifier("playback-inspector")
        .onChange(of: comparison.isActive) { _, active in
            if !active { selectsSecondary = false }
        }
    }
}

private struct PlaybackSettingsView: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject var primary: PlayerController
    @ObservedObject var comparison: CompareSessionController
    @AppStorage(AppSettings.audioWaveformBoost.key)
    private var waveformBoost = AppSettings.audioWaveformBoost.defaultValue
    @AppStorage(AppSettings.audioWaveformColor.key)
    private var waveformColor = AppSettings.audioWaveformColor.defaultValue

    private var monitoringVolume: Binding<Double> {
        Binding(get: { primary.volume }, set: { value in
            if comparison.isActive {
                comparison.setMonitoringVolume(value, primary: primary)
            } else {
                primary.volume = value
            }
        })
    }

    private var monitoringMute: Binding<Bool> {
        Binding(get: { primary.isMuted }, set: { value in
            guard value != primary.isMuted else { return }
            if comparison.isActive {
                comparison.toggleMonitoringMute(primary: primary)
            } else {
                primary.isMuted = value
            }
        })
    }

    private var canAdjust: Bool {
        controller.supportsAudioSyncOffset && controller.isReady && !controller.audioTrackOptions.isEmpty
    }

    private var offset: Binding<Double> {
        Binding(get: { controller.audioSyncOffsetMilliseconds },
                set: { controller.setAudioSyncOffset(milliseconds: $0) })
    }

    private var direction: String {
        let value = controller.audioSyncOffsetMilliseconds
        if value == 0 { return "No timing adjustment" }
        return value > 0 ? "Audio later" : "Audio earlier"
    }

    var body: some View {
        List {
            Section("Playback") {
                if let name = controller.mediaItem?.name {
                    Text(name).font(.callout).textSelection(.enabled)
                }
                if let backend = controller.playbackBackend {
                    LabeledContent("Engine", value: backend.displayName)
                } else {
                    Text("Preparing playback…").foregroundStyle(.secondary)
                }
            }
            Section("Audio output") {
                if comparison.isActive {
                    Picker("Listen to", selection: Binding(
                        get: { comparison.audioSource },
                        set: { comparison.selectAudioSource($0, primary: primary) }
                    )) {
                        ForEach(CompareAudioSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .accessibilityIdentifier("playback-inspector-audio-source")
                }
                Toggle("Mute", isOn: monitoringMute)
                    .accessibilityIdentifier("playback-inspector-mute")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(primary.volume))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: monitoringVolume, in: 0...100)
                        .accessibilityLabel("Playback volume")
                        .accessibilityValue("\(Int(primary.volume)) percent")
                        .accessibilityIdentifier("playback-inspector-volume")
                }
                if comparison.isActive {
                    Text("Volume and mute apply to the comparison's listening source.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Waveform") {
                Picker("Color", selection: $waveformColor) {
                    ForEach(AudioWaveformColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color.rawValue)
                    }
                }
                .accessibilityIdentifier("playback-inspector-waveform-color")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Quiet detail")
                        Spacer()
                        Text("\(Int(waveformBoost))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $waveformBoost, in: 0...100, step: 1)
                        .accessibilityLabel("Waveform quiet detail")
                        .accessibilityValue("\(Int(waveformBoost)) percent")
                        .accessibilityIdentifier("playback-inspector-waveform-detail")
                }
                Button("Reset quiet detail") { waveformBoost = 0 }
                    .disabled(waveformBoost == 0)
                if controller.isMultiMonoFile {
                    Toggle("Show all mono tracks", isOn: $controller.showAllMonoWaveforms)
                }
                Text("Color and quiet detail apply to all waveform views. Quiet detail reveals low-level audio without changing playback volume. The outer envelope shows peaks; the solid body shows average levels from the waveform's reduced-rate audio preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio sync offset") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Offset", value: offset, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 85)
                            .accessibilityLabel("Audio sync offset in milliseconds")
                            .accessibilityIdentifier("audio-sync-offset-ms")
                        Text("ms").foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { controller.setAudioSyncOffset(milliseconds: 0) }
                            .disabled(controller.audioSyncOffsetMilliseconds == 0)
                            .accessibilityLabel("Reset audio sync offset")
                            .accessibilityIdentifier("reset-audio-sync-offset")
                    }
                    Slider(value: offset, in: AudioSyncOffset.rangeMilliseconds, step: 10)
                        .accessibilityLabel("Audio sync offset")
                        .accessibilityValue("\(Int(controller.audioSyncOffsetMilliseconds)) milliseconds, \(direction)")
                        .accessibilityIdentifier("audio-sync-offset-slider")
                    HStack {
                        Text("Audio earlier")
                        Spacer()
                        Text("Audio later")
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(direction).font(.callout)
                }
                .padding(.vertical, 6)
                .disabled(!canAdjust)

                if controller.playbackBackend == .avFoundation {
                    Text("Audio sync adjustment is available with mpv playback.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !canAdjust {
                    Text("Available when an audio track is ready for playback.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Positive values play audio later relative to video. Negative values play audio earlier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Applies to this file in this window. Opening a different file resets the offset. Source measurements and exports use the original timing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}
