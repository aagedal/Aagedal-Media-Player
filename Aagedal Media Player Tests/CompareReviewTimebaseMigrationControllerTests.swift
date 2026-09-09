// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareReviewTimebaseMigrationControllerTests: XCTestCase {
    func testPreviewDoesNotWriteAndCancelRetainsOriginalAndFilter() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let (session, primary) = await makeSession(f)
        defer { session.stop(); primary.teardown() }
        session.reviewSearchQuery = "Keep filter"
        session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
        await assertEventually { session.reviewRelinkPreview?.migration != nil }
        XCTAssertFalse(session.canEditReviewNotes)
        XCTAssertFalse(session.addReviewNote("Blocked", primary: primary))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
        session.cancelReviewRelink()
        XCTAssertTrue(session.canEditReviewNotes)
        XCTAssertEqual(session.reviewNotes, f.document.notes)
        XCTAssertEqual(session.reviewSidecarURL, f.source)
        XCTAssertEqual(session.reviewSearchQuery, "Keep filter")
    }

    func testPreviewAcceptsPersistedFractionalEditTimestamp() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        var edited = f.document
        edited.notes[0].updatedAt = Date(timeIntervalSinceReferenceDate: 810_724_000 + pow(2, -23))
        try f.write(edited)
        let persisted = try await CompareReviewSidecarStore().previewRelink(from: f.source)
        XCTAssertNotEqual(edited.notes[0].updatedAt, persisted.notes[0].updatedAt)
        let store = DelayedMigrationControllerStore(document: edited, holdPreview: false, previewDocument: persisted)
        let (session, primary) = await makeSession(f, store: store)
        defer { session.stop(); primary.teardown() }
        session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
        await assertEventually { session.reviewRelinkPreview?.migration != nil || session.reviewRelinkFailure != nil }
        XCTAssertNotNil(session.reviewRelinkPreview?.migration)
        XCTAssertNil(session.reviewRelinkFailure)
        var changed = edited.notes
        changed[0].text = "Actual unsaved change"
        XCTAssertFalse(try CompareReviewTimebaseMigration.hasSameSavedNotes(changed, persisted.notes))
    }

    func testConfirmedCopyEnablesEditorExportsAndSubsequentEditsUseCopy() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let (session, primary) = await makeSession(f)
        defer { session.stop(); primary.teardown() }
        let bytes = try Data(contentsOf: f.source)
        let oldSnapshot = CompareReviewReportSnapshot(primaryItem: f.item(url: f.primary),
            secondaryItem: f.item(url: f.secondary), alignmentMode: .relative, notes: session.reviewNotes)
        XCTAssertThrowsError(try CompareReviewReportExporter.finalCutProXML(snapshot: oldSnapshot))
        session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
        await assertEventually { session.reviewRelinkPreview != nil }
        session.confirmReviewRelink(primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNil(session.reviewError)
        XCTAssertEqual(session.reviewSidecarURL, f.destination)
        XCTAssertEqual(session.reviewNotes[0].primaryRateNumerator, 30_000)
        let snapshot = CompareReviewReportSnapshot(primaryItem: f.item(url: f.primary),
            secondaryItem: f.item(url: f.secondary), alignmentMode: .relative, notes: session.reviewNotes)
        for format in [CompareReviewReportFormat.resolveMarkersEDL, .finalCutProXML, .avidMarkersText] {
            XCTAssertNoThrow(try CompareReviewReportExporter.data(for: format, snapshot: snapshot))
        }
        session.updateReviewNote(id: session.reviewNotes[0].id, text: "Edit migrated copy")
        await assertEventually { session.canManageReviewCopy }
        let saved = try await CompareReviewSidecarStore().load(
            from: f.destination, primaryURL: f.primary, secondaryURL: f.secondary)
        XCTAssertEqual(saved?.notes[0].text, "Edit migrated copy")
        XCTAssertEqual(try Data(contentsOf: f.source), bytes)
    }

    func testReopeningCopyIsExplicitAndPreservesSourceIdentityChecks() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let corrected = try await CompareReviewSidecarStore().migrateTimebases(
            from: f.source, to: f.destination, expectedMigration: f.proposal())
        let (session, primary) = await makeSession(f)
        defer { session.stop(); primary.teardown() }
        XCTAssertEqual(session.reviewNotes, f.document.notes)
        session.reviewSearchQuery = "Keep filter"
        session.openReviewCopy(from: f.destination, primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertEqual(session.reviewNotes, corrected.notes)
        XCTAssertEqual(session.reviewSidecarURL, f.destination)
        XCTAssertEqual(session.reviewSearchQuery, "Keep filter")
        let other = try ReviewTimebaseMigrationFixture()
        defer { other.remove() }
        session.openReviewCopy(from: other.source, primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNotNil(session.reviewRelinkFailure)
        XCTAssertEqual(session.reviewNotes, corrected.notes)
        XCTAssertEqual(session.reviewSidecarURL, f.destination)
    }

    func testChangedMetadataOrPrimaryPreparationRejectsConfirmation() async throws {
        for changePreparation in [false, true] {
            let f = try ReviewTimebaseMigrationFixture()
            defer { f.remove() }
            let (session, primary) = await makeSession(f)
            defer { session.stop(); primary.teardown() }
            session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
            await assertEventually { session.reviewRelinkPreview != nil }
            if changePreparation {
                primary.loadMedia(f.item(url: f.primary))
            } else {
                var changed = f.item(url: f.primary)
                changed.durationSeconds = 30
                primary.updateMetadata(changed)
            }
            session.confirmReviewRelink(primary: primary)
            XCTAssertFalse(session.isReviewRelinking)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
            XCTAssertEqual(session.reviewNotes, f.document.notes)
            XCTAssertEqual(session.reviewSidecarURL, f.source)
        }
    }

    func testSourceReplacementAfterPreviewPreservesOriginalActiveReview() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let (session, primary) = await makeSession(f)
        defer { session.stop(); primary.teardown() }
        session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
        await assertEventually { session.reviewRelinkPreview != nil }
        try Data("Replacement B contents".utf8).write(to: f.secondary, options: .atomic)
        session.confirmReviewRelink(primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNotNil(session.reviewRelinkFailure)
        XCTAssertEqual(session.reviewNotes, f.document.notes)
        XCTAssertEqual(session.reviewSidecarURL, f.source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destination.path))
    }

    func testStopRejectsLateMigrationPreviewAndSaveCompletions() async throws {
        for holdPreview in [false, true] {
            let f = try ReviewTimebaseMigrationFixture()
            defer { f.remove() }
            let store = DelayedMigrationControllerStore(document: f.document, holdPreview: holdPreview)
            let (session, primary) = await makeSession(f, store: store)
            defer { session.stop(); primary.teardown() }
            session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
            if holdPreview {
                await assertEventuallyAsync { await store.previewStarted }
            } else {
                await assertEventually { session.reviewRelinkPreview != nil }
                session.confirmReviewRelink(primary: primary)
                await assertEventuallyAsync { await store.saveStarted }
            }
            session.stop()
            await store.complete()
            for _ in 0..<30 { await Task.yield() }
            XCTAssertFalse(session.isReviewRelinking)
            XCTAssertNil(session.reviewRelinkPreview)
            XCTAssertNil(session.reviewSidecarURL)
            XCTAssertTrue(session.reviewNotes.isEmpty)
            XCTAssertNil(session.reviewError)
        }
    }

    private func makeSession(_ f: ReviewTimebaseMigrationFixture,
                             store: any CompareReviewSidecarStoring = CompareReviewSidecarStore()) async -> (CompareSessionController, PlayerController) {
        let primary = PlayerController()
        primary.loadMedia(f.item(url: f.primary))
        let metadata = f.item(url: f.secondary).metadata!
        let session = CompareSessionController(reviewStore: store, metadataLoader: { _ in metadata })
        session.loadSecondary(f.secondary, alignedWith: primary)
        await assertEventually { session.canManageReviewCopy && !session.reviewNotes.isEmpty }
        return (session, primary)
    }

    private func assertEventually(
        file: StaticString = #filePath, line: UInt = #line, _ condition: @MainActor () -> Bool
    ) async {
        let result = await waitUntil(condition)
        XCTAssertTrue(result, file: file, line: line)
    }

    private func assertEventuallyAsync(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool
    ) async {
        let result = await waitUntilAsync(condition)
        XCTAssertTrue(result, file: file, line: line)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }

    private func waitUntilAsync(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }
}

private actor DelayedMigrationControllerStore: CompareReviewSidecarStoring {
    let document: CompareReviewDocument
    let holdPreview: Bool
    let previewDocument: CompareReviewDocument?
    private(set) var previewStarted = false
    private(set) var saveStarted = false
    private var result: CompareReviewDocument?
    private var continuation: CheckedContinuation<CompareReviewDocument, Error>?

    init(document: CompareReviewDocument, holdPreview: Bool, previewDocument: CompareReviewDocument? = nil) {
        self.document = document
        self.holdPreview = holdPreview
        self.previewDocument = previewDocument
    }

    func previewRelink(from url: URL) async throws -> CompareReviewDocument {
        previewStarted = true
        guard holdPreview else { return previewDocument ?? document }
        result = previewDocument ?? document
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func migrateTimebases(from url: URL, to destinationURL: URL,
                          expectedMigration: CompareReviewTimebaseMigration) async throws -> CompareReviewDocument {
        saveStarted = true
        result = expectedMigration.migrated
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func complete() {
        guard let result else { return }
        continuation?.resume(returning: result)
        continuation = nil
    }

    func load(from url: URL, primaryURL: URL, secondaryURL: URL) async throws -> CompareReviewDocument? { document }

    func apply(_ mutation: CompareReviewMutation, to url: URL, primaryURL: URL,
               secondaryURL: URL) async throws -> CompareReviewDocument {
        throw CompareReviewTimebaseMigrationError.unavailable
    }
}
