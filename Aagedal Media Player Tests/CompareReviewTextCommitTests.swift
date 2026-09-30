// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareReviewTextCommitTests: XCTestCase {
    @MainActor
    func testEditingRangePreservesTextCorrectionAndItsFocusPriority() {
        let noteID = UUID()
        let anotherNoteID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.noteDrafts[noteID] = "  "
        drafts.blockAction(noteID: noteID, field: .text,
            error: "Enter note text", notice: "Correct this note")
        let correction = drafts.correctionRequest

        // A range in another row must see the same preflight priority even
        // though only the text row receives the actual focus request.
        drafts.updateRangeEndDraft("invalid other end", noteID: anotherNoteID)
        XCTAssertEqual(drafts.correctionRequest, correction)
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: drafts.rangeDrafts[anotherNoteID]!, savedEndFrame: 10,
            correctionField: drafts.correctionRequest?.field))

        // The real range binding also receives saved-endpoint changes from
        // Clear range. Neither input path corrects the empty note text.
        for range in ["invalid end", "20", ""] {
            drafts.updateRangeEndDraft(range, noteID: noteID)
            XCTAssertEqual(drafts.rangeDrafts[noteID], range)
            XCTAssertEqual(drafts.correctionRequest, correction)
            XCTAssertEqual(drafts.rangeActionNotice, "Correct this note")
            XCTAssertEqual(drafts.noteActionErrors[noteID], "Enter note text")
            XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
                draft: range, savedEndFrame: 10,
                correctionField: drafts.correctionRequest?.field))
        }

        drafts.updateNoteTextDraft("Corrected finding", noteID: noteID)
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertNil(drafts.rangeActionNotice)
        XCTAssertNil(drafts.noteActionErrors[noteID])
        XCTAssertEqual(drafts.noteDrafts[noteID], "Corrected finding")
    }

    @MainActor
    func testEditingTextPreservesRangeCorrectionUntilRangeIsEdited() {
        let noteID = UUID()
        let anotherNoteID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.rangeDrafts[noteID] = "invalid end"
        drafts.noteActionErrors[noteID] = "Earlier text error"
        drafts.blockAction(noteID: noteID, field: .rangeEnd,
            error: "Enter a whole-number end frame", notice: "Correct this range")
        let correction = drafts.correctionRequest

        drafts.updateNoteTextDraft("Corrected finding", noteID: noteID)
        drafts.updateRangeEndDraft("30", noteID: anotherNoteID)
        XCTAssertEqual(drafts.correctionRequest, correction)
        XCTAssertEqual(drafts.rangeActionNotice, "Correct this range")
        XCTAssertEqual(drafts.rangeActionErrors[noteID], "Enter a whole-number end frame")
        XCTAssertEqual(drafts.rangeDrafts[noteID], "invalid end")
        XCTAssertNil(drafts.noteActionErrors[noteID])

        drafts.updateRangeEndDraft("20", noteID: noteID)
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertNil(drafts.rangeActionNotice)
        XCTAssertEqual(drafts.rangeDrafts[noteID], "20")
    }

    @MainActor
    func testTextCorrectionDoesNotCommitOrRefocusAnUnrelatedRangeDraft() {
        let noteID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.noteDrafts[noteID] = "  "
        drafts.rangeDrafts[noteID] = "not a frame"
        drafts.rangeActionErrors[noteID] = "Enter a whole-number end frame."
        drafts.blockAction(noteID: noteID, field: .text,
            error: "Enter note text before continuing.", notice: "Correct this note")

        // Action preflight chooses the empty text first. Resigning the range
        // field must leave its draft pending rather than refocus it by validation.
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: drafts.rangeDrafts[noteID]!, savedEndFrame: 20,
            correctionField: drafts.correctionRequest?.field))
        XCTAssertEqual(drafts.rangeDrafts[noteID], "not a frame")
        XCTAssertEqual(drafts.rangeActionErrors[noteID], "Enter a whole-number end frame.")
        XCTAssertEqual(drafts.correctionRequest?.field, .text)

        // Once text is corrected, normal range blur validation remains active.
        drafts.finishNoteTextCommit(noteID: noteID)
        XCTAssertNil(drafts.noteDrafts[noteID])
        XCTAssertNil(drafts.noteActionErrors[noteID])
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertTrue(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: drafts.rangeDrafts[noteID]!, savedEndFrame: 20,
            correctionField: drafts.correctionRequest?.field))
    }

    @MainActor
    func testRangeFocusLossKeepsNormalChangedDraftValidation() {
        let correctionFields: [CompareReviewCorrectionRequest.Field?] = [nil, .rangeEnd]
        for field in correctionFields {
            for draft in ["21", "not a frame", "19"] {
                XCTAssertTrue(CompareReviewRangeFocusLossPolicy.shouldCommit(
                    draft: draft, savedEndFrame: 20, correctionField: field))
            }
            for draft in ["", " \n ", " 20 "] {
                XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
                    draft: draft, savedEndFrame: 20, correctionField: field))
            }
        }
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: "21", savedEndFrame: 20, correctionField: .text),
            "Preflight must not partially commit a valid range while text needs correction")
    }

    @MainActor
    func testSuccessfulTextCommitPreservesASeparateRangeCorrection() {
        let noteID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.noteDrafts[noteID] = "Corrected text"
        drafts.noteActionErrors[noteID] = "Previous text error"
        drafts.rangeDrafts[noteID] = "invalid range"
        drafts.blockAction(noteID: noteID, field: .rangeEnd,
            error: "Enter a whole-number end frame.", notice: "Correct this range")
        let correction = drafts.correctionRequest

        drafts.finishNoteTextCommit(noteID: noteID)

        XCTAssertNil(drafts.noteDrafts[noteID])
        XCTAssertNil(drafts.noteActionErrors[noteID])
        XCTAssertEqual(drafts.rangeDrafts[noteID], "invalid range")
        XCTAssertEqual(drafts.rangeActionErrors[noteID], "Enter a whole-number end frame.")
        XCTAssertEqual(drafts.rangeActionNotice, "Correct this range")
        XCTAssertEqual(drafts.correctionRequest, correction)
    }

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
