// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

/// Owns the live meter for one player window. Source selection is deliberately
/// independent of audible A/B routing: this session only chooses which decoded
/// source PCM is measured.
@MainActor
final class LiveAudioMeterSession: ObservableObject {
    static let primarySourceID = "A"
    static let secondarySourceID = "B"

    @Published private(set) var preferences: LiveAudioMeterPreferences
    @Published private(set) var selectedSourceID = primarySourceID
    @Published private(set) var sourceOptions: [LiveAudioMeterSourceOption] = []

    let coordinator: LiveAudioMeterCoordinator

    private let primary: PlayerController
    private let comparison: CompareSessionController
    private let defaults: UserDefaults
    private var selectedPlayer: PlayerController?
    private var selectedSource: LiveAudioMeterPlaybackSource?
    private var sourceFailure: String?
    private var awaitsSourceReadiness = false
    private var hasStarted = false
    private var isClosed = false
    private var coordinatorCancellable: AnyCancellable?
    private var comparisonCancellables: Set<AnyCancellable> = []
    private var playbackCancellable: AnyCancellable?
    private var sourceRevisionCancellable: AnyCancellable?

    init(
        primary: PlayerController,
        comparison: CompareSessionController,
        defaults: UserDefaults = .standard,
        coordinator: LiveAudioMeterCoordinator = LiveAudioMeterCoordinator()
    ) {
        self.primary = primary
        self.comparison = comparison
        self.defaults = defaults
        self.coordinator = coordinator
        preferences = LiveAudioMeterPreferences(defaults: defaults)

        coordinatorCancellable = coordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        comparison.$secondaryURL
            .removeDuplicates()
            .sink { [weak self] secondaryURL in
                self?.comparisonSourcesChanged(secondaryURL: secondaryURL)
            }
            .store(in: &comparisonCancellables)
        comparison.$isSecondaryReady
            .removeDuplicates()
            .sink { [weak self] ready in
                guard ready, self?.selectedSourceID == Self.secondarySourceID else { return }
                self?.reconcileSelectedSource()
            }
            .store(in: &comparisonCancellables)
    }

    func start() {
        guard !isClosed, !hasStarted else { return }
        hasStarted = true
        refreshSourceOptions(secondaryURL: comparison.secondaryURL)
        bindSelectedPlayer()
        reconcileSelectedSource(initial: true)
    }

    func selectSource(_ id: String) {
        guard !isClosed, id != selectedSourceID,
              sourceOptions.contains(where: { $0.id == id }) else { return }
        selectedSourceID = id
        sourceFailure = nil
        awaitsSourceReadiness = false
        selectedSource = nil
        coordinator.handlePlaybackEvent(.discontinuity(
            .sourceReplacement,
            snapshot: selectedPlayer?.liveAudioMeterPlaybackSnapshot()
                ?? primary.liveAudioMeterPlaybackSnapshot()
        ))
        bindSelectedPlayer()
        reconcileSelectedSource()
    }

    func selectPreset(_ preset: LiveAudioMeterReference.Preset) {
        preferences.preset = preset
        savePreferences()
    }

    func setCustomLoudnessTarget(_ value: Double) {
        guard value.isFinite else { return }
        preferences.customLoudnessTarget = value
        savePreferences()
    }

    func setCustomTruePeakCeiling(_ value: Double?) {
        guard value?.isFinite != false else { return }
        preferences.customTruePeakCeiling = value
        savePreferences()
    }

    func clearMaxima() {
        coordinator.clearMaxima()
    }

    func reset() {
        // Source and track replacement deliberately retain the coordinator's
        // previous request only as diagnostic/recovery context. Never let a
        // user action revive that stale URL or stream while the replacement's
        // track metadata is still rebuilding.
        guard let player = selectedPlayer,
              selectedSource != nil, !awaitsSourceReadiness else { return }
        if !coordinator.reset(at: player.playbackTimeSnapshot()) {
            reconcileSelectedSource()
        }
        coordinator.updatePlaybackClock(player.liveAudioMeterPlaybackSnapshot())
    }

    func retry() {
        guard let player = selectedPlayer,
              selectedSource != nil, !awaitsSourceReadiness else { return }
        if coordinator.retry(at: player.playbackTimeSnapshot()) {
            coordinator.updatePlaybackClock(player.liveAudioMeterPlaybackSnapshot())
            return
        }
        selectedSource = nil
        reconcileSelectedSource()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        playbackCancellable = nil
        sourceRevisionCancellable = nil
        comparisonCancellables.removeAll()
        coordinatorCancellable = nil
        selectedPlayer = nil
        selectedSource = nil
        coordinator.close()
    }

    var viewState: LiveAudioMeterViewState {
        let reference = preferences.reference
        let reduced = coordinator.reducedSnapshot
        let channelLabels = selectedSource?.channelLabels ?? []
        let emptyLevel = LiveAudioMeterLevelState(
            current: nil, bar: nil, marker: nil, maximum: nil
        )
        let channels = channelLabels.indices.map { index in
            LiveAudioMeterChannelState(
                id: index,
                label: channelLabels[index],
                samplePeak: reduced?.samplePeaks[safe: index] ?? emptyLevel,
                truePeak: reduced?.truePeaks[safe: index] ?? emptyLevel
            )
        }
        let loudness = reduced?.loudness ?? LiveAudioMeterLoudnessState(
            momentary: nil, maximumMomentary: nil,
            shortTerm: nil, maximumShortTerm: nil
        )
        return LiveAudioMeterViewState(
            status: presentationStatus,
            sourceOptions: sourceOptions,
            selectedSourceID: selectedSourceID,
            measuredSourceLabel: measuredSourceLabel,
            canRetry: selectedSource != nil && !awaitsSourceReadiness,
            channels: channels,
            loudness: loudness,
            reference: reference,
            provenance: presentationProvenance,
            diagnostics: presentationDiagnostics
        )
    }

    private func comparisonSourcesChanged(secondaryURL: URL?) {
        guard !isClosed else { return }
        // `@Published` emits from `willSet`, so use the value delivered by the
        // publisher instead of rereading `comparison.secondaryURL` here.
        refreshSourceOptions(secondaryURL: secondaryURL)
        if selectedSourceID == Self.secondarySourceID,
           !sourceOptions.contains(where: { $0.id == Self.secondarySourceID }) {
            selectedSourceID = Self.primarySourceID
            selectedSource = nil
            sourceFailure = nil
            awaitsSourceReadiness = false
            bindSelectedPlayer()
            reconcileSelectedSource()
        }
    }

    private func refreshSourceOptions(secondaryURL: URL?) {
        var options: [LiveAudioMeterSourceOption] = []
        if primary.mediaItem != nil {
            options.append(option(id: Self.primarySourceID, label: "Source A", player: primary))
        }
        if secondaryURL != nil {
            options.append(option(
                id: Self.secondarySourceID,
                label: "Source B",
                player: comparison.secondaryController
            ))
        }
        sourceOptions = options
    }

    private func option(
        id: String, label: String, player: PlayerController
    ) -> LiveAudioMeterSourceOption {
        let index = player.selectedAudioTrackOrderIndex
        let detail = player.audioTrackOptions.indices.contains(index)
            ? player.audioTrackOptions[index].title
            : nil
        return .init(id: id, label: label, detail: detail)
    }

    private func bindSelectedPlayer() {
        playbackCancellable = nil
        sourceRevisionCancellable = nil
        let player = player(for: selectedSourceID)
        selectedPlayer = player
        guard let player else { return }

        playbackCancellable = player.liveAudioMeterPlaybackEvents.sink { [weak self, weak player] event in
            guard let self, let player, self.selectedPlayer === player else { return }
            self.handle(event, from: player)
        }
        sourceRevisionCancellable = player.$liveAudioMeterSourceRevision
            .dropFirst()
            .sink { [weak self, weak player] _ in
                guard let self, let player, self.selectedPlayer === player else { return }
                self.refreshSourceOptions(secondaryURL: self.comparison.secondaryURL)
                self.reconcileSelectedSource()
            }
    }

    private func handle(_ event: LiveAudioMeterPlaybackEvent, from player: PlayerController) {
        switch event {
        case .discontinuity(.sourceReplacement, _):
            selectedSource = nil
            sourceFailure = nil
            awaitsSourceReadiness = true
            coordinator.handlePlaybackEvent(event)
            refreshSourceOptions(secondaryURL: comparison.secondaryURL)
        case .discontinuity(.audioTrackReplacement, let snapshot):
            selectedSource = nil
            sourceFailure = nil
            awaitsSourceReadiness = false
            coordinator.handlePlaybackEvent(event)
            refreshSourceOptions(secondaryURL: comparison.secondaryURL)
            reconcileSelectedSource(at: snapshot.time)
        default:
            coordinator.handlePlaybackEvent(event)
        }
    }

    private func reconcileSelectedSource(
        at playbackTime: TimeInterval? = nil,
        initial: Bool = false
    ) {
        guard !isClosed, let player = selectedPlayer else {
            sourceFailure = "The selected live meter source is unavailable."
            return
        }
        do {
            let source = try player.liveAudioMeterSource(
                id: selectedSourceID,
                label: selectedSourceID == Self.primarySourceID ? "Source A" : "Source B"
            )
            if source == selectedSource, !awaitsSourceReadiness, !initial { return }
            let snapshot = player.liveAudioMeterPlaybackSnapshot()
            let request = try source.request(at: playbackTime ?? snapshot.time)
            selectedSource = source
            sourceFailure = nil
            awaitsSourceReadiness = false
            if coordinator.generation == 0 {
                coordinator.start(request)
            } else {
                coordinator.restart(request, because: .sourceReplacement)
            }
            coordinator.updatePlaybackClock(snapshot)
        } catch {
            selectedSource = nil
            sourceFailure = error.localizedDescription
            awaitsSourceReadiness = true
            coordinator.handlePlaybackEvent(.discontinuity(
                .sourceReplacement,
                snapshot: player.liveAudioMeterPlaybackSnapshot()
            ))
        }
    }

    private func player(for id: String) -> PlayerController? {
        switch id {
        case Self.primarySourceID: primary
        case Self.secondarySourceID where comparison.secondaryURL != nil:
            comparison.secondaryController
        default: nil
        }
    }

    private func savePreferences() {
        preferences.save(to: defaults)
    }

    private var presentationStatus: LiveAudioMeterPresentationStatus {
        if let sourceFailure {
            return .unavailable(
                reason: "Live source audio is unavailable.", diagnostic: sourceFailure
            )
        }
        switch coordinator.status {
        case .unavailable(let reason, let diagnostic):
            return .unavailable(reason: reason, diagnostic: diagnostic)
        case .warmingUp(let frame, let momentaryReady, let shortTermReady):
            return .warmingUp(
                position: position(frame), momentaryReady: momentaryReady,
                shortTermReady: shortTermReady
            )
        case .active(let frame): return .active(position: position(frame))
        case .paused(let frame): return .paused(position: position(frame))
        case .buffering(let frame): return .buffering(position: position(frame))
        case .ended(let frame): return .ended(position: position(frame))
        }
    }

    private var measuredSourceLabel: String {
        guard let source = selectedSource else {
            return selectedSourceID == Self.primarySourceID ? "Source A" : "Source B"
        }
        return "\(source.label) · \(source.trackLabel)"
    }

    private func position(_ frame: Int64) -> String {
        guard let rate = selectedSource?.format.sampleRate, rate > 0 else { return "—" }
        return String(format: "%.3f s", Double(frame) / Double(rate))
    }

    private var presentationProvenance: LiveAudioMeterProvenance? {
        guard let source = selectedSource,
              let provenance = coordinator.provenance else { return nil }
        let endFrame = coordinator.snapshot?.endFrame ?? provenance.request.startSourceFrame
        return LiveAudioMeterProvenance(
            sourceIdentity: source.url.path,
            streamIndex: source.containerStreamIndex ?? source.audioStreamOrderIndex,
            trackLabel: source.trackLabel,
            decoder: "FFmpeg",
            decoderVersion: provenance.decoderVersion,
            sampleRate: source.format.sampleRate,
            channelLayout: layoutDescription(source.format.layout),
            channelMap: source.channelLabels,
            algorithm: LiveAudioMeterDSP.algorithm,
            measurementGeneration: coordinator.generation,
            sourceInterval: "\(position(provenance.request.startSourceFrame))–\(position(endFrame))",
            segmentStart: position(provenance.request.startSourceFrame)
        )
    }

    private var presentationDiagnostics: [LiveAudioMeterDiagnostic] {
        var diagnostics: [LiveAudioMeterDiagnostic] = []
        if let drift = coordinator.clockDrift {
            diagnostics.append(.init(
                id: "clock-drift", label: "Playback alignment",
                detail: String(format: "%+.1f ms decoded-source drift", drift * 1_000)
            ))
        }
        if case .unknown = selectedSource?.format.layout {
            diagnostics.append(.init(
                id: "unknown-layout", label: "Loudness unavailable",
                detail: "The source channel layout is not explicitly supported; numbered peak meters remain available.",
                severity: .qualification
            ))
        }
        if coordinator.provenance == nil, selectedSource != nil {
            diagnostics.append(.init(
                id: "provenance-pending", label: "Decoder provenance",
                detail: "The decoder version and completed source interval are available when this segment ends.",
                severity: .qualification
            ))
        }
        return diagnostics
    }

    private func layoutDescription(_ layout: LiveAudioMeterFormat.Layout) -> String {
        switch layout {
        case .mono: "mono"
        case .stereo: "stereo"
        case .surround5Point1: "5.1(side)"
        case .surround7Point1: "7.1"
        case .unknown(let channels): "unknown (\(channels) channels)"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
