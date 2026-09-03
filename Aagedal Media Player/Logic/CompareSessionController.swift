// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation

nonisolated enum CompareViewMode: String, CaseIterable, Sendable {
    case sideBySide
    case primary
    case secondary
    case verticalWipe
    case horizontalWipe
    case overlay

    var label: String {
        switch self {
        case .sideBySide: "A | B"
        case .primary: "A"
        case .secondary: "B"
        case .verticalWipe: "Vertical Wipe"
        case .horizontalWipe: "Horizontal Wipe"
        case .overlay: "Overlay"
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
    let secondaryController: PlayerController
    let secondaryWaveformGenerator = AudioWaveformGenerator()

    @Published var viewMode: CompareViewMode = .sideBySide
    @Published private(set) var wipePosition = 0.5
    @Published private(set) var overlayBlend = 0.5
    @Published private(set) var secondaryURL: URL?
    @Published private(set) var mapping: CompareTimelineMapping?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private var loadTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var driftCorrectionTask: Task<Void, Never>?
    private var loadGeneration = OperationGeneration()

    var isActive: Bool { secondaryURL != nil }

    init(secondaryController: PlayerController? = nil) {
        self.secondaryController = secondaryController ?? PlayerController()
        self.secondaryController.setAudioSuppressed(true)
    }

    func loadSecondary(_ url: URL, alignedWith primary: PlayerController) {
        let generation = loadGeneration.advance()
        loadTask?.cancel()
        readinessTask?.cancel()
        stopDriftCorrection()
        secondaryWaveformGenerator.cancel()
        secondaryController.teardown()
        secondaryController.setAudioSuppressed(true)

        isLoading = true
        loadError = nil
        secondaryURL = nil
        mapping = nil

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
        stopDriftCorrection()
        secondaryWaveformGenerator.cancel()
        secondaryController.teardown()
        secondaryController.setAudioSuppressed(true)
        secondaryURL = nil
        mapping = nil
        isLoading = false
        loadError = nil
        viewMode = .sideBySide
        wipePosition = 0.5
        overlayBlend = 0.5
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

    nonisolated static func clampedUnitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    func dismissLoadError() {
        loadError = nil
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
            startSecondaryWhenReady(primary: primary, generation: loadGeneration.current)
        }
    }

    func synchronize(primary: PlayerController) {
        guard isActive, secondaryController.isReady else { return }
        let expected = mappedSecondaryTime(for: primary.currentPlaybackTime)
        secondaryController.seekTo(expected)
    }

    private func mappedSecondaryTime(for primaryTime: TimeInterval) -> TimeInterval {
        mapping?.secondaryTime(
            forPrimaryTime: primaryTime,
            secondaryDuration: secondaryController.mediaItem?.durationSeconds
        ) ?? primaryTime
    }

    private func startSecondaryWhenReady(primary: PlayerController, generation: UInt64) {
        readinessTask?.cancel()
        readinessTask = Task { @MainActor [weak self, weak primary] in
            guard let self, let primary else { return }
            for _ in 0..<200 {
                guard !Task.isCancelled,
                      self.loadGeneration.isCurrent(generation),
                      self.isActive else { return }
                if self.secondaryController.isReady {
                    self.synchronize(primary: primary)
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
