// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class CompareReviewTimebaseMigrationControllerTests: XCTestCase {
    func testStopPreventsEarlierQueuedReviewWritesFromStarting() async throws {
        try await verifyQueuedWritesAreInvalidated(replaceComparison: false)
    }

    func testReplacementPreventsEarlierQueuedReviewWritesFromStarting() async throws {
        try await verifyQueuedWritesAreInvalidated(replaceComparison: true)
    }

    private func verifyQueuedWritesAreInvalidated(replaceComparison: Bool) async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let store = DelayedMigrationControllerStore(document: f.document,
            holdPreview: false, holdNoteSave: true, holdOnlyFirstNoteSave: true)
        let (session, primary) = await makeSession(f, store: store)
        defer { session.stop(); primary.teardown() }

        let noteID = f.document.notes[0].id
        session.updateReviewNote(id: noteID, text: "Already started")
        await assertEventuallyAsync { await store.noteSaveCount == 1 }
        session.updateReviewNote(id: noteID, text: "Queued middle write")
        session.updateReviewNote(id: noteID, text: "Queued tail write")
        var actionStarted = false
        let action = session.performReviewActionAfterSaving(primary: primary) { _, _ in
            actionStarted = true
        }
        if replaceComparison {
            session.loadSecondary(f.secondary, alignedWith: primary)
            await assertEventually { session.canManageReviewCopy && !session.reviewNotes.isEmpty }
        } else {
            session.stop()
        }
        let currentNotes = session.reviewNotes
        await store.complete()
        // The action awaits the tail, which in turn awaits every predecessor.
        await action.value

        let saveCount = await store.noteSaveCount
        XCTAssertEqual(saveCount, 1, "Invalidating a comparison cancels every queued write, including unretained middle tasks")
        let persisted = try await store.load(from: f.source,
            primaryURL: f.primary, secondaryURL: f.secondary)
        XCTAssertEqual(persisted?.notes[0].text, "Already started")
        XCTAssertFalse(actionStarted)
        XCTAssertFalse(session.isReviewActionPending)
        XCTAssertFalse(session.hasUnsavedReviewChanges)
        XCTAssertEqual(session.reviewNotes, currentNotes)
    }

    func testReviewActionWaitsForDraftSaveAndRejectsFailureOrChangedPrimary() async throws {
        for outcome in ["saved", "failed", "reloaded"] {
            let f = try ReviewTimebaseMigrationFixture()
            defer { f.remove() }
            let store = DelayedMigrationControllerStore(
                document: f.document, holdPreview: false, holdNoteSave: true
            )
            let (session, primary) = await makeSession(f, store: store)
            defer { session.stop(); primary.teardown() }
            session.updateReviewNote(id: f.document.notes[0].id, text: "Pending field draft")
            var actionStarted = false
            let action = session.performReviewActionAfterSaving(primary: primary) { session, _ in
                actionStarted = true
                XCTAssertEqual(session.reviewNotes[0].text, "Pending field draft")
                XCTAssertTrue(session.canManageReviewCopy)
            }
            await assertEventuallyAsync { await store.noteSaveStarted }
            XCTAssertFalse(actionStarted)
            XCTAssertTrue(session.isReviewActionPending)
            XCTAssertFalse(session.canEditReviewNotes)
            session.updateReviewNote(id: f.document.notes[0].id, text: "Must not replace the flushed draft")
            XCTAssertEqual(session.reviewNotes[0].text, "Pending field draft")
            if outcome == "reloaded" { primary.loadMedia(f.item(url: f.primary)) }
            await store.complete(error: outcome == "failed"
                ? NSError(domain: "ReviewSaveTest", code: 1) : nil)
            await action.value
            XCTAssertFalse(session.isReviewActionPending)
            XCTAssertEqual(actionStarted, outcome == "saved")
            XCTAssertEqual(session.reviewNotes[0].text, "Pending field draft")
            if outcome == "failed" { XCTAssertNotNil(session.reviewError) }
        }
    }

    func testDismissedSaveFailureIsRetriedBeforeOpeningAnotherReview() async throws {
        for deleteNote in [false, true] {
            let f = try ReviewTimebaseMigrationFixture()
            defer { f.remove() }
            let store = DelayedMigrationControllerStore(document: f.document, holdPreview: false, holdNoteSave: true)
            let (session, primary) = await makeSession(f, store: store)
            defer { session.stop(); primary.teardown() }
            if deleteNote { session.deleteReviewNote(id: f.document.notes[0].id) }
            else { session.updateReviewNote(id: f.document.notes[0].id, text: "Retain failed edit") }
            var actionStarted = false
            let first = session.performReviewActionAfterSaving(primary: primary) { _, _ in actionStarted = true }
            await assertEventuallyAsync { await store.noteSaveCount == 1 }
            await store.complete(error: NSError(domain: "ReviewSaveTest", code: 1))
            await first.value
            XCTAssertFalse(actionStarted)
            session.dismissReviewError()

            let retry = session.performReviewActionAfterSaving(primary: primary) { _, _ in actionStarted = true }
            await assertEventuallyAsync { await store.noteSaveCount == 2 }
            XCTAssertFalse(actionStarted)
            XCTAssertTrue(session.isReviewActionPending)
            await store.complete()
            await retry.value
            XCTAssertTrue(actionStarted)
            let persisted = try await store.load(from: f.source, primaryURL: f.primary, secondaryURL: f.secondary)
            if deleteNote { XCTAssertTrue(persisted?.notes.isEmpty == true) }
            else { XCTAssertEqual(persisted?.notes[0].text, "Retain failed edit") }
        }
    }

    func testUnrelatedSuccessfulSaveRetainsEarlierFailedEditUntilRetry() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        var document = f.document
        let other = CompareReviewNote(primaryFrame: 10, primaryTime: 1, secondaryFrame: 10,
            secondaryTime: 1, text: "Other finding")
        document.notes.append(other)
        let store = DelayedMigrationControllerStore(document: document, holdPreview: false, holdNoteSave: true)
        let (session, primary) = await makeSession(f, store: store)
        defer { session.stop(); primary.teardown() }
        session.updateReviewNote(id: f.document.notes[0].id, text: "Failed finding edit")
        await assertEventuallyAsync { await store.noteSaveCount == 1 }
        await store.complete(error: NSError(domain: "ReviewSaveTest", code: 1))
        await assertEventually { session.canManageReviewCopy }
        session.updateReviewNote(id: other.id, text: "Successful other edit")
        await assertEventuallyAsync { await store.noteSaveCount == 2 }
        await store.complete()
        await assertEventually { session.canManageReviewCopy }
        XCTAssertEqual(session.reviewNotes.first { $0.id == f.document.notes[0].id }?.text, "Failed finding edit")
        XCTAssertEqual(session.reviewNotes.first { $0.id == other.id }?.text, "Successful other edit")

        var actionStarted = false
        let retry = session.performReviewActionAfterSaving(primary: primary) { _, _ in actionStarted = true }
        await assertEventuallyAsync { await store.noteSaveCount == 3 }
        XCTAssertFalse(actionStarted)
        await store.complete()
        await retry.value
        XCTAssertTrue(actionStarted)
        let persisted = try await store.load(from: f.source, primaryURL: f.primary, secondaryURL: f.secondary)
        XCTAssertEqual(persisted?.notes.first { $0.id == f.document.notes[0].id }?.text, "Failed finding edit")
        XCTAssertEqual(persisted?.notes.first { $0.id == other.id }?.text, "Successful other edit")
    }

    func testReviewActionRetriesEarlierFailureBehindNewDraftSaveOnlyOnce() async throws {
        for retryFails in [false, true] {
            let f = try ReviewTimebaseMigrationFixture()
            defer { f.remove() }
            var document = f.document
            let other = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
                secondaryFrame: 10, secondaryTime: 1, text: "Other finding")
            document.notes.append(other)
            let store = DelayedMigrationControllerStore(document: document, holdPreview: false, holdNoteSave: true)
            let (session, primary) = await makeSession(f, store: store)
            defer { session.stop(); primary.teardown() }
            session.updateReviewNote(id: document.notes[0].id, text: "Retained failed edit")
            await assertEventuallyAsync { await store.noteSaveCount == 1 }
            await store.complete(error: CocoaError(.fileWriteNoPermission))
            await assertEventually { session.canManageReviewCopy }

            // Match the view: flushing another visible text draft starts a
            // write immediately before the Retry Save/menu action is queued.
            session.updateReviewNote(id: other.id, text: "New visible draft")
            var actionStarted = false
            let action = session.performReviewActionAfterSaving(primary: primary) { _, _ in
                actionStarted = true
            }
            await assertEventuallyAsync { await store.noteSaveCount == 2 }
            XCTAssertFalse(actionStarted)
            await store.complete()
            await assertEventuallyAsync { await store.noteSaveCount == 3 }
            XCTAssertFalse(actionStarted)
            XCTAssertTrue(session.isReviewActionPending)
            await store.complete(error: retryFails ? CocoaError(.fileWriteNoPermission) : nil)
            await action.value
            XCTAssertFalse(session.isReviewActionPending)
            XCTAssertEqual(actionStarted, !retryFails)
            XCTAssertEqual(session.hasUnsavedReviewChanges, retryFails)
            let saveCount = await store.noteSaveCount
            XCTAssertEqual(saveCount, 3, "A persistent error must not start an automatic retry loop")
            let persisted = try await store.load(from: f.source, primaryURL: f.primary, secondaryURL: f.secondary)
            XCTAssertEqual(persisted?.notes.first { $0.id == other.id }?.text, "New visible draft")
            XCTAssertEqual(persisted?.notes.first { $0.id == document.notes[0].id }?.text,
                retryFails ? document.notes[0].text : "Retained failed edit")
            XCTAssertEqual(session.reviewNotes.first { $0.id == document.notes[0].id }?.text, "Retained failed edit")
        }
    }

    func testPermissionAndDiskFullFailuresCanBeRetriedWithoutReloadingUnsavedChanges() async throws {
        for failure in [CocoaError.Code.fileWriteNoPermission, .fileWriteOutOfSpace] {
            for deleteNote in [false, true] {
                let f = try ReviewTimebaseMigrationFixture()
                defer { f.remove() }
                let store = DelayedMigrationControllerStore(document: f.document, holdPreview: false, holdNoteSave: true)
                let (session, primary) = await makeSession(f, store: store)
                defer { session.stop(); primary.teardown() }
                if deleteNote { session.deleteReviewNote(id: f.document.notes[0].id) }
                else { session.updateReviewNote(id: f.document.notes[0].id, text: "Unsaved edit") }
                await assertEventuallyAsync { await store.noteSaveCount == 1 }
                let error = CocoaError(failure)
                await store.complete(error: error)
                await assertEventually { session.canManageReviewCopy }
                XCTAssertTrue(session.hasUnsavedReviewChanges)
                XCTAssertTrue(session.reviewError?.contains(error.localizedDescription) == true)
                let optimisticNotes = session.reviewNotes
                session.retryReviewLoad(primary: primary)
                XCTAssertFalse(session.isReviewLoading)
                XCTAssertEqual(session.reviewNotes, optimisticNotes)
                XCTAssertTrue(session.hasUnsavedReviewChanges)

                session.retryReviewSave(primary: primary)
                await assertEventuallyAsync { await store.noteSaveCount == 2 }
                session.retryReviewSave(primary: primary)
                XCTAssertTrue(session.isReviewActionPending)
                await store.complete(error: error)
                await assertEventually { !session.isReviewActionPending }
                XCTAssertTrue(session.hasUnsavedReviewChanges)
                XCTAssertEqual(session.reviewNotes, optimisticNotes)

                session.retryReviewSave(primary: primary)
                await assertEventuallyAsync { await store.noteSaveCount == 3 }
                await store.complete()
                await assertEventually { !session.isReviewActionPending }
                XCTAssertFalse(session.hasUnsavedReviewChanges)
                XCTAssertNil(session.reviewError)
                XCTAssertTrue(session.canEditReviewNotes)
                let persisted = try await store.load(from: f.source, primaryURL: f.primary, secondaryURL: f.secondary)
                XCTAssertEqual(persisted?.notes, optimisticNotes)
            }
        }
    }

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

    func testMigrationPublicationFailureCanBeRetriedWithoutLosingTheActiveReview() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let (session, primary) = await makeSession(f)
        defer { session.stop(); primary.teardown() }
        let originalBytes = try Data(contentsOf: f.source)
        let existingBytes = Data("An existing destination must survive".utf8)
        try existingBytes.write(to: f.destination)
        session.reviewSearchQuery = "Keep filter"

        session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
        await assertEventually { session.reviewRelinkPreview != nil }
        session.confirmReviewRelink(primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNotNil(session.reviewRelinkFailure)
        XCTAssertTrue(session.canEditReviewNotes)
        XCTAssertFalse(session.isReviewRelinkSaving)
        XCTAssertNil(session.reviewRelinkPreview)
        XCTAssertEqual(session.reviewNotes, f.document.notes)
        XCTAssertEqual(session.reviewSidecarURL, f.source)
        XCTAssertEqual(try Data(contentsOf: f.destination), existingBytes)

        session.dismissReviewRelinkFailure()
        let retryURL = f.directory.appendingPathComponent("retry-migrated.json")
        session.previewReviewTimebaseMigration(primary: primary, destinationURL: retryURL)
        await assertEventually { session.reviewRelinkPreview != nil }
        session.confirmReviewRelink(primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNil(session.reviewRelinkFailure)
        XCTAssertNil(session.reviewError)
        XCTAssertEqual(session.reviewSidecarURL, retryURL)
        XCTAssertEqual(session.reviewSearchQuery, "Keep filter")
        XCTAssertEqual(session.reviewNotes.map(\.id), f.document.notes.map(\.id))
        XCTAssertEqual(try Data(contentsOf: f.source), originalBytes)
        XCTAssertEqual(try Data(contentsOf: f.destination), existingBytes)
    }

    func testFailedCopyOpeningRetainsEditableReviewAndCanBeRetried() async throws {
        let f = try ReviewTimebaseMigrationFixture()
        defer { f.remove() }
        let (session, primary) = await makeSession(f)
        defer { session.stop(); primary.teardown() }
        try Data("Corrupt review".utf8).write(to: f.destination)
        session.openReviewCopy(from: f.destination, primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNotNil(session.reviewRelinkFailure)
        XCTAssertTrue(session.canEditReviewNotes)
        XCTAssertEqual(session.reviewSidecarURL, f.source)
        XCTAssertEqual(session.reviewNotes, f.document.notes)

        session.dismissReviewRelinkFailure()
        session.updateReviewNote(id: f.document.notes[0].id, text: "Edit after failed opening")
        await assertEventually { session.canManageReviewCopy }
        let editedBytes = try Data(contentsOf: f.source)
        try editedBytes.write(to: f.destination, options: .atomic)
        session.openReviewCopy(from: f.destination, primary: primary)
        await assertEventually { !session.isReviewRelinking }
        XCTAssertNil(session.reviewRelinkFailure)
        XCTAssertNil(session.reviewError)
        XCTAssertEqual(session.reviewSidecarURL, f.destination)
        XCTAssertEqual(session.reviewNotes[0].text, "Edit after failed opening")
        session.updateReviewNote(id: f.document.notes[0].id, text: "Edit reopened copy")
        await assertEventually { session.canManageReviewCopy }
        let saved = try await CompareReviewSidecarStore().load(
            from: f.destination, primaryURL: f.primary, secondaryURL: f.secondary)
        XCTAssertEqual(saved?.notes[0].text, "Edit reopened copy")
        XCTAssertEqual(try Data(contentsOf: f.source), editedBytes)
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

    func testMetadataChangeDuringMigrationSaveDoesNotActivateTheCopy() async throws {
        for changePrimary in [false, true] {
            let f = try ReviewTimebaseMigrationFixture()
            defer { f.remove() }
            let store = DelayedMigrationControllerStore(document: f.document, holdPreview: false)
            let (session, primary) = await makeSession(f, store: store)
            defer { session.stop(); primary.teardown() }
            session.previewReviewTimebaseMigration(primary: primary, destinationURL: f.destination)
            await assertEventually { session.reviewRelinkPreview != nil }
            session.confirmReviewRelink(primary: primary)
            await assertEventuallyAsync { await store.saveStarted }

            let controller = changePrimary ? primary : session.secondaryController
            var changed = f.item(url: changePrimary ? f.primary : f.secondary)
            changed.durationSeconds = 30
            controller.updateMetadata(changed)
            await store.complete()
            await assertEventually { !session.isReviewRelinking }

            XCTAssertEqual(session.reviewNotes, f.document.notes)
            XCTAssertEqual(session.reviewSidecarURL, f.source)
            XCTAssertTrue(session.canEditReviewNotes)
            XCTAssertTrue(session.reviewRelinkFailure?.contains("Media timing changed while saving") == true)
            XCTAssertTrue(session.reviewRelinkFailure?.contains(f.destination.path) == true)
        }
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
    var document: CompareReviewDocument
    let holdPreview: Bool
    let holdNoteSave: Bool
    let holdOnlyFirstNoteSave: Bool
    let previewDocument: CompareReviewDocument?
    private(set) var previewStarted = false
    private(set) var saveStarted = false
    private(set) var noteSaveStarted = false
    private(set) var noteSaveCount = 0
    private var result: CompareReviewDocument?
    private var continuation: CheckedContinuation<CompareReviewDocument, Error>?

    init(document: CompareReviewDocument, holdPreview: Bool, previewDocument: CompareReviewDocument? = nil,
         holdNoteSave: Bool = false, holdOnlyFirstNoteSave: Bool = false) {
        self.document = document
        self.holdPreview = holdPreview
        self.holdNoteSave = holdNoteSave
        self.holdOnlyFirstNoteSave = holdOnlyFirstNoteSave
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

    func complete(error: Error? = nil) {
        guard let result else { return }
        if let error { continuation?.resume(throwing: error) }
        else { document = result; continuation?.resume(returning: result) }
        continuation = nil
    }

    func load(from url: URL, primaryURL: URL, secondaryURL: URL) async throws -> CompareReviewDocument? { document }

    func apply(_ mutation: CompareReviewMutation, to url: URL, primaryURL: URL,
               secondaryURL: URL) async throws -> CompareReviewDocument {
        guard holdNoteSave else {
            throw CompareReviewTimebaseMigrationError.unavailable
        }
        noteSaveStarted = true
        noteSaveCount += 1
        var updated = document
        switch mutation {
        case .upsert(let note):
            updated.notes.removeAll { $0.id == note.id }
            updated.notes.append(note)
        case .delete(let id): updated.notes.removeAll { $0.id == id }
        }
        if holdOnlyFirstNoteSave && noteSaveCount > 1 {
            document = updated
            return updated
        }
        result = updated
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
