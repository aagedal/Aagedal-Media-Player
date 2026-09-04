// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation
import OSLog
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

nonisolated enum CompareFrameResolution: String, CaseIterable, Sendable {
    case full
    case reduced

    var label: String {
        switch self {
        case .full: "Full Frame"
        case .reduced: "Reduced Frame (½)"
        }
    }

    var renderScale: CGFloat {
        switch self {
        case .full: 1
        case .reduced: 0.5
        }
    }

    func surfaceSize(for canvasSize: CGSize) -> CGSize {
        let width = canvasSize.width.isFinite ? max(0, canvasSize.width) : 0
        let height = canvasSize.height.isFinite ? max(0, canvasSize.height) : 0
        return CGSize(width: width * renderScale, height: height * renderScale)
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

nonisolated enum CompareOverlapStatus: Equatable, Sendable {
    case full
    case partial
    case none
    case unknown

    var label: String {
        switch self {
        case .full: "Full overlap"
        case .partial: "Partial overlap"
        case .none: "No overlap"
        case .unknown: "Overlap unknown"
        }
    }
}

/// Whether source B can advance with source A at the current mapped time.
/// Outside the shared interval B must remain parked on its nearest boundary;
/// otherwise an independent decoder clock makes it run away from the clamp and
/// periodically snap back under drift correction.
nonisolated enum CompareSecondaryPlaybackDisposition: Equatable, Sendable {
    case advance
    case holdAtStart
    case holdAtEnd
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
        primaryOverlapRange(
            primaryDuration: primaryDuration,
            secondaryDuration: secondaryDuration
        )
    }

    func primaryOverlapRange(
        primaryDuration: TimeInterval,
        secondaryDuration overrideDuration: TimeInterval?
    ) -> ClosedRange<TimeInterval>? {
        let primaryDuration = max(0, primaryDuration.isFinite ? primaryDuration : 0)
        let secondaryDuration = resolvedSecondaryDuration(overrideDuration)
        guard primaryDuration > 0, secondaryDuration > 0 else { return nil }
        let lowerBound = max(0, -offset)
        let upperBound = min(primaryDuration, secondaryDuration - offset)
        // Timelines that merely touch at one endpoint share no playable span.
        guard upperBound > lowerBound else { return nil }
        return lowerBound...upperBound
    }

    func overlapStatus(
        primaryDuration: TimeInterval,
        secondaryDuration overrideDuration: TimeInterval? = nil
    ) -> CompareOverlapStatus {
        let primaryDuration = max(0, primaryDuration.isFinite ? primaryDuration : 0)
        let secondaryDuration = resolvedSecondaryDuration(overrideDuration)
        guard primaryDuration > 0, secondaryDuration > 0 else { return .unknown }
        guard let overlap = primaryOverlapRange(
            primaryDuration: primaryDuration,
            secondaryDuration: secondaryDuration
        ) else { return .none }
        return overlap.lowerBound <= 0 && overlap.upperBound >= primaryDuration
            ? .full
            : .partial
    }

    /// Describes the mapping equation for the relative point in B that matches
    /// A's current relative time. A positive value means B is that far into
    /// its file when A is at its first frame; a negative value means B begins
    /// later than A.
    func offsetLabel(
        primaryFrameRate: Double?,
        dropFrame: Bool = false
    ) -> String {
        let sign = offset < 0 ? "−" : "+"
        let rate = TimecodeRate(
            frameRate: primaryFrameRate ?? 30,
            dropFrame: dropFrame
        )
        let frames = rate.frameCount(forSeconds: abs(offset)) ?? 0
        let timecode = rate.timecode(forFrameCount: frames)
        return "B = A \(sign)\(timecode)"
    }

    func secondaryPlaybackDisposition(
        forPrimaryTime primaryTime: TimeInterval,
        primaryPlaybackSpeed: Float,
        secondaryDuration overrideDuration: TimeInterval? = nil
    ) -> CompareSecondaryPlaybackDisposition {
        let secondaryDuration = resolvedSecondaryDuration(overrideDuration)
        guard secondaryDuration > 0,
              primaryPlaybackSpeed.isFinite,
              primaryPlaybackSpeed != 0 else { return .advance }
        let primaryTime = primaryTime.isFinite ? primaryTime : 0
        let unboundedSecondaryTime = primaryTime + offset

        if unboundedSecondaryTime < 0
            || (unboundedSecondaryTime == 0 && primaryPlaybackSpeed < 0) {
            return .holdAtStart
        }
        if unboundedSecondaryTime > secondaryDuration
            || (unboundedSecondaryTime == secondaryDuration && primaryPlaybackSpeed > 0) {
            return .holdAtEnd
        }
        return .advance
    }

    private func resolvedSecondaryDuration(_ overrideDuration: TimeInterval?) -> TimeInterval {
        let overrideDuration = overrideDuration.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        return overrideDuration ?? secondaryDuration
    }
}

/// Decides when the secondary decoder must be re-synchronized with the
/// primary backend clock. The tolerance is one primary frame plus a small
/// clock-comparison margin; a short cooldown prevents a decoder with an
/// outstanding seek from being flooded with duplicate corrections.
nonisolated struct CompareDriftPolicy: Equatable, Sendable {
    static let fallbackFrameRate = 30.0
    static let correctionCooldown: TimeInterval = 0.25
    static let correctionSettlementTimeout: TimeInterval = 1
    static let clockComparisonTolerance: TimeInterval = 0.001
    static let avFoundationRateNudgeFraction = 0.25
    static let maximumRateCorrectionFraction = 0.5
    static let rateCorrectionGain = 2.0
    static let hardSeekThreshold: TimeInterval = 1
    static let monitoringWarmup: TimeInterval = 0.75

    let frameRate: Double

    init(primaryFrameRate: Double?) {
        if let primaryFrameRate,
           primaryFrameRate.isFinite,
           primaryFrameRate > 0 {
            frameRate = primaryFrameRate
        } else {
            frameRate = Self.fallbackFrameRate
        }
    }

    var frameDuration: TimeInterval { 1 / frameRate }
    var correctionThreshold: TimeInterval {
        frameDuration + Self.clockComparisonTolerance
    }

    func signedDrift(
        actualSecondaryTime: TimeInterval,
        expectedSecondaryTime: TimeInterval
    ) -> TimeInterval? {
        guard actualSecondaryTime.isFinite, expectedSecondaryTime.isFinite else { return nil }
        return actualSecondaryTime - expectedSecondaryTime
    }

    func correctionTarget(
        actualSecondaryTime: TimeInterval,
        expectedSecondaryTime: TimeInterval,
        timeSinceLastCorrection: TimeInterval
    ) -> TimeInterval? {
        guard timeSinceLastCorrection >= Self.correctionCooldown,
              let drift = signedDrift(
                actualSecondaryTime: actualSecondaryTime,
                expectedSecondaryTime: expectedSecondaryTime
              ),
              abs(drift) > correctionThreshold else { return nil }
        return expectedSecondaryTime
    }
}

@MainActor
final class CompareSessionController: ObservableObject {
    typealias MetadataLoader = @MainActor @Sendable (URL) async throws -> MediaMetadata

    nonisolated static let minimumDifferenceGain = 1.0
    nonisolated static let maximumDifferenceGain = 16.0
    private nonisolated static let signposter = OSSignposter(
        subsystem: "com.aagedal.MediaPlayer",
        category: "CompareMode"
    )

    let secondaryController: PlayerController
    let secondaryWaveformGenerator = AudioWaveformGenerator()

    @Published var viewMode: CompareViewMode = .sideBySide
    @Published private(set) var frameResolution: CompareFrameResolution = .full
    @Published private(set) var wipePosition = 0.5
    @Published private(set) var overlayBlend = 0.5
    @Published private(set) var differenceGain = 1.0
    @Published var scopeSource: CompareScopeSource = .primary
    @Published var safeAreaGuide: CompareSafeAreaGuide = .none
    @Published var aspectRatioGuide: CompareAspectRatioGuide = .none
    @Published private(set) var audioSource: CompareAudioSource = .primary
    @Published private(set) var comparedAudioChannel: CompareAudioChannelOption?
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
    private var secondaryLoadSignpostState: OSSignpostIntervalState?
    private var driftMonitoringSignpostState: OSSignpostIntervalState?
    private var audioTrackSelectionTask: Task<Void, Never>?
    private var reviewLoadTask: Task<Void, Never>?
    private var reviewSaveTask: Task<Void, Never>?
    private var reviewExportTask: Task<Void, Never>?
    private var reviewExportSavePanel: NSSavePanel?
    private var shouldResumeAfterAudioTrackSelection = false
    private var secondaryBoundaryHold: CompareSecondaryPlaybackDisposition?
    private var secondaryPlaybackPhaseCancellable: AnyCancellable?
    private var loadGeneration = OperationGeneration()
    private var reviewRevision: UInt64 = 0
    private var isReviewSidecarWritable = false
    private let reviewStore = CompareReviewSidecarStore.shared
    private let metadataLoader: MetadataLoader
    private weak var primaryAudioController: PlayerController?

    var isActive: Bool { secondaryURL != nil }
    var canEditReviewNotes: Bool {
        isActive && !isReviewLoading && isReviewSidecarWritable
    }

    init(
        secondaryController: PlayerController? = nil,
        metadataLoader: @escaping MetadataLoader = { url in
            try await MetadataService.shared.metadata(for: url)
        }
    ) {
        self.secondaryController = secondaryController ?? PlayerController()
        self.metadataLoader = metadataLoader
        self.secondaryController.setAudioSuppressed(true)
        secondaryPlaybackPhaseCancellable = self.secondaryController.$playbackPhase
            .sink { [weak self] phase in
                guard let self else { return }
                self.handleSecondaryPlaybackPhase(phase)
            }
    }

    func handleSecondaryPlaybackPhase(_ phase: PlaybackPhase) {
        isSecondaryReady = phase.permitsPlaybackControls
        guard case .failed(let failure) = phase,
              isActive,
              let primary = primaryAudioController else { return }
        // A decoder failure is terminal for this readiness attempt. Without
        // cancelling the poller, its later timeout can replace the specific
        // backend diagnostic with a generic message.
        readinessTask?.cancel()
        readinessTask = nil
        endSecondaryLoadSignpost()
        Self.signposter.emitEvent("Secondary decoder failed")
        selectComparedAudioChannel(nil, primary: primary)
        selectAudioSource(.primary, primary: primary)
        loadError = "The comparison file could not be played: \(failure.message)"
    }

    func loadSecondary(_ url: URL, alignedWith primary: PlayerController) {
        if primaryAudioController !== primary {
            secondaryController.setAudioSuppressed(true)
            primaryAudioController?.setAudioSuppressed(false)
        }
        primaryAudioController = primary

        let generation = loadGeneration.advance()
        beginSecondaryLoadSignpost()
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
        secondaryBoundaryHold = nil
        secondaryWaveformGenerator.cancel()
        primary.setSessionAudioChannelRouting(nil)
        secondaryController.setSessionAudioChannelRouting(nil)
        comparedAudioChannel = nil
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
                let metadata = try await self.metadataLoader(url)
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
                forPrimaryTime: primary.playbackTimeSnapshot()
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
        secondaryBoundaryHold = nil
        endSecondaryLoadSignpost()
        secondaryWaveformGenerator.cancel()
        primaryAudioController?.setSessionAudioChannelRouting(nil)
        secondaryController.setSessionAudioChannelRouting(nil)
        comparedAudioChannel = nil
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
        frameResolution = .full
        wipePosition = 0.5
        overlayBlend = 0.5
        differenceGain = 1
        scopeSource = .primary
        safeAreaGuide = .none
        aspectRatioGuide = .none
        audioSource = .primary
    }

    func availableComparedAudioChannels(primary: PlayerController) -> [CompareAudioChannelOption] {
        CompareAudioChannelMatcher.options(
            primaryCount: primary.selectedAudioChannelCount,
            primaryLayout: primary.selectedAudioStream?.channelLayout,
            secondaryCount: secondaryController.selectedAudioChannelCount,
            secondaryLayout: secondaryController.selectedAudioStream?.channelLayout
        )
    }

    func selectComparedAudioChannel(
        _ option: CompareAudioChannelOption?,
        primary: PlayerController
    ) {
        guard let option else {
            comparedAudioChannel = nil
            primary.setSessionAudioChannelRouting(nil)
            secondaryController.setSessionAudioChannelRouting(nil)
            return
        }

        let available = availableComparedAudioChannels(primary: primary)
        guard let current = available.first(where: { $0.id == option.id }) else {
            selectComparedAudioChannel(nil, primary: primary)
            return
        }
        comparedAudioChannel = current
        primary.setSessionAudioChannelRouting(
            AudioChannelRouting(
                channelCount: primary.selectedAudioChannelCount,
                soloedChannels: [current.primaryIndex]
            )
        )
        secondaryController.setSessionAudioChannelRouting(
            AudioChannelRouting(
                channelCount: secondaryController.selectedAudioChannelCount,
                soloedChannels: [current.secondaryIndex]
            )
        )
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
            if let comparedAudioChannel = self.comparedAudioChannel,
               let updatedChannel = self.availableComparedAudioChannels(primary: primary).first(where: {
                   $0.id == comparedAudioChannel.id
               }) {
                self.selectComparedAudioChannel(updatedChannel, primary: primary)
            } else {
                self.selectComparedAudioChannel(nil, primary: primary)
            }
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

    func setFrameResolution(_ resolution: CompareFrameResolution, primary: PlayerController) {
        guard frameResolution != resolution else { return }
        frameResolution = resolution
        // MPV's Metal destination can retain its old drawable size after a
        // large surface growth. Reuse the paired reload path so both backends
        // restart at the same timeline position and the requested resolution
        // is applied predictably in either direction.
        if isActive, isSecondaryReady {
            reload(primary: primary)
        }
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
        panel.allowedContentTypes = switch format {
        case .csv: [.commaSeparatedText]
        case .pdf: [.pdf]
        case .resolveMarkersEDL:
            [UTType(filenameExtension: "edl") ?? .plainText]
        case .finalCutProXML:
            [UTType(filenameExtension: "fcpxml") ?? .xml]
        case .avidMarkersText:
            [.plainText]
        }
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
                        let annotatedStills = if format == .pdf {
                            try await CompareReviewReportExporter.annotatedStillData(
                                snapshot: snapshot
                            )
                        } else {
                            [Int: Data]()
                        }
                        try Task.checkCancellation()
                        let data = try CompareReviewReportExporter.data(
                            for: format,
                            snapshot: snapshot,
                            annotatedStills: annotatedStills
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
        primary.play()
        updateSecondaryTransport(primary: primary, forceRateMatch: true)
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
        updateSecondaryTransport(primary: primary, forceRateMatch: true)
        startDriftCorrection(primary: primary)
    }

    func fastForward(primary: PlayerController) {
        guard isActive else {
            primary.fastForward()
            return
        }
        synchronize(primary: primary)
        primary.fastForward()
        updateSecondaryTransport(primary: primary, forceRateMatch: true)
        startDriftCorrection(primary: primary)
    }

    func slowForward(primary: PlayerController) {
        guard isActive else {
            primary.slowForward()
            return
        }
        synchronize(primary: primary)
        primary.slowForward()
        updateSecondaryTransport(primary: primary, forceRateMatch: true)
        startDriftCorrection(primary: primary)
    }

    func slowReverse(primary: PlayerController) {
        guard isActive else {
            primary.slowReverse()
            return
        }
        synchronize(primary: primary)
        primary.slowReverse()
        updateSecondaryTransport(primary: primary, forceRateMatch: true)
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
        if primary.isPlaying {
            updateSecondaryTransport(primary: primary, at: time)
        }
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
        let primaryTime = primary.playbackTimeSnapshot()
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
        let expected = mappedSecondaryTime(for: primary.playbackTimeSnapshot())
        secondaryController.seekTo(expected)
    }

    func secondaryTime(forPrimaryTime primaryTime: TimeInterval) -> TimeInterval {
        mappedSecondaryTime(for: primaryTime)
    }

    func overlapStatus(primaryDuration: TimeInterval) -> CompareOverlapStatus {
        mapping?.overlapStatus(
            primaryDuration: primaryDuration,
            secondaryDuration: secondaryController.mediaItem?.durationSeconds
        ) ?? .unknown
    }

    func primaryOverlapRange(
        primaryDuration: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        mapping?.primaryOverlapRange(
            primaryDuration: primaryDuration,
            secondaryDuration: secondaryController.mediaItem?.durationSeconds
        )
    }

    func captureComparisonStill(primary: PlayerController) {
        guard isActive,
              isSecondaryReady,
              let secondaryItem = secondaryController.mediaItem,
              let mapping else { return }
        let primaryTime = primary.playbackTimeSnapshot()
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
                    self.endSecondaryLoadSignpost()
                    let primaryBackend = primary.useMPV ? "MPV" : "AVFoundation"
                    let secondaryBackend = self.secondaryController.useMPV ? "MPV" : "AVFoundation"
                    Self.signposter.emitEvent(
                        "Secondary decoder ready",
                        "primary=\(primaryBackend, privacy: .public) secondary=\(secondaryBackend, privacy: .public)"
                    )
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
                        self.updateSecondaryTransport(
                            primary: primary,
                            forceRateMatch: true
                        )
                        self.startDriftCorrection(primary: primary)
                    }
                    self.readinessTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled, self.loadGeneration.isCurrent(generation) else { return }
            self.handleSecondaryReadinessTimeout(primary: primary)
        }
    }

    func handleSecondaryReadinessTimeout(primary: PlayerController) {
        guard loadError == nil else {
            readinessTask = nil
            return
        }
        endSecondaryLoadSignpost()
        Self.signposter.emitEvent("Secondary decoder readiness timeout")
        selectAudioSource(.primary, primary: primary)
        loadError = "The comparison file did not become ready for playback."
        readinessTask = nil
    }

    private func updateSecondaryTransport(
        primary: PlayerController,
        at primaryTimeOverride: TimeInterval? = nil,
        forceRateMatch: Bool = false
    ) {
        guard isActive, secondaryController.isReady, let mapping else { return }
        let primaryTime = primaryTimeOverride ?? primary.playbackTimeSnapshot()
        let disposition = mapping.secondaryPlaybackDisposition(
            forPrimaryTime: primaryTime,
            primaryPlaybackSpeed: primary.currentPlaybackSpeed,
            secondaryDuration: secondaryController.mediaItem?.durationSeconds
        )

        switch disposition {
        case .advance:
            let wasHeldAtBoundary = secondaryBoundaryHold != nil
            secondaryBoundaryHold = nil
            guard primary.isPlaying else { return }
            if wasHeldAtBoundary {
                secondaryController.seekTo(mappedSecondaryTime(for: primaryTime))
            }
            let speedMismatch = abs(
                secondaryController.currentPlaybackSpeed - primary.currentPlaybackSpeed
            ) > 0.001
            if forceRateMatch || wasHeldAtBoundary
                || !secondaryController.isPlaying || speedMismatch {
                matchSecondaryTransport(to: primary.currentPlaybackSpeed)
            }

        case .holdAtStart, .holdAtEnd:
            let enteredBoundary = secondaryBoundaryHold != disposition
            secondaryBoundaryHold = disposition
            if enteredBoundary || secondaryController.isPlaying {
                secondaryController.pause()
                secondaryController.seekTo(mappedSecondaryTime(for: primaryTime))
            }
        }
    }

    private func matchSecondaryTransport(to primarySpeed: Float) {
        guard primarySpeed.isFinite, primarySpeed != 0 else {
            secondaryController.pause()
            return
        }

        if primarySpeed > 0 {
            secondaryController.playForSynchronization(atRate: primarySpeed)
            return
        }

        secondaryController.pause()
        let targetMagnitude = abs(primarySpeed)
        if targetMagnitude >= 1 {
            secondaryController.startReverse()
            for _ in 1..<min(8, max(1, Int(targetMagnitude.rounded()))) {
                secondaryController.startReverse()
            }
            return
        }

        // Slow reverse exposes four discrete rates: .75, .5, .25, and .1.
        // Step through the same public transport states until B matches A.
        for _ in 0..<4 {
            secondaryController.slowReverse()
            if abs(secondaryController.currentPlaybackSpeed - primarySpeed) <= 0.001 {
                break
            }
        }
    }

    private func startDriftCorrection(primary: PlayerController) {
        guard isActive else { return }
        stopDriftCorrection()
        driftMonitoringSignpostState = Self.signposter.beginInterval("Drift monitoring")
        let generation = loadGeneration.current
        let frameRate = primary.mediaItem?.metadata?.primaryVideoStream?.frameRate?.value
        let policy = CompareDriftPolicy(primaryFrameRate: frameRate)
        let sampleInterval = min(policy.frameDuration, 0.05)
        driftCorrectionTask = Task { @MainActor [weak self, weak primary] in
            guard let self, let primary else { return }
            var lastCorrectionTime = -TimeInterval.infinity
            var outOfToleranceSince: TimeInterval?
            var isWaitingForCorrectionToSettle = false
            var isRateNudged = false
            let monitoringStartTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled,
                  self.loadGeneration.isCurrent(generation),
                  self.isActive {
                try? await Task.sleep(for: .seconds(sampleInterval))
                guard !Task.isCancelled,
                      primary.isPlaying else { continue }

                let primaryBefore = primary.playbackTimeSnapshot()
                let primaryAfter = primary.playbackTimeSnapshot()
                let primaryTime = (primaryBefore + primaryAfter) / 2
                let previousBoundaryHold = self.secondaryBoundaryHold
                self.updateSecondaryTransport(primary: primary, at: primaryTime)
                if self.secondaryBoundaryHold != nil {
                    if isRateNudged {
                        self.secondaryController.restoreSynchronizationPlaybackRate()
                        isRateNudged = false
                    }
                    outOfToleranceSince = nil
                    isWaitingForCorrectionToSettle = false
                    continue
                }
                guard self.secondaryController.isPlaying else { continue }
                if previousBoundaryHold != nil {
                    // The newly resumed decoder has just been positioned at
                    // the mapped time; let that seek settle before measuring.
                    lastCorrectionTime = ProcessInfo.processInfo.systemUptime
                    outOfToleranceSince = nil
                    isWaitingForCorrectionToSettle = true
                    continue
                }

                let actual = self.secondaryController.playbackTimeSnapshot()
                let expected = self.mappedSecondaryTime(for: primaryTime)
                let readUncertainty = abs(primaryAfter - primaryBefore) / 2
                let sampleTime = ProcessInfo.processInfo.systemUptime
                guard sampleTime - monitoringStartTime >=
                        CompareDriftPolicy.monitoringWarmup else { continue }
                guard let signedDrift = policy.signedDrift(
                    actualSecondaryTime: actual,
                    expectedSecondaryTime: expected
                ) else { continue }

                let absoluteDrift = max(0, abs(signedDrift) - readUncertainty)
                let baseRate = max(0.1, abs(primary.currentPlaybackSpeed))
                if absoluteDrift <= policy.frameDuration / 2 {
                    if isRateNudged {
                        self.secondaryController.restoreSynchronizationPlaybackRate()
                        isRateNudged = false
                    }
                    outOfToleranceSince = nil
                    isWaitingForCorrectionToSettle = false
                    continue
                }

                // Let a hard seek settle before considering a rate nudge. An
                // intermediate decoder clock can otherwise turn one recovery
                // operation into two competing corrections.
                if isWaitingForCorrectionToSettle {
                    guard sampleTime - lastCorrectionTime >=
                            CompareDriftPolicy.correctionSettlementTimeout else { continue }
                    isWaitingForCorrectionToSettle = false
                    outOfToleranceSince = sampleTime
                    continue
                }

                if absoluteDrift > policy.correctionThreshold,
                   !primary.isReversing,
                   !self.secondaryController.isReversing,
                   absoluteDrift < CompareDriftPolicy.hardSeekThreshold {
                    let multiplier: Double
                    if self.secondaryController.useMPV {
                        let maximumCorrection =
                            CompareDriftPolicy.maximumRateCorrectionFraction
                        let unboundedCorrection =
                            -signedDrift * CompareDriftPolicy.rateCorrectionGain
                        let rateCorrection = min(
                            maximumCorrection,
                            max(-maximumCorrection, unboundedCorrection)
                        )
                        multiplier = 1 + rateCorrection
                    } else {
                        // Reassigning AVPlayer.rate on every clock sample can
                        // repeatedly restart its timebase. Hold one modest
                        // nudge until the clocks enter the convergence band.
                        guard !isRateNudged else { continue }
                        multiplier = signedDrift > 0
                            ? 1 - CompareDriftPolicy.avFoundationRateNudgeFraction
                            : 1 + CompareDriftPolicy.avFoundationRateNudgeFraction
                    }
                    self.secondaryController.setSynchronizationPlaybackRate(
                        baseRate * Float(multiplier)
                    )
                    isRateNudged = true
                    Self.signposter.emitEvent(
                        "Drift correction rate",
                        "drift_ms=\(signedDrift * 1_000) multiplier=\(multiplier)"
                    )
                    outOfToleranceSince = nil
                    isWaitingForCorrectionToSettle = false
                    continue
                }

                if isRateNudged {
                    self.secondaryController.restoreSynchronizationPlaybackRate()
                    isRateNudged = false
                }

                guard absoluteDrift > policy.correctionThreshold,
                      sampleTime - lastCorrectionTime >=
                        CompareDriftPolicy.correctionCooldown else { continue }

                guard let excursionStart = outOfToleranceSince else {
                    outOfToleranceSince = sampleTime
                    continue
                }
                guard sampleTime - excursionStart >= CompareDriftPolicy.correctionCooldown,
                      let target = policy.correctionTarget(
                        actualSecondaryTime: actual,
                        expectedSecondaryTime: expected,
                        timeSinceLastCorrection: sampleTime - lastCorrectionTime
                      ) else { continue }

                lastCorrectionTime = sampleTime
                outOfToleranceSince = nil
                isWaitingForCorrectionToSettle = true
                Self.signposter.emitEvent(
                    "Drift correction seek",
                    "drift_ms=\(signedDrift * 1_000)"
                )
                self.secondaryController.seekTo(target)
            }
        }
    }

    private func stopDriftCorrection() {
        driftCorrectionTask?.cancel()
        driftCorrectionTask = nil
        secondaryController.restoreSynchronizationPlaybackRate()
        if let state = driftMonitoringSignpostState {
            Self.signposter.endInterval("Drift monitoring", state)
            driftMonitoringSignpostState = nil
        }
    }

    private func beginSecondaryLoadSignpost() {
        endSecondaryLoadSignpost()
        secondaryLoadSignpostState = Self.signposter.beginInterval("Secondary decoder load")
    }

    private func endSecondaryLoadSignpost() {
        guard let state = secondaryLoadSignpostState else { return }
        Self.signposter.endInterval("Secondary decoder load", state)
        secondaryLoadSignpostState = nil
    }
}
