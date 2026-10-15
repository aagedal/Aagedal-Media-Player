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
            PlaybackSettingsView(controller: selectedPlayer)
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
