// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareReviewRelinkControllerTests: XCTestCase {
    func testPreviewRequiresConfirmationAndCancellationPreservesReviewFilter() async {
        let fixture = await makeFixture()
        defer { fixture.session.stop(); fixture.primary.teardown() }
        fixture.session.reviewSearchQuery = "Keep this filter"
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let previewed = await waitUntil { fixture.session.reviewRelinkPreview != nil }
        XCTAssertTrue(previewed)
        XCTAssertFalse(fixture.session.canEditReviewNotes)
        XCTAssertFalse(fixture.session.addReviewNote("Blocked", primary: fixture.primary))
        let calls = await fixture.store.relinkCalls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(fixture.session.reviewRelinkPreview?.document.notes.count, 1)
        fixture.session.cancelReviewRelink()
        XCTAssertNil(fixture.session.reviewRelinkPreview)
        XCTAssertTrue(fixture.session.canEditReviewNotes)
        XCTAssertTrue(fixture.session.reviewNotes.isEmpty)
        XCTAssertEqual(fixture.session.reviewSearchQuery, "Keep this filter")
    }

    func testStopRejectsLatePreviewCompletion() async {
        let fixture = await makeFixture(holdPreview: true)
        defer { fixture.primary.teardown() }
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let started = await waitUntilAsync { await fixture.store.previewStarted }
        XCTAssertTrue(started)
        fixture.session.stop()
        await fixture.store.completePreview()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(fixture.session.reviewRelinkPreview)
        XCTAssertFalse(fixture.session.isReviewRelinking)
        XCTAssertTrue(fixture.session.reviewNotes.isEmpty)
    }

    func testChangedPrimaryDuringSuspendedPreviewReleasesBusyState() async {
        let fixture = await makeFixture(holdPreview: true)
        defer { fixture.session.stop(); fixture.primary.teardown() }
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let started = await waitUntilAsync { await fixture.store.previewStarted }
        XCTAssertTrue(started)
        // Reloading the same path still creates a different preparation.
        fixture.primary.loadMedia(PlayerWindowCoordinator.makeMediaItem(
            for: URL(fileURLWithPath: "/tmp/relink-current-A.mov")
        ))
        await fixture.store.completePreview()
        let finished = await waitUntil { !fixture.session.isReviewRelinking }
        XCTAssertTrue(finished)
        XCTAssertNil(fixture.session.reviewRelinkPreview)
        XCTAssertNil(fixture.session.reviewError)
    }

    func testStopRejectsLateConfirmedRelinkCompletion() async {
        let fixture = await makeFixture(holdRelink: true)
        defer { fixture.primary.teardown() }
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let previewed = await waitUntil { fixture.session.reviewRelinkPreview != nil }
        XCTAssertTrue(previewed)
        fixture.session.confirmReviewRelink(primary: fixture.primary)
        let started = await waitUntilAsync { await fixture.store.relinkCalls == 1 }
        XCTAssertTrue(started)
        fixture.session.stop()
        await fixture.store.completeRelink()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(fixture.session.reviewRelinkPreview)
        XCTAssertFalse(fixture.session.isReviewRelinking)
        XCTAssertFalse(fixture.session.isReviewRelinkSaving)
        XCTAssertTrue(fixture.session.reviewNotes.isEmpty)
        XCTAssertNil(fixture.session.reviewError)
    }

    func testChangedPrimaryBeforeConfirmationDoesNotWrite() async {
        let fixture = await makeFixture()
        defer { fixture.session.stop(); fixture.primary.teardown() }
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let previewed = await waitUntil { fixture.session.reviewRelinkPreview != nil }
        XCTAssertTrue(previewed)
        fixture.primary.loadMedia(PlayerWindowCoordinator.makeMediaItem(
            for: URL(fileURLWithPath: "/tmp/relink-replacement-A.mov")
        ))
        fixture.session.confirmReviewRelink(primary: fixture.primary)
        let calls = await fixture.store.relinkCalls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(fixture.session.reviewRelinkPreview)
        XCTAssertFalse(fixture.session.isReviewRelinking)
    }

    func testChangedSecondaryBeforeConfirmationDoesNotWrite() async {
        let fixture = await makeFixture()
        defer { fixture.session.stop(); fixture.primary.teardown() }
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let previewed = await waitUntil { fixture.session.reviewRelinkPreview != nil }
        XCTAssertTrue(previewed)
        fixture.session.loadSecondary(
            URL(fileURLWithPath: "/tmp/relink-replacement-B.mov"), alignedWith: fixture.primary
        )
        fixture.session.confirmReviewRelink(primary: fixture.primary)
        let calls = await fixture.store.relinkCalls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(fixture.session.reviewRelinkPreview)
    }

    func testConfirmedRelinkAdoptsNotesAndRetainsFilter() async {
        let fixture = await makeFixture()
        defer { fixture.session.stop(); fixture.primary.teardown() }
        fixture.session.reviewSearchQuery = "Existing filter"
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let previewed = await waitUntil { fixture.session.reviewRelinkPreview != nil }
        XCTAssertTrue(previewed)
        fixture.session.confirmReviewRelink(primary: fixture.primary)
        let finished = await waitUntil { !fixture.session.isReviewRelinking }
        XCTAssertTrue(finished)
        XCTAssertEqual(fixture.session.reviewNotes.map(\.text), ["Original note"])
        XCTAssertEqual(fixture.session.reviewSearchQuery, "Existing filter")
        XCTAssertNil(fixture.session.reviewError)
        XCTAssertTrue(fixture.session.canEditReviewNotes)
        let calls = await fixture.store.relinkCalls
        XCTAssertEqual(calls, 1)
    }

    func testConflictPreservesEmptyReviewAndFilter() async {
        let fixture = await makeFixture(failRelink: true)
        defer { fixture.session.stop(); fixture.primary.teardown() }
        fixture.session.reviewSearchQuery = "Existing filter"
        fixture.session.previewReviewRelink(from: sourceURL, primary: fixture.primary)
        let previewed = await waitUntil { fixture.session.reviewRelinkPreview != nil }
        XCTAssertTrue(previewed)
        fixture.session.confirmReviewRelink(primary: fixture.primary)
        let finished = await waitUntil { !fixture.session.isReviewRelinking }
        XCTAssertTrue(finished)
        XCTAssertTrue(fixture.session.reviewNotes.isEmpty)
        XCTAssertEqual(fixture.session.reviewSearchQuery, "Existing filter")
        XCTAssertNotNil(fixture.session.reviewError)
        XCTAssertEqual(fixture.session.reviewRelinkFailure, fixture.session.reviewError)
        fixture.session.dismissReviewRelinkFailure()
        XCTAssertNil(fixture.session.reviewRelinkFailure)
        XCTAssertNotNil(fixture.session.reviewError)
    }

    private var sourceURL: URL { URL(fileURLWithPath: "/tmp/old-review.json") }

    private func makeFixture(holdPreview: Bool = false, failRelink: Bool = false, holdRelink: Bool = false) async -> (
        session: CompareSessionController, primary: PlayerController, store: RelinkControllerStore
    ) {
        let store = RelinkControllerStore(holdPreview: holdPreview, failRelink: failRelink, holdRelink: holdRelink)
        let primary = PlayerController()
        primary.loadMedia(PlayerWindowCoordinator.makeMediaItem(
            for: URL(fileURLWithPath: "/tmp/relink-current-A.mov")
        ))
        let session = CompareSessionController(reviewStore: store, metadataLoader: { _ in
            MediaMetadata(
                duration: 10, formatName: "mov", containerLongName: nil,
                sizeBytes: nil, bitRate: nil, timecode: nil, comment: nil,
                encoder: nil, frameCount: nil, videoStreams: [], audioStreams: [],
                subtitleStreams: [], chapters: []
            )
        })
        session.loadSecondary(URL(fileURLWithPath: "/tmp/relink-current-B.mov"), alignedWith: primary)
        let loaded = await waitUntil { session.canRelinkReviewNotes }
        XCTAssertTrue(loaded)
        return (session, primary, store)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }

    private func waitUntilAsync(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }
}

private actor RelinkControllerStore: CompareReviewSidecarStoring {
    private let holdPreview: Bool
    private let failRelink: Bool
    private let holdRelink: Bool
    private var relinkContinuation: CheckedContinuation<CompareReviewDocument, Error>?
    private var pendingRelink: CompareReviewDocument?
    private var continuation: CheckedContinuation<CompareReviewDocument, Error>?
    private(set) var previewStarted = false
    private(set) var relinkCalls = 0

    init(holdPreview: Bool, failRelink: Bool, holdRelink: Bool) {
        self.holdRelink = holdRelink
        self.holdPreview = holdPreview
        self.failRelink = failRelink
    }

    private var document: CompareReviewDocument {
        CompareReviewDocument(
            primaryURL: URL(fileURLWithPath: "/tmp/relink-old-A.mov"),
            secondaryURL: URL(fileURLWithPath: "/tmp/relink-old-B.mov"),
            notes: [CompareReviewNote(primaryFrame: 0, primaryTime: 0,
                secondaryFrame: 0, secondaryTime: 0, primaryRateNumerator: 24,
                text: "Original note")]
        )
    }

    func previewRelink(from url: URL) async throws -> CompareReviewDocument {
        previewStarted = true
        if holdPreview {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return document
    }

    func completePreview() {
        continuation?.resume(returning: document)
        continuation = nil
    }

    func relink(from url: URL, to destinationURL: URL, primaryURL: URL,
                secondaryURL: URL, expectedDocument: CompareReviewDocument) async throws -> CompareReviewDocument {
        relinkCalls += 1
        if failRelink { throw CompareReviewSidecarError.relinkDestinationExists }
        let result = CompareReviewDocument(primaryURL: primaryURL, secondaryURL: secondaryURL,
                                           notes: expectedDocument.notes)
        if holdRelink {
            pendingRelink = result
            return try await withCheckedThrowingContinuation { relinkContinuation = $0 }
        }
        return result
    }

    func completeRelink() {
        guard let pendingRelink else { return }
        relinkContinuation?.resume(returning: pendingRelink)
        relinkContinuation = nil
        self.pendingRelink = nil
    }

    func load(from url: URL, primaryURL: URL, secondaryURL: URL) async throws -> CompareReviewDocument? { nil }

    func apply(_ mutation: CompareReviewMutation, to url: URL, primaryURL: URL,
               secondaryURL: URL) async throws -> CompareReviewDocument {
        throw CompareReviewSidecarError.relinkUnavailable
    }
}
