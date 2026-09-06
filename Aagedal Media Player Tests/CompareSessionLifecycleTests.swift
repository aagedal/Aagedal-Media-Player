// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareSessionLifecycleTests: XCTestCase {
    func testManualAlignmentRestoresAutomaticAndResetsOnReplacementAndStop() async {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let session = makeSession(loader: loader)
        let firstURL = URL(fileURLWithPath: "/tmp/compare-offset-first.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/compare-offset-second.mov")
        session.loadSecondary(firstURL, alignedWith: primary)
        let requestedFirst = await waitUntil { loader.hasRequest(for: firstURL) }
        XCTAssertTrue(requestedFirst)
        loader.succeed(firstURL, metadata: metadata(duration: 20))
        let loadedFirst = await waitUntil { session.mapping != nil }
        XCTAssertTrue(loadedFirst)
        let automatic = session.mapping

        session.setManualOffset(-2, primary: primary)
        XCTAssertEqual(session.mapping?.mode, .manual)
        XCTAssertEqual(session.secondaryTime(forPrimaryTime: 5), 3)
        for invalid in [Double.nan, .infinity, 1e30, -1e30] {
            session.setManualOffset(invalid, primary: primary)
            XCTAssertEqual(session.mapping?.offset, -2)
        }
        session.setManualOffset(nil, primary: primary)
        XCTAssertEqual(session.mapping, automatic)
        session.setManualOffset(3, primary: primary)

        session.loadSecondary(secondURL, alignedWith: primary)
        XCTAssertNil(session.mapping)
        let requestedSecond = await waitUntil { loader.hasRequest(for: secondURL) }
        XCTAssertTrue(requestedSecond)
        loader.succeed(secondURL, metadata: metadata(duration: 10))
        let loadedSecond = await waitUntil { session.mapping != nil }
        XCTAssertTrue(loadedSecond)
        XCTAssertEqual(session.mapping?.mode, .relative)
        XCTAssertEqual(session.mapping?.offset, 0)
        session.setManualOffset(4, primary: primary)
        session.stop()
        session.setManualOffset(8, primary: primary)
        XCTAssertNil(session.mapping)
        primary.teardown()
    }

    func testRapidReplacementIgnoresStaleMetadataCompletion() async throws {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let session = makeSession(loader: loader)
        let firstURL = URL(fileURLWithPath: "/tmp/compare-first.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/compare-second.mov")

        session.reviewSearchQuery = "Previous pair"
        session.loadSecondary(firstURL, alignedWith: primary)
        XCTAssertEqual(session.reviewSearchQuery, "")
        let requestedFirst = await waitUntil { loader.hasRequest(for: firstURL) }
        XCTAssertTrue(requestedFirst)

        session.loadSecondary(secondURL, alignedWith: primary)
        let requestedSecond = await waitUntil { loader.hasRequest(for: secondURL) }
        XCTAssertTrue(requestedSecond)

        loader.succeed(secondURL, metadata: metadata(duration: 12))
        let loadedSecond = await waitUntil { session.secondaryURL == secondURL }
        XCTAssertTrue(loadedSecond)

        loader.succeed(firstURL, metadata: metadata(duration: 24))
        await settleMainActorTasks()

        XCTAssertEqual(session.secondaryURL, secondURL)
        XCTAssertEqual(session.mapping?.secondaryDuration, 12)
        XCTAssertFalse(session.isLoading)
        session.stop()
    }

    func testStopDuringMetadataLoadRejectsLateCompletionAndRestoresAudioSafety() async {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let secondary = PlayerController()
        let session = makeSession(loader: loader, secondary: secondary)
        let url = URL(fileURLWithPath: "/tmp/compare-stopped.mov")

        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        XCTAssertTrue(requested)

        session.stop()
        loader.succeed(url, metadata: metadata(duration: 10))
        await settleMainActorTasks()

        XCTAssertNil(session.secondaryURL)
        XCTAssertNil(session.mapping)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isLoading)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    func testClosingAcceptedWindowStopsMetadataLoadAndRejectsLateCompletion() async {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let secondary = PlayerController()
        let session = makeSession(loader: loader, secondary: secondary)
        let windowCoordinator = PlayerWindowCoordinator()
        let windowManager = WindowManager.shared
        let previousWindowsToAllow = windowManager.windowsToAllow
        windowManager.windowsToAllow += 1
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 711, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let url = URL(fileURLWithPath: "/tmp/compare-window-close.mov")
        var closeHandlerCallCount = 0

        defer {
            session.stop()
            primary.teardown()
            windowCoordinator.tearDown()
            windowManager.windowsToAllow = previousWindowsToAllow
        }

        XCTAssertTrue(
            windowCoordinator.accept(
                window,
                onClose: {
                    closeHandlerCallCount += 1
                    session.stop()
                    primary.cancelMediaOperationsForWindowClose()
                    primary.teardown()
                }
            )
        )
        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        XCTAssertTrue(requested)
        let preparationIDBeforeClose = secondary.preparationID

        window.close()

        XCTAssertEqual(closeHandlerCallCount, 1)
        XCTAssertNil(windowCoordinator.window)
        XCTAssertFalse(
            windowCoordinator.accept(window) {
                closeHandlerCallCount += 1
            }
        )
        XCTAssertNil(session.secondaryURL)
        XCTAssertNil(session.mapping)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isLoading)
        XCTAssertFalse(session.isSecondaryReady)
        XCTAssertGreaterThan(secondary.preparationID, preparationIDBeforeClose)
        XCTAssertEqual(secondary.playbackPhase, .idle)
        XCTAssertNil(secondary.player)
        XCTAssertNil(secondary.mpvPlayer)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)

        loader.succeed(url, metadata: metadata(duration: 10))
        await settleMainActorTasks()

        XCTAssertEqual(closeHandlerCallCount, 1)
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.secondaryURL)
        XCTAssertNil(secondary.player)
        XCTAssertNil(secondary.mpvPlayer)
    }

    func testStopDuringBackendPreparationRejectsLateDecoderCompletion() async {
        let loader = ControlledCompareMetadataLoader()
        let detector = ControlledCompareProResRAWDetector()
        let primary = PlayerController()
        let secondary = PlayerController { _, _ in
            await detector.result()
        }
        let session = makeSession(loader: loader, secondary: secondary)
        let url = URL(fileURLWithPath: "/tmp/compare-preparing.mov")

        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        guard requested else {
            XCTFail("Comparison metadata loading did not start.")
            session.stop()
            return
        }

        loader.succeed(url, metadata: metadata(duration: 10))
        await detector.waitUntilStarted()
        let activePreparationID = secondary.preparationID
        XCTAssertEqual(session.secondaryURL, url)
        XCTAssertEqual(secondary.playbackPhase, .preparing)

        // ContentView uses the same stop path when its window disappears.
        session.stop()
        XCTAssertGreaterThan(secondary.preparationID, activePreparationID)
        XCTAssertNil(session.secondaryURL)
        XCTAssertNil(session.mapping)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isLoading)
        XCTAssertFalse(session.isSecondaryReady)
        XCTAssertEqual(secondary.playbackPhase, .idle)
        XCTAssertNil(secondary.player)
        XCTAssertNil(secondary.mpvPlayer)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)

        detector.resume(returning: false)
        await settleMainActorTasks()

        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.loadError)
        XCTAssertEqual(secondary.playbackPhase, .idle)
        XCTAssertNil(secondary.player)
        XCTAssertNil(secondary.mpvPlayer)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
    }

    func testDecoderFailureRemainsMoreSpecificThanReadinessTimeout() async {
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        let session = makeSession(loader: loader)
        let url = URL(fileURLWithPath: "/tmp/compare-failed.mov")

        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        XCTAssertTrue(requested)
        loader.succeed(url, metadata: metadata(duration: 10))
        let loaded = await waitUntil { session.secondaryURL == url }
        XCTAssertTrue(loaded)

        let failure = PlaybackFailure(
            backend: .mpv,
            stage: .loading,
            message: "Decoder rejected the comparison stream.",
            mediaURL: url
        )
        session.handleSecondaryPlaybackPhase(.failed(failure))
        session.handleSecondaryReadinessTimeout(primary: primary)

        XCTAssertEqual(
            session.loadError,
            "The comparison file could not be played: Decoder rejected the comparison stream."
        )
        XCTAssertEqual(session.audioSource, .primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(session.secondaryController.isAudioSuppressed)
        session.stop()
    }

    func testReadinessTimeoutInvalidatesLateBackendCompletionAndRestoresAudioSafety() async {
        let loader = ControlledCompareMetadataLoader()
        let detector = ControlledCompareProResRAWDetector()
        let primary = PlayerController()
        let secondary = PlayerController { _, _ in
            await detector.result()
        }
        let session = makeSession(loader: loader, secondary: secondary)
        let url = URL(fileURLWithPath: "/tmp/compare-readiness-timeout.mov")

        session.loadSecondary(url, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: url) }
        guard requested else {
            XCTFail("Comparison metadata loading did not start.")
            session.stop()
            return
        }

        loader.succeed(url, metadata: metadata(duration: 10))
        await detector.waitUntilStarted()
        let activePreparationID = secondary.preparationID
        XCTAssertEqual(session.secondaryURL, url)
        XCTAssertEqual(secondary.playbackPhase, .preparing)

        session.selectAudioSource(.secondary, primary: primary)
        XCTAssertTrue(primary.isAudioSuppressed)
        XCTAssertFalse(secondary.isAudioSuppressed)

        session.handleSecondaryReadinessTimeout(primary: primary)

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.secondaryURL, url)
        XCTAssertNotNil(session.mapping)
        XCTAssertFalse(session.isSecondaryReady)
        XCTAssertEqual(
            session.loadError,
            "The comparison file did not become ready for playback."
        )
        XCTAssertEqual(session.audioSource, .primary)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
        XCTAssertGreaterThan(secondary.preparationID, activePreparationID)
        XCTAssertEqual(secondary.playbackPhase, .idle)
        XCTAssertNil(secondary.player)
        XCTAssertNil(secondary.mpvPlayer)

        detector.resume(returning: false)
        await settleMainActorTasks()

        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.isSecondaryReady)
        XCTAssertEqual(secondary.playbackPhase, .idle)
        XCTAssertNil(secondary.player)
        XCTAssertNil(secondary.mpvPlayer)
        XCTAssertFalse(primary.isAudioSuppressed)
        XCTAssertTrue(secondary.isAudioSuppressed)
        session.stop()
    }

    func testStopRejectsLateReviewSaveCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let primaryURL = directory.appendingPathComponent("Master.mov")
        let secondaryURL = directory.appendingPathComponent("Encode.mov")
        try Data("primary".utf8).write(to: primaryURL)
        try Data("secondary".utf8).write(to: secondaryURL)

        let loader = ControlledCompareMetadataLoader()
        let reviewStore = ControlledCompareReviewStore()
        let primary = PlayerController()
        var primaryItem = PlayerWindowCoordinator.makeMediaItem(for: primaryURL)
        primaryItem.durationSeconds = 10
        primaryItem.metadata = metadata(duration: 10)
        primary.loadMedia(primaryItem)
        let session = makeSession(loader: loader, reviewStore: reviewStore)

        session.loadSecondary(secondaryURL, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: secondaryURL) }
        XCTAssertTrue(requested)
        loader.succeed(secondaryURL, metadata: metadata(duration: 10))
        let reviewLoaded = await waitUntil { session.canEditReviewNotes }
        XCTAssertTrue(reviewLoaded)

        XCTAssertTrue(session.addReviewNote("Pending write", primary: primary))
        await reviewStore.waitUntilApplyStarted()
        XCTAssertEqual(session.reviewNotes.map(\.text), ["Pending write"])
        session.reviewSearchQuery = "missing"
        XCTAssertTrue(session.filteredReviewNotes.isEmpty)
        XCTAssertEqual(session.reviewNotes.count, 1)
        session.reviewSearchQuery = "pending"
        XCTAssertEqual(session.filteredReviewNotes, session.reviewNotes)

        session.stop()
        XCTAssertEqual(session.reviewSearchQuery, "")
        await reviewStore.completeApply()
        await settleMainActorTasks()

        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.reviewNotes.isEmpty)
        XCTAssertNil(session.reviewError)
        primary.teardown()
    }

    func testReviewClassificationAndRangeEditsPreserveCoordinatesAndPersist() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let primaryURL = directory.appendingPathComponent("Master.mov")
        let secondaryURL = directory.appendingPathComponent("Encode.mov")
        try Data("primary".utf8).write(to: primaryURL)
        try Data("secondary".utf8).write(to: secondaryURL)
        let store = CompareReviewSidecarStore()
        let sidecar = CompareReviewSidecarStore.sidecarURL(primaryURL: primaryURL, secondaryURL: secondaryURL)
        let original = CompareReviewNote(
            primaryFrame: 30, primaryTime: 1,
            secondaryFrame: 48, secondaryTime: 2,
            secondaryRateNumerator: 24, text: "Inspect transition"
        )
        try await store.save(
            CompareReviewDocument(primaryURL: primaryURL, secondaryURL: secondaryURL, notes: [original]),
            to: sidecar, revision: 1
        )
        let loader = ControlledCompareMetadataLoader()
        let primary = PlayerController()
        var item = PlayerWindowCoordinator.makeMediaItem(for: primaryURL)
        item.durationSeconds = 10
        item.metadata = metadata(duration: 10)
        primary.loadMedia(item)
        let session = makeSession(loader: loader, reviewStore: store)
        defer { session.stop(); primary.teardown() }
        session.loadSecondary(secondaryURL, alignedWith: primary)
        let requested = await waitUntil { loader.hasRequest(for: secondaryURL) }
        XCTAssertTrue(requested)
        loader.succeed(secondaryURL, metadata: metadata(duration: 10))
        let loaded = await waitUntil { session.canEditReviewNotes }
        XCTAssertTrue(loaded)

        session.updateReviewClassification(id: original.id, severity: .major, category: .picture, status: .inProgress)
        XCTAssertTrue(session.updateReviewRange(id: original.id, endFrame: 90))
        let ranged = try XCTUnwrap(session.reviewNotes.first)
        XCTAssertEqual(ranged.primaryFrame, original.primaryFrame)
        XCTAssertEqual(ranged.primaryTime, original.primaryTime)
        XCTAssertEqual(ranged.secondaryFrame, original.secondaryFrame)
        XCTAssertEqual(ranged.secondaryRateNumerator, original.secondaryRateNumerator)
        XCTAssertEqual(ranged.text, original.text)
        XCTAssertEqual(ranged.severity, .major)
        XCTAssertEqual(ranged.category, .picture)
        XCTAssertEqual(ranged.status, .inProgress)
        XCTAssertEqual(ranged.primaryEndFrame, 90)
        XCTAssertFalse(session.updateReviewRange(id: original.id, endFrame: 29))
        XCTAssertFalse(session.updateReviewRange(id: original.id, endFrame: 300))
        XCTAssertEqual(session.reviewNotes.first, ranged)

        func waitForSavedNote(endFrame: Int64?, text: String) async throws -> CompareReviewNote? {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            while clock.now < deadline {
                let saved = try await store.load(from: sidecar, primaryURL: primaryURL, secondaryURL: secondaryURL)?.notes.first
                if saved?.primaryEndFrame == endFrame, saved?.text == text,
                   saved?.severity == .major, saved?.category == .picture, saved?.status == .inProgress {
                    return saved
                }
                await Task.yield()
            }
            return nil
        }
        let savedRange = try await waitForSavedNote(endFrame: 90, text: original.text)
        XCTAssertNotNil(savedRange)
        XCTAssertTrue(session.updateReviewRange(id: original.id, endFrame: nil))
        session.updateReviewNote(id: original.id, text: "Updated text")
        let savedSingle = try await waitForSavedNote(endFrame: nil, text: "Updated text")
        XCTAssertNotNil(savedSingle)
        XCTAssertEqual(savedSingle?.primaryFrame, original.primaryFrame)
        XCTAssertEqual(savedSingle?.secondaryFrame, original.secondaryFrame)
        XCTAssertNil(session.reviewError)
    }

    private func makeSession(
        loader: ControlledCompareMetadataLoader,
        secondary: PlayerController = PlayerController(),
        reviewStore: any CompareReviewSidecarStoring = CompareReviewSidecarStore.shared
    ) -> CompareSessionController {
        CompareSessionController(
            secondaryController: secondary,
            reviewStore: reviewStore,
            metadataLoader: { url in
                try await loader.load(url)
            }
        )
    }

    private func metadata(duration: TimeInterval) -> MediaMetadata {
        MediaMetadata(
            duration: duration,
            formatName: "mov",
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [],
            subtitleStreams: [],
            chapters: []
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }

    private func settleMainActorTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
private final class ControlledCompareMetadataLoader {
    private var requestedURLs: Set<URL> = []
    private var continuations: [URL: CheckedContinuation<MediaMetadata, Error>] = [:]

    func load(_ url: URL) async throws -> MediaMetadata {
        requestedURLs.insert(url)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[url] = continuation
        }
    }

    func hasRequest(for url: URL) -> Bool {
        requestedURLs.contains(url)
    }

    func succeed(_ url: URL, metadata: MediaMetadata) {
        continuations.removeValue(forKey: url)?.resume(returning: metadata)
    }
}

@MainActor
private final class ControlledCompareProResRAWDetector {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var didStart = false

    func result() async -> Bool {
        didStart = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func resume(returning value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private actor ControlledCompareReviewStore: CompareReviewSidecarStoring {
    private var applyContinuation: CheckedContinuation<CompareReviewDocument, Error>?
    private var pendingDocument: CompareReviewDocument?
    private var didStartApply = false

    func load(
        from url: URL,
        primaryURL: URL,
        secondaryURL: URL
    ) async throws -> CompareReviewDocument? {
        nil
    }

    func apply(
        _ mutation: CompareReviewMutation,
        to url: URL,
        primaryURL: URL,
        secondaryURL: URL
    ) async throws -> CompareReviewDocument {
        let notes: [CompareReviewNote]
        switch mutation {
        case .upsert(let note):
            notes = [note]
        case .delete:
            notes = []
        }
        pendingDocument = CompareReviewDocument(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            notes: notes
        )
        didStartApply = true
        return try await withCheckedThrowingContinuation { continuation in
            applyContinuation = continuation
        }
    }

    func waitUntilApplyStarted() async {
        while !didStartApply {
            await Task.yield()
        }
    }

    func completeApply() {
        guard let pendingDocument else { return }
        applyContinuation?.resume(returning: pendingDocument)
        applyContinuation = nil
        self.pendingDocument = nil
    }
}
