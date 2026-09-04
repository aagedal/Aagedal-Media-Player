// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

nonisolated enum CompareViewMode: String, CaseIterable, Sendable {
    case sideBySide
    case primary
    case secondary
    case verticalWipe
    case horizontalWipe
    case overlay
    case difference

    var label: String {
        switch self {
        case .sideBySide: "A | B"
        case .primary: "A"
        case .secondary: "B"
        case .verticalWipe: "Vertical Wipe"
        case .horizontalWipe: "Horizontal Wipe"
        case .overlay: "Overlay"
        case .difference: "Display Difference"
        }
    }

    var isWipe: Bool {
        self == .verticalWipe || self == .horizontalWipe
    }
}

nonisolated enum CompareAlignmentMode: Equatable, Sendable {
    case sourceTimecode
    case relative

    var label: String {
        switch self {
        case .sourceTimecode: "Source timecode"
        case .relative: "Relative start"
        }
    }
}

nonisolated enum CompareScopeSource: String, CaseIterable, Sendable {
    case primary
    case secondary
    case difference

    var label: String {
        switch self {
        case .primary: "Scopes: A"
        case .secondary: "Scopes: B"
        case .difference: "Scopes: Display Difference"
        }
    }
}

nonisolated enum CompareAudioSource: String, CaseIterable, Sendable {
    case primary
    case secondary

    var label: String {
        switch self {
        case .primary: "Audio: A"
        case .secondary: "Audio: B"
        }
    }
}

nonisolated enum CompareSafeAreaGuide: String, CaseIterable, Sendable {
    case none
    case action
    case title
    case actionAndTitle

    var label: String {
        switch self {
        case .none: "Off"
        case .action: "Action Safe (90%)"
        case .title: "Title Safe (80%)"
        case .actionAndTitle: "Action + Title Safe"
        }
    }

    var showsActionSafe: Bool {
        self == .action || self == .actionAndTitle
    }

    var showsTitleSafe: Bool {
        self == .title || self == .actionAndTitle
    }
}

nonisolated enum CompareAspectRatioGuide: String, CaseIterable, Sendable {
    case none
    case fourByThree
    case sixteenByNine
    case oneEightyFive
    case twoThirtyNine

    var label: String {
        switch self {
        case .none: "Off"
        case .fourByThree: "4:3"
        case .sixteenByNine: "16:9"
        case .oneEightyFive: "1.85:1"
        case .twoThirtyNine: "2.39:1"
        }
    }

    var aspectRatio: CGFloat? {
        switch self {
        case .none: nil
        case .fourByThree: 4.0 / 3.0
        case .sixteenByNine: 16.0 / 9.0
        case .oneEightyFive: 1.85
        case .twoThirtyNine: 2.39
        }
    }
}

/// Maps the primary player's relative timeline onto the comparison player's
/// relative timeline. Keeping this pure makes drop-frame parsing a concern of
/// TimecodeFormatter while synchronization and overlap math remain testable.
nonisolated struct CompareTimelineMapping: Equatable, Sendable {
    let mode: CompareAlignmentMode
    let offset: TimeInterval
    let secondaryDuration: TimeInterval

    init(
        primaryStartSeconds: TimeInterval?,
        secondaryStartSeconds: TimeInterval?,
        secondaryDuration: TimeInterval
    ) {
        if let primaryStartSeconds,
           let secondaryStartSeconds,
           primaryStartSeconds.isFinite,
           secondaryStartSeconds.isFinite {
            mode = .sourceTimecode
            offset = primaryStartSeconds - secondaryStartSeconds
        } else {
            mode = .relative
            offset = 0
        }
        self.secondaryDuration = max(0, secondaryDuration.isFinite ? secondaryDuration : 0)
    }

    func secondaryTime(
        forPrimaryTime primaryTime: TimeInterval,
        secondaryDuration overrideDuration: TimeInterval? = nil
    ) -> TimeInterval {
        let mapped = (primaryTime.isFinite ? primaryTime : 0) + offset
        let overrideDuration = overrideDuration.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        let clampingDuration = overrideDuration ?? secondaryDuration
        guard clampingDuration > 0 else { return max(0, mapped) }
        return max(0, min(mapped, clampingDuration))
    }

    func primaryOverlapRange(primaryDuration: TimeInterval) -> ClosedRange<TimeInterval>? {
        let primaryDuration = max(0, primaryDuration.isFinite ? primaryDuration : 0)
        let lowerBound = max(0, -offset)
        let upperBound = min(primaryDuration, secondaryDuration - offset)
        guard upperBound >= lowerBound else { return nil }
        return lowerBound...upperBound
    }
}

@MainActor
final class CompareSessionController: ObservableObject {
    nonisolated static let minimumDifferenceGain = 1.0
    nonisolated static let maximumDifferenceGain = 16.0

    let secondaryController: PlayerController
    let secondaryWaveformGenerator = AudioWaveformGenerator()

    @Published var viewMode: CompareViewMode = .sideBySide
    @Published private(set) var wipePosition = 0.5
    @Published private(set) var overlayBlend = 0.5
    @Published private(set) var differenceGain = 1.0
    @Published var scopeSource: CompareScopeSource = .primary
    @Published var safeAreaGuide: CompareSafeAreaGuide = .none
    @Published var aspectRatioGuide: CompareAspectRatioGuide = .none
    @Published private(set) var audioSource: CompareAudioSource = .primary
    @Published private(set) var secondaryURL: URL?
    @Published private(set) var mapping: CompareTimelineMapping?
    @Published private(set) var isLoading = false
    @Published private(set) var isSecondaryReady = false
    @Published private(set) var loadError: String?
    @Published private(set) var reviewNotes: [CompareReviewNote] = []
    @Published private(set) var reviewSidecarURL: URL?
    @Published private(set) var reviewError: String?
    @Published private(set) var isReviewLoading = false
    @Published private(set) var reviewExportState: CompareReviewExportState = .idle

    private var loadTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var driftCorrectionTask: Task<Void, Never>?
    private var audioTrackSelectionTask: Task<Void, Never>?
    private var reviewLoadTask: Task<Void, Never>?
    private var reviewSaveTask: Task<Void, Never>?
    private var reviewExportTask: Task<Void, Never>?
    private var reviewExportSavePanel: NSSavePanel?
    private var shouldResumeAfterAudioTrackSelection = false
    private var secondaryPlaybackPhaseCancellable: AnyCancellable?
    private var loadGeneration = OperationGeneration()
    private var reviewRevision: UInt64 = 0
    private var isReviewSidecarWritable = false
    private let reviewStore = CompareReviewSidecarStore.shared
    private weak var primaryAudioController: PlayerController?

    var isActive: Bool { secondaryURL != nil }
    var canEditReviewNotes: Bool {
        isActive && !isReviewLoading && isReviewSidecarWritable
    }

    init(secondaryController: PlayerController? = nil) {
        self.secondaryController = secondaryController ?? PlayerController()
        self.secondaryController.setAudioSuppressed(true)
        secondaryPlaybackPhaseCancellable = self.secondaryController.$playbackPhase
            .sink { [weak self] phase in
                guard let self else { return }
                self.isSecondaryReady = phase.permitsPlaybackControls
                guard case .failed(let failure) = phase,
                      self.isActive,
                      let primary = self.primaryAudioController else { return }
                self.selectAudioSource(.primary, primary: primary)
                self.loadError = "The comparison file could not be played: \(failure.message)"
            }
    }

    func loadSecondary(_ url: URL, alignedWith primary: PlayerController) {
        if primaryAudioController !== primary {
            secondaryController.setAudioSuppressed(true)
            primaryAudioController?.setAudioSuppressed(false)
        }
        primaryAudioController = primary

        let generation = loadGeneration.advance()
        loadTask?.cancel()
        readinessTask?.cancel()
        reviewLoadTask?.cancel()
        reviewExportTask?.cancel()
        reviewExportSavePanel?.cancel(nil)
        reviewExportSavePanel = nil
        audioTrackSelectionTask?.cancel()
        audioTrackSelectionTask = nil
        shouldResumeAfterAudioTrackSelection = false
        stopDriftCorrection()
        secondaryWaveformGenerator.cancel()
        secondaryController.teardown()
        // Replacing B is an explicit source change. Return monitoring to A so
        // the replacement cannot become audible merely because the old B was.
        audioSource = .primary
        synchronizeAudioPreferences(primary: primary)
        applyAudioRouting(primary: primary)

        isLoading = true
        loadError = nil
        secondaryURL = nil
        mapping = nil
        reviewNotes = []
        reviewSidecarURL = nil
        reviewError = nil
        isReviewLoading = false
        isReviewSidecarWritable = false
        reviewExportState = .idle

        loadTask = Task { @MainActor [weak self, weak primary] in
            guard let self, let primary else { return }
            var item = PlayerWindowCoordinator.makeMediaItem(for: url)

            do {
                let metadata = try await MetadataService.shared.metadata(for: url)
                guard !Task.isCancelled, self.loadGeneration.isCurrent(generation) else { return }
                item.metadata = metadata
                item.durationSeconds = metadata.duration ?? 0
                item.hasVideoStream = !metadata.videoStreams.isEmpty
            } catch {
                guard !Task.isCancelled, self.loadGeneration.isCurrent(generation) else { return }
                // Playback may still succeed when metadata is malformed or
                // incomplete, so retain the same graceful fallback as the
                // primary-file loader.
            }

            guard !Task.isCancelled, self.loadGeneration.isCurrent(generation) else { return }

            let primaryStart = primary.mediaItem.flatMap {
                TimecodeFormatter.startTimecodeInSeconds(for: $0)
            }
            let secondaryStart = TimecodeFormatter.startTimecodeInSeconds(for: item)
            let newMapping = CompareTimelineMapping(
                primaryStartSeconds: primaryStart,
                secondaryStartSeconds: secondaryStart,
                secondaryDuration: item.durationSeconds
            )

            self.mapping = newMapping
            self.secondaryURL = url
            self.isLoading = false
            if let primaryURL = primary.mediaItem?.url {
                self.loadReviewNotes(
                    primaryURL: primaryURL,
                    secondaryURL: url,
                    generation: generation
                )
            }
            let secondaryTime = newMapping.secondaryTime(
                forPrimaryTime: primary.currentPlaybackTime
            )
            self.secondaryController.loadMedia(item, startTime: secondaryTime)
            if item.metadata != nil {
                self.secondaryController.updateMetadata(item)
            }
            self.startSecondaryWhenReady(primary: primary, generation: generation)
            self.loadTask = nil
        }
    }

    func stop() {
        loadGeneration.advance()
        loadTask?.cancel()
        loadTask = nil
        readinessTask?.cancel()
        readinessTask = nil
        reviewLoadTask?.cancel()
        reviewLoadTask = nil
        reviewExportTask?.cancel()
        reviewExportTask = nil
        reviewExportSavePanel?.cancel(nil)
        reviewExportSavePanel = nil
        audioTrackSelectionTask?.cancel()
        audioTrackSelectionTask = nil
        shouldResumeAfterAudioTrackSelection = false
        stopDriftCorrection()
        secondaryWaveformGenerator.cancel()
        secondaryController.teardown()
        secondaryController.setAudioSuppressed(true)
        primaryAudioController?.setAudioSuppressed(false)
        primaryAudioController = nil
        secondaryURL = nil
        mapping = nil
        isLoading = false
        isSecondaryReady = false
        loadError = nil
        reviewNotes = []
        reviewSidecarURL = nil
        reviewError = nil
        isReviewLoading = false
        isReviewSidecarWritable = false
        reviewExportState = .idle
        viewMode = .sideBySide
        wipePosition = 0.5
        overlayBlend = 0.5
        differenceGain = 1
        scopeSource = .primary
        safeAreaGuide = .none
        aspectRatioGuide = .none
        audioSource = .primary
    }

    func selectAudioSource(_ source: CompareAudioSource, primary: PlayerController) {
        // Enforce silence before synchronizing preferences: a stale B mute
        // preference must not make B audible during the routing transition.
        primaryAudioController?.setAudioSuppressed(true)
        primary.setAudioSuppressed(true)
        secondaryController.setAudioSuppressed(true)
        if primaryAudioController !== primary {
            primaryAudioController?.setAudioSuppressed(false)
            primaryAudioController = primary
        }
        synchronizeAudioPreferences(primary: primary)
        audioSource = source
        unsuppressSelectedAudioSource(primary: primary)
    }

    func toggleMonitoringMute(primary: PlayerController) {
        let muted = !primary.isMuted
        primary.isMuted = muted
        secondaryController.isMuted = muted
    }

    func setMonitoringVolume(_ volume: Double, primary: PlayerController) {
        primary.volume = volume
        secondaryController.volume = primary.volume
    }

    func adjustMonitoringVolume(by delta: Double, primary: PlayerController) {
        primary.adjustVolume(by: delta)
        secondaryController.volume = primary.volume
        secondaryController.isMuted = primary.isMuted
    }

    func selectAudioTrack(
        at position: Int,
        for source: CompareAudioSource,
        primary: PlayerController
    ) {
        let target = source == .primary ? primary : secondaryController
        guard target.audioTrackOptions.indices.contains(position),
              position != target.selectedAudioTrackOrderIndex else { return }

        let wasPlaying = primary.isPlaying
            || secondaryController.isPlaying
            || shouldResumeAfterAudioTrackSelection
        shouldResumeAfterAudioTrackSelection = wasPlaying
        primary.pause()
        secondaryController.pause()
        stopDriftCorrection()

        audioTrackSelectionTask?.cancel()
        let generation = loadGeneration.current
        audioTrackSelectionTask = Task { @MainActor [weak self, weak primary] in
            guard let self, let primary else { return }
            _ = await target.selectAudioTrackAndWait(at: position)
            guard !Task.isCancelled,
                  self.loadGeneration.isCurrent(generation),
                  self.isActive else { return }
            self.synchronize(primary: primary)
            let shouldResume = self.shouldResumeAfterAudioTrackSelection
            self.shouldResumeAfterAudioTrackSelection = false
            if shouldResume {
                self.play(primary: primary)
            }
            self.audioTrackSelectionTask = nil
        }
    }

    private func synchronizeAudioPreferences(primary: PlayerController) {
        secondaryController.volume = primary.volume
        secondaryController.isMuted = primary.isMuted
    }

    private func applyAudioRouting(primary: PlayerController) {
        // Break before make: suppress both outputs first so switching can
        // never produce a short burst of doubled audio.
        primary.setAudioSuppressed(true)
        secondaryController.setAudioSuppressed(true)
        unsuppressSelectedAudioSource(primary: primary)
    }

    private func unsuppressSelectedAudioSource(primary: PlayerController) {
        switch audioSource {
        case .primary:
            primary.setAudioSuppressed(false)
        case .secondary:
            secondaryController.setAudioSuppressed(false)
        }
    }

    func togglePrimarySecondary() {
        viewMode = viewMode == .primary ? .secondary : .primary
    }

    func setWipePosition(_ position: Double) {
        wipePosition = Self.clampedUnitValue(position)
    }

    func moveWipe(by delta: Double) {
        setWipePosition(wipePosition + delta)
    }

    func setOverlayBlend(_ blend: Double) {
        overlayBlend = Self.clampedUnitValue(blend)
    }

    func setDifferenceGain(_ gain: Double) {
        differenceGain = Self.clampedDifferenceGain(gain)
    }

    nonisolated static func clampedUnitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    nonisolated static func clampedDifferenceGain(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, minimumDifferenceGain), maximumDifferenceGain)
    }

    nonisolated static func differenceBrightness(forGain gain: Double) -> Double {
        let gain = clampedDifferenceGain(gain)
        return (gain - 1) / (2 * gain)
    }

    func dismissLoadError() {
        loadError = nil
    }

    func dismissReviewError() {
        reviewError = nil
    }

    func dismissReviewExportFeedback() {
        guard !reviewExportState.isInFlight else { return }
        reviewExportState = .idle
    }

    func exportReviewReport(
        _ format: CompareReviewReportFormat,
        primary: PlayerController
    ) {
        guard !reviewExportState.isInFlight,
              !isReviewLoading,
              let primaryItem = primary.mediaItem,
              let secondaryItem = secondaryController.mediaItem,
              let alignmentMode = mapping?.mode,
              !reviewNotes.isEmpty else { return }

        let snapshot = CompareReviewReportSnapshot(
            primaryItem: primaryItem,
            secondaryItem: secondaryItem,
            alignmentMode: alignmentMode,
            notes: reviewNotes
        )
        let generation = loadGeneration.current
        let panel = NSSavePanel()
        reviewExportSavePanel = panel
        reviewExportState = .exporting
        panel.nameFieldStringValue = CompareReviewReportExporter.preferredFilename(
            for: format,
            snapshot: snapshot
        )
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.directoryURL = primaryItem.url.deletingLastPathComponent()

        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reviewExportSavePanel = nil
                guard self.loadGeneration.isCurrent(generation) else { return }
                guard response == .OK, let destinationURL = panel.url else {
                    self.reviewExportState = .idle
                    return
                }

                let output = OutputCoordinator.userConfirmed(destinationURL: destinationURL)
                self.reviewExportTask = Task { @MainActor [weak self] in
                    defer { output.discard() }
                    do {
                        let data = CompareReviewReportExporter.data(
                            for: format,
                            snapshot: snapshot
                        )
                        try data.write(to: output.temporaryURL, options: .atomic)
                        try Task.checkCancellation()
                        guard let self,
                              self.loadGeneration.isCurrent(generation) else { return }
                        let outputURL = try output.commit()
                        self.reviewExportState = .succeeded(outputURL)
                        self.reviewExportTask = nil
                    } catch is CancellationError {
                        guard let self,
                              self.loadGeneration.isCurrent(generation) else { return }
                        self.reviewExportState = .idle
                        self.reviewExportTask = nil
                    } catch {
                        guard let self,
                              self.loadGeneration.isCurrent(generation) else { return }
                        self.reviewExportState = .failed(
                            "Could not export comparison review: \(error.localizedDescription)"
                        )
                        self.reviewExportTask = nil
                    }
                }
            }
        }
    }

    func retryReviewLoad(primary: PlayerController) {
        guard let primaryURL = primary.mediaItem?.url,
              let secondaryURL else { return }
        loadReviewNotes(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            generation: loadGeneration.current
        )
    }

    @discardableResult
    func addReviewNote(_ text: String, primary: PlayerController) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              canEditReviewNotes,
              let primaryItem = primary.mediaItem,
              let secondaryItem = secondaryController.mediaItem else { return false }

        // Freeze both clocks before taking the backend snapshot so the marker
        // identifies the frame the user is reviewing, not a stale UI tick.
        pause(primary: primary)
        let primaryTimecodeRate = TimecodeFormatter.effectiveTimecodeRate(for: primaryItem)
        let primaryRate = primaryTimecodeRate.value
        let primaryDuration = max(0, primaryItem.durationSeconds)
        let rawPrimaryTime = max(0, min(primary.playbackTimeSnapshot(), primaryDuration))
        let primaryFrame = CompareReviewTimeline.frameIndex(
            for: rawPrimaryTime,
            duration: primaryDuration,
            frameRate: primaryRate
        )
        let primaryTime = CompareReviewTimeline.time(
            forFrame: primaryFrame,
            duration: primaryDuration,
            frameRate: primaryRate
        )

        let secondaryTimecodeRate = TimecodeFormatter.effectiveTimecodeRate(for: secondaryItem)
        let secondaryRate = secondaryTimecodeRate.value
        let secondaryDuration = max(0, secondaryItem.durationSeconds)
        let rawSecondaryTime = max(
            0,
            min(mappedSecondaryTime(for: primaryTime), secondaryDuration)
        )
        let secondaryFrame = CompareReviewTimeline.frameIndex(
            for: rawSecondaryTime,
            duration: secondaryDuration,
            frameRate: secondaryRate
        )
        let secondaryTime = CompareReviewTimeline.time(
            forFrame: secondaryFrame,
            duration: secondaryDuration,
            frameRate: secondaryRate
        )

        let note = CompareReviewNote(
            primaryFrame: primaryFrame,
            primaryTime: primaryTime,
            secondaryFrame: secondaryFrame,
            secondaryTime: secondaryTime,
            primaryRateNumerator: primaryTimecodeRate.numerator,
            primaryRateDenominator: primaryTimecodeRate.denominator,
            secondaryRateNumerator: secondaryTimecodeRate.numerator,
            secondaryRateDenominator: secondaryTimecodeRate.denominator,
            text: text
        )
        reviewNotes.append(note)
        reviewNotes.sort {
            ($0.primaryFrame, $0.createdAt) < ($1.primaryFrame, $1.createdAt)
        }
        persistReviewMutation(
            .upsert(note),
            primaryURL: primaryItem.url,
            secondaryURL: secondaryItem.url
        )
        return true
    }

    func updateReviewNote(id: UUID, text: String) {
        guard let index = reviewNotes.firstIndex(where: { $0.id == id }),
              canEditReviewNotes,
              let primaryURL = primaryAudioController?.mediaItem?.url,
              let secondaryURL else { return }
        reviewNotes[index].text = text
        reviewNotes[index].updatedAt = Date()
        persistReviewMutation(
            .upsert(reviewNotes[index]),
            primaryURL: primaryURL,
            secondaryURL: secondaryURL
        )
    }

    func deleteReviewNote(id: UUID) {
        guard canEditReviewNotes,
              let primaryURL = primaryAudioController?.mediaItem?.url,
              let secondaryURL else { return }
        reviewNotes.removeAll { $0.id == id }
        persistReviewMutation(
            .delete(id),
            primaryURL: primaryURL,
            secondaryURL: secondaryURL
        )
    }

    func seekToReviewNote(_ note: CompareReviewNote, primary: PlayerController) {
        let time = primary.mediaItem.map { reviewNotePrimaryTime(note, primaryItem: $0) }
            ?? note.primaryTime
        seek(primary: primary, to: time)
    }

    func reviewNotePrimaryTime(_ note: CompareReviewNote, primaryItem: MediaItem) -> TimeInterval {
        let rate = Double(note.primaryRateNumerator) / Double(note.primaryRateDenominator)
        return CompareReviewTimeline.time(
            forFrame: note.primaryFrame,
            duration: primaryItem.durationSeconds,
            frameRate: rate,
            fallback: note.primaryTime
        )
    }

    private func loadReviewNotes(
        primaryURL: URL,
        secondaryURL: URL,
        generation: UInt64
    ) {
        reviewLoadTask?.cancel()
        let sidecarURL = CompareReviewSidecarStore.sidecarURL(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL
        )
        reviewSidecarURL = sidecarURL
        isReviewLoading = true
        isReviewSidecarWritable = false
        reviewRevision &+= 1
        let loadRevision = reviewRevision
        reviewLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let document = try await self.reviewStore.load(
                    from: sidecarURL,
                    primaryURL: primaryURL,
                    secondaryURL: secondaryURL
                )
                guard !Task.isCancelled,
                      self.loadGeneration.isCurrent(generation),
                      self.reviewRevision == loadRevision,
                      self.secondaryURL == secondaryURL else { return }
                self.reviewNotes = (document?.notes ?? []).sorted {
                    ($0.primaryFrame, $0.createdAt) < ($1.primaryFrame, $1.createdAt)
                }
                self.reviewError = nil
                self.isReviewSidecarWritable = true
            } catch {
                guard !Task.isCancelled,
                      self.loadGeneration.isCurrent(generation),
                      self.reviewRevision == loadRevision else { return }
                self.reviewNotes = []
                self.reviewError = "Could not load comparison notes: \(error.localizedDescription)"
                self.isReviewSidecarWritable = false
            }
            self.isReviewLoading = false
            self.reviewLoadTask = nil
        }
    }

    private func persistReviewMutation(
        _ mutation: CompareReviewMutation,
        primaryURL: URL,
        secondaryURL: URL
    ) {
        guard let reviewSidecarURL else { return }
        reviewRevision &+= 1
        let revision = reviewRevision
        let previousSave = reviewSaveTask
        let reviewStore = reviewStore
        reviewSaveTask = Task { @MainActor [weak self] in
            await previousSave?.value
            guard !Task.isCancelled else { return }
            do {
                let document = try await reviewStore.apply(
                    mutation,
                    to: reviewSidecarURL,
                    primaryURL: primaryURL,
                    secondaryURL: secondaryURL
                )
                guard let self else { return }
                guard !Task.isCancelled, revision == self.reviewRevision else { return }
                self.reviewNotes = document.notes
                self.reviewError = nil
                self.reviewSaveTask = nil
            } catch {
                guard let self else { return }
                guard !Task.isCancelled, revision == self.reviewRevision else { return }
                self.reviewError = "Could not save comparison notes: \(error.localizedDescription)"
                self.reviewSaveTask = nil
            }
        }
    }

    func togglePlayback(primary: PlayerController) {
        if primary.isPlaying || secondaryController.isPlaying {
            pause(primary: primary)
        } else {
            play(primary: primary)
        }
    }

    func play(primary: PlayerController) {
        guard isActive else {
            primary.play()
            return
        }
        synchronize(primary: primary)
        primary.play()
        if secondaryController.isReady {
            secondaryController.play()
        }
        startDriftCorrection(primary: primary)
    }

    func pause(primary: PlayerController) {
        primary.pause()
        guard isActive else { return }
        secondaryController.pause()
        stopDriftCorrection()
        synchronize(primary: primary)
    }

    func reverse(primary: PlayerController) {
        guard isActive else {
            primary.startReverse()
            return
        }
        synchronize(primary: primary)
        primary.startReverse()
        secondaryController.startReverse()
        startDriftCorrection(primary: primary)
    }

    func fastForward(primary: PlayerController) {
        guard isActive else {
            primary.fastForward()
            return
        }
        synchronize(primary: primary)
        primary.fastForward()
        secondaryController.fastForward()
        startDriftCorrection(primary: primary)
    }

    func slowForward(primary: PlayerController) {
        guard isActive else {
            primary.slowForward()
            return
        }
        synchronize(primary: primary)
        primary.slowForward()
        secondaryController.slowForward()
        startDriftCorrection(primary: primary)
    }

    func slowReverse(primary: PlayerController) {
        guard isActive else {
            primary.slowReverse()
            return
        }
        synchronize(primary: primary)
        primary.slowReverse()
        secondaryController.slowReverse()
        startDriftCorrection(primary: primary)
    }

    func seek(primary: PlayerController, by seconds: TimeInterval) {
        let duration = max(0, primary.mediaItem?.durationSeconds ?? 0)
        let target = max(0, min(primary.currentPlaybackTime + seconds, duration))
        seek(primary: primary, to: target)
    }

    func seekByFrames(primary: PlayerController, frameCount: Int) {
        let frameRate = primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
        let effectiveRate = frameRate.flatMap { $0 > 0 ? $0 : nil } ?? 30
        seek(primary: primary, by: Double(frameCount) / effectiveRate)
    }

    func seek(primary: PlayerController, to time: TimeInterval) {
        primary.seekTo(time)
        guard isActive else { return }
        secondaryController.seekTo(mappedSecondaryTime(for: time))
    }

    func scrub(primary: PlayerController, to time: TimeInterval) {
        primary.scrub(to: time)
        guard isActive else { return }
        secondaryController.scrub(to: mappedSecondaryTime(for: time))
    }

    func endScrubbing(primary: PlayerController, at time: TimeInterval) {
        primary.endScrubbing(at: time)
        guard isActive else { return }
        secondaryController.endScrubbing(at: mappedSecondaryTime(for: time))
    }

    func reload(primary: PlayerController) {
        guard isActive else {
            primary.preparePlayback(startTime: primary.currentPlaybackTime, resetAudioSelection: false)
            return
        }
        let wasPlaying = primary.isPlaying
        primary.pause()
        secondaryController.pause()
        stopDriftCorrection()
        let primaryTime = primary.currentPlaybackTime
        let secondaryTime = mappedSecondaryTime(for: primaryTime)
        primary.preparePlayback(startTime: primaryTime, resetAudioSelection: false)
        secondaryController.preparePlayback(startTime: secondaryTime, resetAudioSelection: false)
        if wasPlaying {
            startSecondaryWhenReady(
                primary: primary,
                generation: loadGeneration.current,
                resumePlayback: true
            )
        }
    }

    func synchronize(primary: PlayerController) {
        guard isActive, secondaryController.isReady else { return }
        let expected = mappedSecondaryTime(for: primary.currentPlaybackTime)
        secondaryController.seekTo(expected)
    }

    func secondaryTime(forPrimaryTime primaryTime: TimeInterval) -> TimeInterval {
        mappedSecondaryTime(for: primaryTime)
    }

    func captureComparisonStill(primary: PlayerController) {
        guard isActive,
              isSecondaryReady,
              let secondaryItem = secondaryController.mediaItem,
              let mapping else { return }
        let primaryTime = primary.currentPlaybackTime
        primary.captureComparisonStill(
            secondaryItem: secondaryItem,
            secondaryTime: secondaryTime(forPrimaryTime: primaryTime),
            alignmentMode: mapping.mode
        )
    }

    private func mappedSecondaryTime(for primaryTime: TimeInterval) -> TimeInterval {
        mapping?.secondaryTime(
            forPrimaryTime: primaryTime,
            secondaryDuration: secondaryController.mediaItem?.durationSeconds
        ) ?? primaryTime
    }

    private func startSecondaryWhenReady(
        primary: PlayerController,
        generation: UInt64,
        resumePlayback: Bool = false
    ) {
        readinessTask?.cancel()
        readinessTask = Task { @MainActor [weak self, weak primary] in
            guard let self, let primary else { return }
            for _ in 0..<200 {
                guard !Task.isCancelled,
                      self.loadGeneration.isCurrent(generation),
                      self.isActive else { return }
                let primaryIsReady = primary.isReady
                if self.secondaryController.isReady && (!resumePlayback || primaryIsReady) {
                    self.synchronize(primary: primary)
                    if primary.frameCapture.isCapturing {
                        // Loading/replacing B tears down its backend and capture
                        // attachment. Restart only after the replacement backend
                        // is ready so AVFoundation can attach its video output.
                        self.secondaryController.frameCapture.stopCapture(rebuildPipeline: false)
                        self.secondaryController.frameCapture.startCapture()
                    }
                    if resumePlayback {
                        primary.play()
                    }
                    if primary.isPlaying {
                        self.secondaryController.play()
                        self.startDriftCorrection(primary: primary)
                    }
                    self.readinessTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled, self.loadGeneration.isCurrent(generation) else { return }
            self.selectAudioSource(.primary, primary: primary)
            self.loadError = "The comparison file did not become ready for playback."
            self.readinessTask = nil
        }
    }

    private func startDriftCorrection(primary: PlayerController) {
        guard isActive else { return }
        stopDriftCorrection()
        let generation = loadGeneration.current
        driftCorrectionTask = Task { @MainActor [weak self, weak primary] in
            guard let self, let primary else { return }
            while !Task.isCancelled,
                  self.loadGeneration.isCurrent(generation),
                  self.isActive {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      primary.isPlaying,
                      self.secondaryController.isPlaying else { continue }

                let expected = self.mappedSecondaryTime(for: primary.currentPlaybackTime)
                let drift = abs(self.secondaryController.currentPlaybackTime - expected)
                let frameRate = primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
                let frameDuration = 1 / max(frameRate ?? 30, 1)
                if drift > max(frameDuration, 0.05) {
                    self.secondaryController.seekTo(expected)
                }
            }
        }
    }

    private func stopDriftCorrection() {
        driftCorrectionTask?.cancel()
        driftCorrectionTask = nil
    }
}
