// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareReviewTextCommitTests: XCTestCase {
    @MainActor
    func testCurrentRangeActionReplacesInvalidDraftEvenWhenSavedEndpointIsUnchanged() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Finding", primaryEndFrame: 20)
        var drafts = CompareReviewDraftState()
        drafts.rangeDrafts[note.id] = "not a frame"
        drafts.blockAction(noteID: note.id, field: .rangeEnd,
            error: "Enter a whole-number end frame", notice: "Correct this range")
        XCTAssertTrue(drafts.hasPendingEdits(in: [note]))

        // The controller succeeds without changing primaryEndFrame when the
        // current frame already equals the saved end. No onChange will fire.
        XCTAssertTrue(drafts.applyCurrentRangeEnd(noteID: note.id) { note.primaryEndFrame })

        XCTAssertEqual(drafts.rangeDrafts[note.id], "20")
        XCTAssertFalse(drafts.hasPendingEdits(in: [note]))
        XCTAssertNil(drafts.rangeActionErrors[note.id])
        XCTAssertNil(drafts.rangeActionNotice)
        XCTAssertNil(drafts.correctionRequest)
    }

    @MainActor
    func testCurrentRangeActionRetainsFailedInputAndUnrelatedTextCorrection() {
        let noteID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.rangeDrafts[noteID] = "invalid end"
        drafts.blockAction(noteID: noteID, field: .text,
            error: "Enter note text", notice: "Correct this note")
        let correction = drafts.correctionRequest
        drafts.rangeActionErrors[noteID] = "Invalid range"

        XCTAssertFalse(drafts.applyCurrentRangeEnd(noteID: noteID) { nil })
        XCTAssertEqual(drafts.rangeDrafts[noteID], "invalid end")
        XCTAssertEqual(drafts.rangeActionErrors[noteID], "Invalid range")
        XCTAssertEqual(drafts.correctionRequest, correction)

        XCTAssertTrue(drafts.applyCurrentRangeEnd(noteID: noteID) { 20 })
        XCTAssertEqual(drafts.rangeDrafts[noteID], "20")
        XCTAssertNil(drafts.rangeActionErrors[noteID])
        XCTAssertEqual(drafts.noteActionErrors[noteID], "Enter note text")
        XCTAssertEqual(drafts.rangeActionNotice, "Correct this note")
        XCTAssertEqual(drafts.correctionRequest, correction)
    }

    @MainActor
    func testRepeatedBlockedActionRevealsSameCorrectionWithoutDiscardingDrafts() throws {
        let noteID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.noteDrafts[noteID] = "  "
        drafts.rangeDrafts[noteID] = "not a frame"

        for field in [CompareReviewCorrectionRequest.Field.text, .rangeEnd] {
            drafts.blockAction(noteID: noteID, field: field,
                error: "Correct this field", notice: "Review action needs attention")
            let firstRequest = try XCTUnwrap(drafts.correctionRequest)

            // The user can move focus, collapse the range or scroll away
            // without changing the draft or its already-visible error.
            drafts.blockAction(noteID: noteID, field: field,
                error: "Correct this field", notice: "Review action needs attention")
            let repeatedRequest = try XCTUnwrap(drafts.correctionRequest)

            XCTAssertNotEqual(firstRequest, repeatedRequest,
                "An unchanged invalid finding must still emit a fresh focus and scroll request")
            XCTAssertEqual(repeatedRequest.noteID, noteID)
            XCTAssertEqual(repeatedRequest.field, field)
            XCTAssertEqual(drafts.rangeActionNoticeNoteID, noteID)
            XCTAssertEqual(drafts.noteDrafts[noteID], "  ")
            XCTAssertEqual(drafts.rangeDrafts[noteID], "not a frame")
        }

        drafts.clearActionNotice()
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertNil(drafts.rangeActionNoticeNoteID)
        XCTAssertNil(drafts.rangeActionNotice)
        XCTAssertEqual(drafts.noteActionErrors[noteID], "Correct this field")
        XCTAssertEqual(drafts.rangeActionErrors[noteID], "Correct this field")
        XCTAssertEqual(drafts.noteDrafts[noteID], "  ")
        XCTAssertEqual(drafts.rangeDrafts[noteID], "not a frame")
    }

    func testAcceptedEditUsesTrimmedText() {
        var updatedText: String?
        let result = CompareReviewTextCommitResult.attempt(
            draft: "  Corrected finding\n", savedText: "Original finding", canEdit: true
        ) { text in
            updatedText = text
            return true
        }

        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(updatedText, "Corrected finding")
    }

    func testRejectedAndUnavailableEditsRemainUnaccepted() {
        let draft = "Corrected finding"
        var updateCalls = 0
        let rejected = CompareReviewTextCommitResult.attempt(
            draft: draft, savedText: "Original finding", canEdit: true
        ) { _ in
            updateCalls += 1
            return false
        }
        let unavailable = CompareReviewTextCommitResult.attempt(
            draft: draft, savedText: "Original finding", canEdit: false
        ) { _ in
            updateCalls += 1
            return true
        }

        XCTAssertEqual(rejected, .rejected)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(updateCalls, 1)
    }

    func testEmptyAndUnchangedEditsDoNotMutateNote() {
        var updateCalls = 0
        for (draft, expected) in [
            (" \n ", CompareReviewTextCommitResult.empty),
            ("  Original finding  ", .accepted)
        ] {
            let result = CompareReviewTextCommitResult.attempt(
                draft: draft, savedText: "Original finding", canEdit: true
            ) { _ in
                updateCalls += 1
                return true
            }
            XCTAssertEqual(result, expected)
        }
        XCTAssertEqual(updateCalls, 0)
    }
}
