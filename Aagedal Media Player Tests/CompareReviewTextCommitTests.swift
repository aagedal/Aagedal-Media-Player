// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class CompareReviewTextCommitTests: XCTestCase {
    @MainActor
    func testOrdinaryTextValidationRevealsFindingHiddenByFilterWithoutSavingDrafts() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Picture finding")
        let other = CompareReviewNote(primaryFrame: 20, primaryTime: 2,
            secondaryFrame: 20, secondaryTime: 2, text: "Audio finding")
        let notes = [note, other]
        for query in ["audio", "no matching finding"] {
            var drafts = CompareReviewDraftState()
            drafts.updateNoteTextDraft("  ", noteID: note.id)
            drafts.updateNoteTextDraft("Pending other edit", noteID: other.id)
            drafts.updateRangeEndDraft("invalid range", noteID: other.id)

            // Typing a filter can remove the row before its blur/disappear
            // callback rejects the empty text. No export preflight runs here.
            XCTAssertFalse(CompareReviewNavigation.filtered(notes, query: query).contains(note))
            XCTAssertEqual(CompareReviewTextCommitResult.attempt(
                draft: drafts.noteDrafts[note.id]!, savedText: note.text, canEdit: true,
                update: { _ in XCTFail("Empty text must not save"); return true }), .empty)
            drafts.recordFieldValidationError("Enter note text before continuing.",
                note: note, field: .text, canEdit: true)
            let selectedRequest = drafts.correctionRequest

            let revealedQuery = drafts.filterRevealingCorrection(in: notes, query: query, canEdit: true)
            XCTAssertEqual(revealedQuery, "")
            XCTAssertTrue(CompareReviewNavigation.filtered(notes, query: revealedQuery).contains(note))
            XCTAssertEqual(CompareReviewCorrectionFocusPolicy.target(
                noteID: note.id, correctionRequest: selectedRequest,
                textError: drafts.noteActionErrors[note.id], rangeError: nil, canEdit: true), .text)
            XCTAssertEqual(drafts.correctionRequest, selectedRequest)
            XCTAssertEqual(drafts.noteDrafts[note.id], "  ")
            XCTAssertEqual(drafts.noteDrafts[other.id], "Pending other edit")
            XCTAssertEqual(drafts.rangeDrafts[other.id], "invalid range")
        }
    }

    @MainActor
    func testRetainedRangeCorrectionRevealsOnlyExistingEditableHiddenFinding() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Picture finding", primaryEndFrame: 20)
        var drafts = CompareReviewDraftState()
        drafts.updateRangeEndDraft("invalid range", noteID: note.id)
        XCTAssertEqual(drafts.filterRevealingCorrection(in: [note], query: "audio", canEdit: true), "audio",
            "An ordinary filter remains usable when no correction was selected")
        drafts.recordFieldValidationError("Enter a whole-number end frame.",
            note: note, field: .rangeEnd, canEdit: true)
        let selectedRequest = drafts.correctionRequest

        // Closing Review or loading does not discard the selected correction.
        // Reopening/restoring editing reveals its row before replaying focus.
        XCTAssertEqual(drafts.filterRevealingCorrection(in: [note], query: "audio", canEdit: false), "audio")
        XCTAssertEqual(drafts.filterRevealingCorrection(in: [note], query: "audio", canEdit: true), "")
        XCTAssertEqual(drafts.filterRevealingCorrection(in: [note], query: " PICTURE ", canEdit: true), " PICTURE ",
            "A filter already showing the finding must retain its exact input")
        XCTAssertEqual(drafts.filterRevealingCorrection(in: [], query: "audio", canEdit: true), "audio",
            "A removed finding cannot force an unrelated filter reset")
        XCTAssertEqual(drafts.correctionRequest, selectedRequest)
        XCTAssertEqual(drafts.rangeDrafts[note.id], "invalid range")
        XCTAssertEqual(drafts.rangeActionErrors[note.id], "Enter a whole-number end frame.")
        XCTAssertEqual(CompareReviewCorrectionFocusPolicy.target(
            noteID: note.id, correctionRequest: selectedRequest,
            textError: nil, rangeError: drafts.rangeActionErrors[note.id], canEdit: true), .rangeEnd)
    }

    @MainActor
    func testDisabledTextBlurPreservesDraftErrorAndCorrection() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Saved finding")
        for draft in ["", "Pending edit", note.text] {
            var drafts = CompareReviewDraftState()
            drafts.updateNoteTextDraft(draft, noteID: note.id)
            drafts.blockAction(noteID: note.id, field: .text,
                error: "Retained text error", notice: "Correct this finding")
            let selectedRequest = drafts.correctionRequest

            // Disabling the field resigns FocusState. Neither validation nor
            // unchanged-text cleanup may run from that passive blur.
            if CompareReviewTextFocusLossPolicy.shouldCommit(
                noteID: note.id, correctionRequest: selectedRequest, canEdit: false
            ) {
                switch CompareReviewTextCommitResult.attempt(
                    draft: draft, savedText: note.text, canEdit: false,
                    update: { _ in XCTFail("Disabled blur must not save"); return true }
                ) {
                case .accepted: drafts.finishNoteTextCommit(noteID: note.id)
                case .empty, .unavailable, .rejected:
                    drafts.recordFieldValidationError("Blur changed the error",
                        note: note, field: .text, canEdit: false)
                }
            }
            XCTAssertEqual(drafts.noteDrafts[note.id], draft)
            XCTAssertEqual(drafts.noteActionErrors[note.id], "Retained text error")
            XCTAssertEqual(drafts.correctionRequest, selectedRequest)
            XCTAssertEqual(drafts.rangeActionNotice, "Correct this finding")
            XCTAssertTrue(CompareReviewTextFocusLossPolicy.shouldCommit(
                noteID: note.id, correctionRequest: selectedRequest, canEdit: true),
                "Ordinary blur validation must resume after loading")
        }
    }

    @MainActor
    func testRetainedCorrectionWaitsForEditableRowAndResumesSelectedField() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Saved finding", primaryEndFrame: 20)
        let otherID = UUID()
        for field in [CompareReviewCorrectionRequest.Field.text, .rangeEnd] {
            var drafts = CompareReviewDraftState()
            drafts.updateNoteTextDraft("", noteID: note.id)
            drafts.updateRangeEndDraft("invalid end", noteID: note.id)
            drafts.noteActionErrors[note.id] = "Earlier text error"
            drafts.rangeActionErrors[note.id] = "Earlier range error"
            drafts.blockAction(noteID: note.id, field: field,
                error: "Correct selected field", notice: "Review needs attention")
            let selectedRequest = drafts.correctionRequest

            // A retained invalid row can be recreated while the review is
            // unavailable. Error fallback and request replay must both defer.
            XCTAssertNil(CompareReviewCorrectionFocusPolicy.target(
                noteID: note.id, correctionRequest: selectedRequest,
                textError: drafts.noteActionErrors[note.id],
                rangeError: drafts.rangeActionErrors[note.id], canEdit: false))
            XCTAssertEqual(drafts.correctionRequest, selectedRequest)
            XCTAssertEqual(drafts.noteDrafts[note.id], "")
            XCTAssertEqual(drafts.rangeDrafts[note.id], "invalid end")

            // Completing load replays the originally selected field, even
            // when a different field and another lazy row also have errors.
            XCTAssertEqual(CompareReviewCorrectionFocusPolicy.target(
                noteID: note.id, correctionRequest: drafts.correctionRequest,
                textError: drafts.noteActionErrors[note.id],
                rangeError: drafts.rangeActionErrors[note.id], canEdit: true), field)
            XCTAssertNil(CompareReviewCorrectionFocusPolicy.target(
                noteID: otherID, correctionRequest: drafts.correctionRequest,
                textError: "Other text error", rangeError: "Other range error", canEdit: true))
        }
    }

    @MainActor
    func testUnavailableTextErrorDefersFallbackFocusUntilLoadingCompletes() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Saved finding")
        var drafts = CompareReviewDraftState()
        drafts.updateNoteTextDraft("Pending edit", noteID: note.id)
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[note.id]!, savedText: note.text, canEdit: false,
            update: { _ in XCTFail("Loading must retain the edit"); return true }), .unavailable)
        drafts.recordFieldValidationError("Review notes cannot be edited right now.",
            note: note, field: .text, canEdit: false)
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertNil(CompareReviewCorrectionFocusPolicy.target(
            noteID: note.id, correctionRequest: drafts.correctionRequest,
            textError: drafts.noteActionErrors[note.id], rangeError: nil, canEdit: false))
        XCTAssertEqual(CompareReviewCorrectionFocusPolicy.target(
            noteID: note.id, correctionRequest: drafts.correctionRequest,
            textError: drafts.noteActionErrors[note.id], rangeError: nil, canEdit: true), .text)
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[note.id]!, savedText: note.text, canEdit: true,
            update: { $0 == "Pending edit" }), .accepted)
        drafts.finishNoteTextCommit(noteID: note.id)
        XCTAssertNil(CompareReviewCorrectionFocusPolicy.target(
            noteID: note.id, correctionRequest: drafts.correctionRequest,
            textError: drafts.noteActionErrors[note.id], rangeError: nil, canEdit: true))
    }

    @MainActor
    func testOrdinaryEmptyTextValidationOwnsFocusThroughCompetingRangeBlur() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Saved finding", primaryEndFrame: 20)
        var drafts = CompareReviewDraftState()
        drafts.updateNoteTextDraft("  ", noteID: note.id)
        drafts.updateRangeEndDraft("not a frame", noteID: note.id)
        drafts.rangeActionErrors[note.id] = "Earlier range error"

        // Return/blur uses the row's error binding without report preflight.
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[note.id]!, savedText: note.text, canEdit: true,
            update: { _ in XCTFail("An empty finding must not be saved"); return true }), .empty)
        drafts.recordFieldValidationError("Enter note text before continuing.",
            note: note, field: .text, canEdit: true)

        XCTAssertEqual(drafts.correctionRequest?.noteID, note.id)
        XCTAssertEqual(drafts.correctionRequest?.field, .text)
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: drafts.rangeDrafts[note.id]!, savedEndFrame: note.primaryEndFrame,
            noteID: note.id, correctionRequest: drafts.correctionRequest))
        XCTAssertEqual(drafts.noteDrafts[note.id], "  ")
        XCTAssertEqual(drafts.rangeDrafts[note.id], "not a frame")

        drafts.updateNoteTextDraft("Corrected finding", noteID: note.id)
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[note.id]!, savedText: note.text,
            canEdit: true, update: { $0 == "Corrected finding" }), .accepted)
        drafts.recordFieldValidationError(nil, note: note, field: .text, canEdit: true)
        drafts.finishNoteTextCommit(noteID: note.id)
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertNil(drafts.noteActionErrors[note.id])
        XCTAssertEqual(drafts.rangeActionErrors[note.id], "Earlier range error")
        XCTAssertTrue(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: drafts.rangeDrafts[note.id]!, savedEndFrame: note.primaryEndFrame,
            noteID: note.id, correctionRequest: drafts.correctionRequest))
    }

    @MainActor
    func testOrdinaryRangeValidationDefersPassiveFieldsAndExplicitFailureCanReplaceIt() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Saved finding", primaryEndFrame: 20)
        let other = CompareReviewNote(primaryFrame: 30, primaryTime: 3,
            secondaryFrame: 30, secondaryTime: 3, text: "Other finding")
        var drafts = CompareReviewDraftState()
        drafts.updateRangeEndDraft("not a frame", noteID: note.id)
        drafts.updateNoteTextDraft("", noteID: other.id)
        drafts.recordFieldValidationError("Enter a whole-number end frame.",
            note: note, field: .rangeEnd, canEdit: true)
        let rangeRequest = drafts.correctionRequest

        for noteID in [note.id, other.id] {
            XCTAssertFalse(CompareReviewTextFocusLossPolicy.shouldCommit(
                noteID: noteID, correctionRequest: drafts.correctionRequest, canEdit: true))
        }
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.canHandlePassively(
            noteID: other.id, correctionRequest: drafts.correctionRequest))
        drafts.recordFieldValidationError(nil, note: other, field: .text, canEdit: true)
        XCTAssertEqual(drafts.correctionRequest, rangeRequest,
            "An unrelated successful callback must preserve the selected range")

        // An explicit Return in the other text field deliberately chooses
        // its new failure; the now-unrelated range callback must defer.
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[other.id]!, savedText: other.text, canEdit: true,
            update: { _ in XCTFail("An empty finding must not be saved"); return true }), .empty)
        drafts.recordFieldValidationError("Enter note text before continuing.",
            note: other, field: .text, canEdit: true)
        let textRequest = drafts.correctionRequest
        XCTAssertEqual(textRequest?.noteID, other.id)
        XCTAssertEqual(textRequest?.field, .text)
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.canHandlePassively(
            noteID: note.id, correctionRequest: textRequest))
        drafts.recordFieldValidationError(nil, note: note, field: .rangeEnd, canEdit: true)
        XCTAssertEqual(drafts.correctionRequest, textRequest)
        XCTAssertEqual(drafts.noteActionErrors[other.id], "Enter note text before continuing.")
        XCTAssertEqual(drafts.rangeDrafts[note.id], "not a frame")
    }

    @MainActor
    func testUnavailableFieldValidationRetainsInputWithoutRequestingDisabledFocus() {
        let note = CompareReviewNote(primaryFrame: 10, primaryTime: 1,
            secondaryFrame: 10, secondaryTime: 1, text: "Saved finding")
        var drafts = CompareReviewDraftState()
        drafts.updateNoteTextDraft("Pending edit", noteID: note.id)
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[note.id]!, savedText: note.text, canEdit: false,
            update: { _ in XCTFail("Unavailable notes must not be saved"); return true }), .unavailable)
        drafts.recordFieldValidationError("Review notes cannot be edited right now.",
            note: note, field: .text, canEdit: false)
        XCTAssertEqual(drafts.noteDrafts[note.id], "Pending edit")
        XCTAssertEqual(drafts.noteActionErrors[note.id], "Review notes cannot be edited right now.")
        XCTAssertNil(drafts.correctionRequest)
        XCTAssertNil(drafts.rangeActionNotice)
    }

    @MainActor
    func testTextCorrectionDefersOtherFindingTextBlurWithoutDroppingDrafts() {
        let selectedID = UUID()
        let otherID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.noteDrafts[selectedID] = "  "
        drafts.noteDrafts[otherID] = ""
        drafts.noteActionErrors[otherID] = "Earlier empty text error"
        drafts.blockAction(noteID: selectedID, field: .text,
            error: "Enter note text", notice: "Correct selected finding")
        let selectedRequest = drafts.correctionRequest

        // A focus handoff or lazy-row disappearance must not run the other
        // empty field's commit/refocus path, including a pre-existing error.
        XCTAssertFalse(CompareReviewTextFocusLossPolicy.shouldCommit(
            noteID: otherID, correctionRequest: selectedRequest, canEdit: true))
        XCTAssertTrue(CompareReviewTextFocusLossPolicy.shouldCommit(
            noteID: selectedID, correctionRequest: selectedRequest, canEdit: true))
        XCTAssertEqual(drafts.noteDrafts[otherID], "")
        XCTAssertEqual(drafts.noteActionErrors[otherID], "Earlier empty text error")
        XCTAssertEqual(drafts.correctionRequest, selectedRequest)

        drafts.updateNoteTextDraft("Corrected selected finding", noteID: selectedID)
        XCTAssertTrue(CompareReviewTextFocusLossPolicy.shouldCommit(
            noteID: otherID, correctionRequest: drafts.correctionRequest, canEdit: true))
        XCTAssertEqual(CompareReviewTextCommitResult.attempt(
            draft: drafts.noteDrafts[otherID]!, savedText: "Other finding", canEdit: true,
            update: { _ in XCTFail("Empty text must never be saved"); return true }), .empty)
    }

    @MainActor
    func testRangeCorrectionDefersSameAndOtherFindingTextBlurUntilCorrected() {
        let selectedID = UUID()
        let otherID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.rangeDrafts[selectedID] = "invalid end"
        drafts.blockAction(noteID: selectedID, field: .rangeEnd,
            error: "Enter a whole-number end frame", notice: "Correct selected range")
        let selectedRequest = drafts.correctionRequest
        var updates: [String] = []

        for noteID in [selectedID, otherID] {
            drafts.updateNoteTextDraft("Corrected text for \(noteID)", noteID: noteID)
            if CompareReviewTextFocusLossPolicy.shouldCommit(
                noteID: noteID, correctionRequest: drafts.correctionRequest, canEdit: true
            ) {
                _ = CompareReviewTextCommitResult.attempt(
                    draft: drafts.noteDrafts[noteID]!, savedText: "Saved text", canEdit: true
                ) { updates.append($0); return true }
                drafts.finishNoteTextCommit(noteID: noteID)
            }
            XCTAssertNotNil(drafts.noteDrafts[noteID], "Blocked text must stay pending")
        }
        XCTAssertTrue(updates.isEmpty, "Range correction must not partially save another field")
        XCTAssertEqual(drafts.correctionRequest, selectedRequest)
        XCTAssertEqual(drafts.rangeDrafts[selectedID], "invalid end")

        drafts.updateRangeEndDraft("20", noteID: selectedID)
        for noteID in [selectedID, otherID] {
            XCTAssertTrue(CompareReviewTextFocusLossPolicy.shouldCommit(
                noteID: noteID, correctionRequest: drafts.correctionRequest, canEdit: true))
            XCTAssertEqual(CompareReviewTextCommitResult.attempt(
                draft: drafts.noteDrafts[noteID]!, savedText: "Saved text", canEdit: true
            ) { updates.append($0); return true }, .accepted)
            drafts.finishNoteTextCommit(noteID: noteID)
            XCTAssertNil(drafts.noteDrafts[noteID])
        }
        XCTAssertEqual(updates.count, 2)
    }

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
            noteID: anotherNoteID, correctionRequest: drafts.correctionRequest))

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
                noteID: noteID, correctionRequest: drafts.correctionRequest))
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
            noteID: noteID, correctionRequest: drafts.correctionRequest))
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
            noteID: noteID, correctionRequest: drafts.correctionRequest))
    }

    @MainActor
    func testRangeFocusLossKeepsNormalChangedDraftValidation() {
        let noteID = UUID()
        let corrections: [CompareReviewCorrectionRequest?] = [nil,
            CompareReviewCorrectionRequest(noteID: noteID, field: .rangeEnd)]
        for correction in corrections {
            for draft in ["21", "not a frame", "19"] {
                XCTAssertTrue(CompareReviewRangeFocusLossPolicy.shouldCommit(
                    draft: draft, savedEndFrame: 20, noteID: noteID, correctionRequest: correction))
            }
            for draft in ["", " \n ", " 20 "] {
                XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
                    draft: draft, savedEndFrame: 20, noteID: noteID, correctionRequest: correction))
            }
        }
        XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: "21", savedEndFrame: 20, noteID: noteID,
            correctionRequest: CompareReviewCorrectionRequest(noteID: noteID, field: .text)),
            "Preflight must not partially commit a valid range while text needs correction")
    }

    @MainActor
    func testRangeCorrectionDefersOtherFindingRangeBlurAndPassiveFocus() {
        let selectedID = UUID()
        let otherID = UUID()
        var drafts = CompareReviewDraftState()
        drafts.rangeDrafts[selectedID] = "invalid selected end"
        drafts.blockAction(noteID: selectedID, field: .rangeEnd,
            error: "Enter a whole-number end frame", notice: "Correct selected range")
        let selectedRequest = drafts.correctionRequest

        // While range A receives preflight focus, range B may resign focus or
        // reappear with an earlier error. Neither callback may save or refocus B.
        for otherDraft in ["invalid other end", "30"] {
            drafts.updateRangeEndDraft(otherDraft, noteID: otherID)
            drafts.rangeActionErrors[otherID] = "Earlier range error"
            XCTAssertFalse(CompareReviewRangeFocusLossPolicy.shouldCommit(
                draft: otherDraft, savedEndFrame: 20, noteID: otherID,
                correctionRequest: drafts.correctionRequest))
            XCTAssertFalse(CompareReviewRangeFocusLossPolicy.canHandlePassively(
                noteID: otherID, correctionRequest: drafts.correctionRequest))
            XCTAssertEqual(drafts.correctionRequest, selectedRequest)
            XCTAssertEqual(drafts.rangeDrafts[otherID], otherDraft)
            XCTAssertEqual(drafts.rangeActionErrors[otherID], "Earlier range error")
        }
        XCTAssertTrue(CompareReviewRangeFocusLossPolicy.canHandlePassively(
            noteID: selectedID, correctionRequest: drafts.correctionRequest))

        drafts.updateRangeEndDraft("25", noteID: selectedID)
        XCTAssertTrue(CompareReviewRangeFocusLossPolicy.shouldCommit(
            draft: drafts.rangeDrafts[otherID]!, savedEndFrame: 20, noteID: otherID,
            correctionRequest: drafts.correctionRequest))
        XCTAssertTrue(CompareReviewRangeFocusLossPolicy.canHandlePassively(
            noteID: otherID, correctionRequest: drafts.correctionRequest))
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
