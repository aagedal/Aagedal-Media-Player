// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PlaybackInspectorSection {
    case playback, video, audio, subtitles
}

struct PlaybackInspectorView: View {
    @ObservedObject var primary: PlayerController
    @ObservedObject var comparison: CompareSessionController
    let section: PlaybackInspectorSection
    @Binding var selectsSecondary: Bool

    private var selectedPlayer: PlayerController {
        selectsSecondary && comparison.isActive ? comparison.secondaryController : primary
    }

    var body: some View {
        VStack(spacing: 0) {
            // Transport settings belong to the shared timeline; only the
            // per-source tabs need an A/B selector.
            if comparison.isActive, section != .playback {
                Picker("Playback source", selection: $selectsSecondary) {
                    Text("Source A").tag(false)
                    Text("Source B").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
                .accessibilityIdentifier("playback-inspector-source")
            }
            Group {
                switch section {
                case .playback:
                    PlaybackGeneralSettingsView(primary: primary, comparison: comparison)
                case .video:
                    VideoSettingsView(controller: selectedPlayer)
                case .audio:
                    AudioSettingsView(
                        controller: selectedPlayer, primary: primary, comparison: comparison,
                        source: selectsSecondary && comparison.isActive ? .secondary : .primary
                    )
                case .subtitles:
                    SubtitleSettingsView(controller: selectedPlayer)
                }
            }
            .id(ObjectIdentifier(selectedPlayer))
        }
        .accessibilityIdentifier("playback-inspector")
        .onChange(of: comparison.isActive) { _, active in
            if !active { selectsSecondary = false }
        }
    }
}

// MARK: - Shared rows

/// Label, live value and slider in the inspector's standard layout.
private struct InspectorSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let valueText: String
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

/// Millisecond field, reset button and slider for a signed timing offset.
private struct TimingOffsetEditor: View {
    let title: String
    @Binding var milliseconds: Double
    let range: ClosedRange<Double>
    let step: Double
    let earlierLabel: String
    let laterLabel: String
    var identifierPrefix: String

    private var direction: String {
        if milliseconds == 0 { return "No timing adjustment" }
        return milliseconds > 0 ? laterLabel : earlierLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Offset", value: $milliseconds, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 85)
                    .accessibilityLabel("\(title) in milliseconds")
                    .accessibilityIdentifier("\(identifierPrefix)-ms")
                Text("ms").foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { milliseconds = 0 }
                    .disabled(milliseconds == 0)
                    .accessibilityLabel("Reset \(title.lowercased())")
                    .accessibilityIdentifier("reset-\(identifierPrefix)")
            }
            Slider(value: $milliseconds, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(milliseconds)) milliseconds, \(direction)")
                .accessibilityIdentifier("\(identifierPrefix)-slider")
            HStack {
                Text(earlierLabel)
                Spacer()
                Text(laterLabel)
            }.font(.caption).foregroundStyle(.secondary)
            Text(direction).font(.callout)
        }
        .padding(.vertical, 6)
    }
}

private struct InspectorFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

private extension PlayerController {
    /// Display and subtitle settings are applied by mpv's renderer.
    var supportsPresentationSettings: Bool { useMPV && mpvPlayer != nil }
}

// MARK: - Playback

private struct PlaybackGeneralSettingsView: View {
    @ObservedObject var primary: PlayerController
    @ObservedObject var comparison: CompareSessionController

    private var loopBinding: Binding<Bool> {
        Binding(get: { primary.mediaItem?.loopPlayback ?? false }, set: { enabled in
            if comparison.isActive {
                comparison.setLoopPlayback(enabled, primary: primary)
            } else {
                primary.updateLoopPlayback(enabled)
            }
        })
    }

    var body: some View {
        List {
            Section("Now playing") {
                if let name = primary.mediaItem?.name {
                    Text(name).font(.callout).textSelection(.enabled)
                }
                engineRow(comparison.isActive ? "Engine A" : "Engine", primary)
                if comparison.isActive {
                    if let name = comparison.secondaryController.mediaItem?.name {
                        Text(name).font(.callout).textSelection(.enabled)
                    }
                    engineRow("Engine B", comparison.secondaryController)
                }
            }
            Section("Playback") {
                Toggle("Loop", isOn: loopBinding)
                    .disabled(primary.mediaItem == nil)
                    .accessibilityIdentifier("playback-inspector-loop")
                LabeledContent("Speed", value: speedText)
                InspectorFootnote("Change speed and direction with the J, K and L shortcuts.")
            }
            if !primary.chapterOptions.isEmpty {
                Section("Chapters") {
                    ForEach(primary.chapterOptions) { chapter in
                        Button { seek(to: chapter.time) } label: {
                            HStack {
                                Text(chapter.title)
                                Spacer()
                                Text(TimecodeText.clock(chapter.time))
                                    .monospacedDigit().foregroundStyle(.secondary)
                                if chapter.position == primary.currentChapterPosition {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chapter.position == primary.currentChapterPosition ? .isSelected : [])
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var speedText: String {
        let speed = primary.currentPlaybackSpeed
        let value = speed.formatted(.number.precision(.fractionLength(0...2)))
        return (primary.isReversing ? "−" : "") + value + "×"
    }

    @ViewBuilder
    private func engineRow(_ title: String, _ player: PlayerController) -> some View {
        if let backend = player.playbackBackend {
            LabeledContent(title, value: backend.displayName)
        } else {
            LabeledContent(title, value: "Preparing…")
        }
    }

    private func seek(to time: TimeInterval) {
        if comparison.isActive {
            comparison.seek(primary: primary, to: time)
        } else {
            primary.seekTo(time)
        }
    }
}

/// Compact h:mm:ss presentation for list rows.
private enum TimecodeText {
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Video

private struct VideoSettingsView: View {
    @ObservedObject var controller: PlayerController

    var body: some View {
        List {
            Section("Deinterlacing") {
                Picker("Deinterlace", selection: Binding(
                    get: { controller.deinterlaceMode },
                    set: { controller.setDeinterlaceMode($0) }
                )) {
                    ForEach(DeinterlaceMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("playback-inspector-deinterlace")
                InspectorFootnote("Automatic deinterlaces only frames flagged as interlaced. Choose Always for interlaced footage that is not flagged.")
            }
            Section("Picture") {
                ForEach(VideoPictureAdjustments.Kind.allCases, id: \.self) { kind in
                    InspectorSliderRow(
                        title: kind.label,
                        value: Binding(
                            get: { controller.pictureAdjustments[kind] },
                            set: { controller.setPictureAdjustment(kind, to: $0) }
                        ),
                        range: VideoPictureAdjustments.range,
                        valueText: signed(controller.pictureAdjustments[kind]),
                        accessibilityIdentifier: "playback-inspector-\(kind.rawValue)"
                    )
                }
                Button("Reset picture") { controller.setPictureAdjustments(VideoPictureAdjustments()) }
                    .disabled(controller.pictureAdjustments.isNeutral)
                InspectorFootnote("Changes the on-screen picture only. Saved screenshots and exports use the source pixels; the loupe and scopes may show the adjusted image.")
            }
            Section {
                InspectorFootnote(controller.playbackBackend == .avFoundation
                    ? "Video settings are available with mpv playback."
                    : "Applies to this file in this window. Opening a different file resets video settings.")
            }
        }
        .listStyle(.sidebar)
        .disabled(!controller.supportsPresentationSettings)
    }

    private func signed(_ value: Double) -> String {
        value > 0 ? "+\(Int(value))" : "\(Int(value))"
    }
}

// MARK: - Audio

private struct AudioSettingsView: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject var primary: PlayerController
    @ObservedObject var comparison: CompareSessionController
    let source: CompareAudioSource
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

    private var trackSelection: Binding<Int> {
        Binding(get: { controller.selectedAudioTrackOrderIndex }, set: { position in
            if comparison.isActive {
                comparison.selectAudioTrack(at: position, for: source, primary: primary)
            } else {
                controller.selectAudioTrack(at: position)
            }
        })
    }

    private var canAdjustSync: Bool {
        controller.supportsAudioSyncOffset && controller.isReady && !controller.audioTrackOptions.isEmpty
    }

    private var syncOffset: Binding<Double> {
        Binding(get: { controller.audioSyncOffsetMilliseconds },
                set: { controller.setAudioSyncOffset(milliseconds: $0) })
    }

    /// Channel routing is a single-source monitoring tool, matching the controls bar.
    private var showsChannelControls: Bool {
        !comparison.isActive && controller.selectedAudioChannelLabels.count > 1
    }

    var body: some View {
        List {
            Section("Output") {
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
                InspectorSliderRow(
                    title: "Volume", value: monitoringVolume, range: 0...100,
                    valueText: "\(Int(primary.volume))%",
                    accessibilityIdentifier: "playback-inspector-volume"
                )
                if comparison.isActive {
                    InspectorFootnote("Volume and mute apply to the comparison's listening source.")
                }
            }
            Section("Track") {
                if controller.audioTrackOptions.isEmpty {
                    Text("No audio tracks").foregroundStyle(.secondary)
                } else if let programme = controller.monoPlaybackProgramme {
                    LabeledContent("Monitoring", value: "Combined " + programme.layout.rawValue)
                    InspectorFootnote("Use the audio menu in the controls bar to change combined mono monitoring.")
                } else {
                    Picker("Audio track", selection: trackSelection) {
                        ForEach(controller.audioTrackOptions) { option in
                            Text(option.title).tag(option.position)
                        }
                    }
                    .disabled(!controller.isReady)
                    .accessibilityIdentifier("playback-inspector-audio-track")
                }
            }
            if showsChannelControls {
                channelSection
            }
            Section("Sync offset") {
                TimingOffsetEditor(
                    title: "Audio sync offset", milliseconds: syncOffset,
                    range: AudioSyncOffset.rangeMilliseconds, step: 10,
                    earlierLabel: "Audio earlier", laterLabel: "Audio later",
                    identifierPrefix: "audio-sync-offset"
                )
                .disabled(!canAdjustSync)
                if controller.playbackBackend == .avFoundation {
                    InspectorFootnote("Audio sync adjustment is available with mpv playback.")
                } else if !canAdjustSync {
                    InspectorFootnote("Available when an audio track is ready for playback.")
                }
                InspectorFootnote("Positive values play audio later relative to video. Applies to this file in this window; source measurements and exports use the original timing.")
            }
            Section("Waveform") {
                Picker("Color", selection: $waveformColor) {
                    ForEach(AudioWaveformColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color.rawValue)
                    }
                }
                .accessibilityIdentifier("playback-inspector-waveform-color")
                InspectorSliderRow(
                    title: "Quiet detail", value: $waveformBoost, range: 0...100,
                    valueText: "\(Int(waveformBoost))%",
                    accessibilityIdentifier: "playback-inspector-waveform-detail"
                )
                Button("Reset quiet detail") { waveformBoost = 0 }
                    .disabled(waveformBoost == 0)
                if controller.isMultiMonoFile {
                    Toggle("Show all mono tracks", isOn: $controller.showAllMonoWaveforms)
                }
                InspectorFootnote("Color and quiet detail apply to all waveform views. Quiet detail reveals low-level audio without changing playback volume.")
            }
        }
        .listStyle(.sidebar)
    }

    private var channelSection: some View {
        Section("Channels") {
            ForEach(Array(controller.selectedAudioChannelLabels.enumerated()), id: \.offset) { channel, name in
                HStack {
                    Text(name)
                        .foregroundStyle(controller.audioChannelRouting.isAudible(channel) ? .primary : .secondary)
                    Spacer()
                    channelToggle("S", help: "Solo \(name)",
                                  isOn: controller.audioChannelRouting.soloedChannels.contains(channel)) {
                        controller.toggleAudioChannelSolo(channel)
                    }
                    channelToggle("M", help: "Mute \(name)",
                                  isOn: controller.audioChannelRouting.mutedChannels.contains(channel)) {
                        controller.toggleAudioChannelMute(channel)
                    }
                }
            }
            Button("Hear all channels") { controller.clearAudioChannelRouting() }
                .disabled(controller.audioChannelRouting.isBypassed)
            InspectorFootnote("Solo isolates channels; mute removes them. Monitoring only — files and exports are unchanged.")
        }
    }

    private func channelToggle(_ title: String, help: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 18)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Subtitles

private struct SubtitleSettingsView: View {
    @ObservedObject var controller: PlayerController

    private static let fileExtensions = ["srt", "ass", "ssa", "vtt", "sub", "idx", "sup", "smi", "lrc"]

    private var presentation: SubtitlePresentation { controller.subtitlePresentation }

    private func binding(_ keyPath: WritableKeyPath<SubtitlePresentation, Double>) -> Binding<Double> {
        Binding(get: { controller.subtitlePresentation[keyPath: keyPath] }, set: { value in
            var updated = controller.subtitlePresentation
            updated[keyPath: keyPath] = value
            controller.setSubtitlePresentation(updated)
        })
    }

    var body: some View {
        List {
            Section("Track") {
                Picker("Subtitles", selection: Binding(
                    get: { controller.selectedSubtitleTrackOrderIndex },
                    set: { controller.selectSubtitleTrack(at: $0) }
                )) {
                    Text("Off").tag(-1)
                    ForEach(controller.subtitleTrackOptions) { option in
                        Text(option.title).tag(option.position)
                    }
                }
                .accessibilityIdentifier("playback-inspector-subtitle-track")
                Button("Add Subtitle File…", action: chooseSubtitleFile)
                    .accessibilityIdentifier("playback-inspector-add-subtitle")
                ForEach(controller.externalSubtitleURLs, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "doc.text")
                        .font(.callout)
                        .help(url.path)
                }
            }
            .disabled(!controller.isReady)
            Section("Timing") {
                TimingOffsetEditor(
                    title: "Subtitle delay", milliseconds: binding(\.delayMilliseconds),
                    range: SubtitlePresentation.delayRangeMilliseconds, step: 50,
                    earlierLabel: "Subtitles earlier", laterLabel: "Subtitles later",
                    identifierPrefix: "subtitle-delay"
                )
            }
            Section("Appearance") {
                InspectorSliderRow(
                    title: "Size", value: binding(\.scale),
                    range: SubtitlePresentation.scaleRange, step: 0.05,
                    valueText: "\(Int((presentation.scale * 100).rounded()))%",
                    accessibilityIdentifier: "playback-inspector-subtitle-size"
                )
                InspectorSliderRow(
                    title: "Vertical position", value: binding(\.position),
                    range: SubtitlePresentation.positionRange,
                    valueText: "\(Int(presentation.position))",
                    accessibilityIdentifier: "playback-inspector-subtitle-position"
                )
                Button("Reset appearance") {
                    var updated = presentation
                    updated.scale = SubtitlePresentation().scale
                    updated.position = SubtitlePresentation().position
                    controller.setSubtitlePresentation(updated)
                }
                .disabled(presentation.scale == SubtitlePresentation().scale
                          && presentation.position == SubtitlePresentation().position)
                InspectorFootnote("Position 100 places subtitles at the bottom of the picture; lower values move them up.")
            }
            Section {
                InspectorFootnote(controller.playbackBackend == .avFoundation
                    ? "Subtitles are available with mpv playback."
                    : "Applies to this file in this window. Opening a different file resets subtitle settings and added files.")
            }
        }
        .listStyle(.sidebar)
        .disabled(!controller.supportsPresentationSettings)
    }

    private func chooseSubtitleFile() {
        let panel = NSOpenPanel()
        panel.title = "Add Subtitle File"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = controller.mediaItem?.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !controller.addExternalSubtitle(url) {
            let alert = NSAlert()
            alert.messageText = "The subtitle file couldn't be added."
            alert.informativeText = "mpv could not read “\(url.lastPathComponent)” as subtitles."
            alert.runModal()
        }
    }
}
