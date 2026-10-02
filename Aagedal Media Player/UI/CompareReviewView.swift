// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Every Review text field shares one focus owner. Separate row FocusStates
/// can leave the parent's new-note value stale while a range owns the actual
/// keyboard focus, making an explicit new-note assignment have no effect.
nonisolated enum CompareReviewFieldFocusTarget: Hashable {
    case newNote, filter
    case noteText(UUID), rangeEnd(UUID)

    init(_ target: CompareReviewFocusTarget) {
        switch target {
        case .newNote: self = .newNote
        case .filter: self = .filter
        }
    }
}

/// Each blocked action must reveal its correction field again, even when the
/// finding and error message are unchanged from the previous attempt.
struct CompareReviewCorrectionRequest: Equatable {
    enum Field { case text, rangeEnd }

    let id = UUID()
    let noteID: UUID
    let field: Field
}

/// Mounting, editing availability and explicit navigation can change while a
/// focus task yields. Changes cancel that task before it can restore old focus.
private struct CompareReviewMountedFocusRequest: Equatable {
    let correctionRequest: CompareReviewCorrectionRequest?
    let textError: String?
    let rangeError: String?
    let canEdit: Bool
    let canRestoreFocus: Bool
}

/// Moving focus to the correction selected by action preflight must not
/// validate another field and immediately steal that focus back.
enum CompareReviewRangeFocusLossPolicy {
    static func canHandlePassively(
        noteID: UUID, correctionRequest: CompareReviewCorrectionRequest?
    ) -> Bool {
        guard let correctionRequest else { return true }
        return correctionRequest.noteID == noteID && correctionRequest.field == .rangeEnd
    }

    static func shouldCommit(
        draft: String, savedEndFrame: Int64?, noteID: UUID,
        correctionRequest: CompareReviewCorrectionRequest?
    ) -> Bool {
        guard canHandlePassively(noteID: noteID, correctionRequest: correctionRequest) else { return false }
        let entered = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Erasing a saved endpoint is a changed draft too. It needs explicit
        // Clear range guidance rather than silently displaying an empty field
        // while the finding still retains its saved range.
        return entered != (savedEndFrame.map(String.init) ?? "")
    }
}

/// A passive text callback must not save another finding or steal focus from
/// the correction selected by action preflight. Explicit Return still commits.
enum CompareReviewTextFocusLossPolicy {
    static func shouldCommit(
        noteID: UUID, correctionRequest: CompareReviewCorrectionRequest?, canEdit: Bool
    ) -> Bool {
        guard canEdit else { return false }
        guard let correctionRequest else { return true }
        return correctionRequest.noteID == noteID && correctionRequest.field == .text
    }
}

/// Error callbacks and lazy-row recreation can happen while loading or a save
/// has disabled editing. Retain the correction and reveal it when editing
/// resumes, without assigning keyboard focus to an unavailable field.
enum CompareReviewCorrectionFocusPolicy {
    static func target(
        noteID: UUID, correctionRequest: CompareReviewCorrectionRequest?,
        textError: String?, rangeError: String?, canEdit: Bool,
        canRestoreFocus: Bool = true
    ) -> CompareReviewCorrectionRequest.Field? {
        guard canEdit, canRestoreFocus else { return nil }
        if let correctionRequest {
            return correctionRequest.noteID == noteID ? correctionRequest.field : nil
        }
        if textError != nil { return .text }
        if rangeError != nil { return .rangeEnd }
        return nil
    }
}

/// Drafts belong to the player window so dismissing Review cannot discard an
/// invalid edit before the user returns to correct it.
struct CompareReviewDraftState {
    var newNoteDraft = ""
    var newNoteActionError: String?
    var noteDrafts: [UUID: String] = [:]
    var noteActionErrors: [UUID: String] = [:]
    var rangeDrafts: [UUID: String] = [:]
    var rangeActionErrors: [UUID: String] = [:]
    var rangeActionNotice: String?
    var rangeActionNoticeNoteID: UUID?
    var correctionRequest: CompareReviewCorrectionRequest?
    var isCorrectionFocusSuspended = false

    /// An explicit new-note/filter destination takes precedence over restoring
    /// an older row's correction, including when the popover is recreated.
    /// Keep its draft, error and selected correction for action preflight.
    mutating func allowExplicitNavigation() {
        isCorrectionFocusSuspended = true
    }

    /// Parent and lazy-row appearance callbacks must choose the same field.
    /// Default new-note focus cannot overwrite a retained row correction, but
    /// an explicit new-note/filter request still takes precedence over it.
    func initialFocusTarget(
        requested: CompareReviewFocusTarget?, notes: [CompareReviewNote], canEdit: Bool
    ) -> CompareReviewFieldFocusTarget {
        if let requested { return CompareReviewFieldFocusTarget(requested) }
        return correctionFocusTarget(in: notes, canEdit: canEdit) ?? .newNote
    }

    /// The stable popover must select a blocked action's field even when its
    /// lazy row is being recreated after a filter hid every finding.
    func correctionFocusTarget(
        in notes: [CompareReviewNote], canEdit: Bool
    ) -> CompareReviewFieldFocusTarget? {
        guard canEdit, !isCorrectionFocusSuspended, let correctionRequest,
              notes.contains(where: { $0.id == correctionRequest.noteID }) else { return nil }
        switch correctionRequest.field {
        case .text: return .noteText(correctionRequest.noteID)
        case .rangeEnd: return .rangeEnd(correctionRequest.noteID)
        }
    }

    mutating func updateNewNoteDraft(_ text: String) {
        newNoteDraft = text
        // Retire feedback with the input itself. A deferred onChange can run
        // after export preflight and erase its newer Add-or-clear guidance.
        newNoteActionError = nil
    }

    /// A queued delete can arrive after saving or loading disabled editing.
    /// Retire input only when the controller accepts the deletion.
    @discardableResult
    mutating func deleteNote(noteID: UUID, action: () -> Bool) -> Bool {
        guard action() else { return false }
        noteDrafts[noteID] = nil
        noteActionErrors[noteID] = nil
        rangeDrafts[noteID] = nil
        rangeActionErrors[noteID] = nil
        if rangeActionNoticeNoteID == noteID { clearActionNotice() }
        return true
    }

    mutating func blockAction(
        noteID: UUID, field: CompareReviewCorrectionRequest.Field,
        error: String, notice: String
    ) {
        isCorrectionFocusSuspended = false
        switch field {
        case .text: noteActionErrors[noteID] = error
        case .rangeEnd: rangeActionErrors[noteID] = error
        }
        rangeActionNotice = notice
        rangeActionNoticeNoteID = noteID
        correctionRequest = CompareReviewCorrectionRequest(noteID: noteID, field: field)
    }

    mutating func clearActionNotice() {
        rangeActionNotice = nil
        rangeActionNoticeNoteID = nil
        correctionRequest = nil
    }

    /// Return, Apply and ordinary blur validation need the same ownership as
    /// action preflight. Otherwise another field's blur can steal focus while
    /// the first invalid field is being revealed.
    mutating func recordFieldValidationError(
        _ error: String?, note: CompareReviewNote,
        field: CompareReviewCorrectionRequest.Field, canEdit: Bool,
        isPassive: Bool = false
    ) {
        let previousError = field == .text ? noteActionErrors[note.id] : rangeActionErrors[note.id]
        switch field {
        case .text: noteActionErrors[note.id] = error
        case .rangeEnd: rangeActionErrors[note.id] = error
        }
        guard let error else {
            if correctionRequest?.noteID == note.id, correctionRequest?.field == field {
                clearActionNotice()
            }
            return
        }
        // Unavailable fields retain their error and draft, but cannot receive
        // correction focus until loading has made them editable again.
        guard canEdit else { return }
        // Leaving an already-invalid correction must allow Tab, clicks and
        // explicit field commands to move away. A fresh UUID here would make
        // the row reacquire focus after every blur. Return/Apply and action
        // preflight still request correction focus on every blocked attempt.
        if isPassive {
            if isCorrectionFocusSuspended { return }
            if previousError == error, correctionRequest?.noteID == note.id,
               correctionRequest?.field == field { return }
        }
        blockAction(noteID: note.id, field: field, error: error,
                    notice: "Review note at source A frame \(note.primaryFrame): \(error)")
    }

    /// Editing one field must not dismiss the correction selected for another.
    /// That request also arbitrates focus-loss validation during the handoff.
    mutating func updateNoteTextDraft(_ text: String, noteID: UUID) {
        guard noteDrafts[noteID] != text else { return }
        isCorrectionFocusSuspended = false
        noteDrafts[noteID] = text
        noteActionErrors[noteID] = nil
        if correctionRequest?.noteID == noteID, correctionRequest?.field == .text {
            clearActionNotice()
        }
    }

    mutating func updateRangeEndDraft(_ text: String, noteID: UUID) {
        // A field may echo its unchanged value during a focus handoff. That
        // callback must not erase the error or resume correction restoration.
        guard rangeDrafts[noteID] != text else { return }
        isCorrectionFocusSuspended = false
        rangeDrafts[noteID] = text
        // Clear the previous input error in this same owner mutation. A row's
        // deferred onChange can run after validation of this new draft and
        // must not erase that newer error or its selected correction.
        rangeActionErrors[noteID] = nil
        if correctionRequest?.noteID == noteID, correctionRequest?.field == .rangeEnd {
            clearActionNotice()
        }
    }

    mutating func finishNoteTextCommit(noteID: UUID) {
        noteDrafts[noteID] = nil
        noteActionErrors[noteID] = nil
        if correctionRequest?.noteID == noteID, correctionRequest?.field == .text {
            clearActionNotice()
        }
    }

    /// Once accepted, an endpoint belongs to the saved note. Keeping a settled
    /// draft would override a newer endpoint merged from another window or
    /// loaded from this same sidecar. Only genuine user input stays in drafts.
    mutating func finishRangeEndCommit(noteID: UUID) {
        rangeDrafts[noteID] = nil
        rangeActionErrors[noteID] = nil
        if correctionRequest?.noteID == noteID, correctionRequest?.field == .rangeEnd {
            clearActionNotice()
        }
    }

    /// Passive callbacks can arrive after another disappearing field has
    /// selected a correction. Read the owner's live request and draft rather
    /// than the row's earlier snapshot, including when a blur precedes removal.
    mutating func commitTextOnDeparture(
        note: CompareReviewNote, canEdit: Bool, update: (String) -> Bool
    ) {
        guard CompareReviewTextFocusLossPolicy.shouldCommit(
            noteID: note.id, correctionRequest: correctionRequest, canEdit: canEdit
        ) else { return }
        commitNoteText(note: note, canEdit: canEdit, isPassive: true, update: update)
    }

    /// Return can arrive from a row rendered before another window's sidecar
    /// save was merged. Compare the live draft with the current saved note,
    /// just as departure does, rather than retiring input against that old row.
    mutating func commitNoteText(
        note: CompareReviewNote, canEdit: Bool, isPassive: Bool = false,
        update: (String) -> Bool
    ) {
        guard let draft = noteDrafts[note.id] else { return }
        switch CompareReviewTextCommitResult.attempt(
            draft: draft, savedText: note.text, canEdit: canEdit, update: update
        ) {
        case .accepted:
            finishNoteTextCommit(noteID: note.id)
        case .empty:
            recordFieldValidationError("Enter note text before continuing.",
                note: note, field: .text, canEdit: canEdit, isPassive: isPassive)
        case .unavailable:
            recordFieldValidationError("Review notes cannot be edited right now. Retry loading the review before continuing.",
                note: note, field: .text, canEdit: canEdit, isPassive: isPassive)
        case .rejected:
            recordFieldValidationError("This note could not be updated. Retry the edit.",
                note: note, field: .text, canEdit: canEdit, isPassive: isPassive)
        }
    }

    /// The explicit current-frame action replaces typed input even when it
    /// chooses the existing endpoint, which emits no note-value change.
    @discardableResult
    mutating func applyCurrentRangeEnd(noteID: UUID, action: () -> Int64?) -> Bool {
        guard action() != nil else { return false }
        finishRangeEndCommit(noteID: noteID)
        return true
    }

    /// A range field can leave the hierarchy before its FocusState callback
    /// runs. Flush its draft from the owning state as the row disappears,
    /// respecting any correction selected by the preceding text departure.
    mutating func commitRangeOnDeparture(
        note: CompareReviewNote, canEdit: Bool, update: (Int64) -> Bool
    ) {
        guard canEdit,
              CompareReviewRangeFocusLossPolicy.canHandlePassively(
                noteID: note.id, correctionRequest: correctionRequest
              ) else { return }
        commitRangeEnd(note: note, canEdit: canEdit, isPassive: true, update: update)
    }

    /// Apply and Return must use the live draft and current saved endpoint,
    /// including when their row predates another window's same-sidecar save.
    /// An untouched field has no input to submit and must not replay that row's
    /// old saved endpoint over the merged finding.
    mutating func commitRangeEnd(
        note: CompareReviewNote, canEdit: Bool, isPassive: Bool = false,
        update: (Int64) -> Bool
    ) {
        guard let draft = rangeDrafts[note.id] else { return }
        let entered = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if entered == (note.primaryEndFrame.map(String.init) ?? "") {
            finishRangeEndCommit(noteID: note.id)
            return
        }
        guard canEdit else {
            recordFieldValidationError("Review notes cannot be edited right now. Retry loading the review before continuing.",
                note: note, field: .rangeEnd, canEdit: canEdit, isPassive: isPassive)
            return
        }
        guard !entered.isEmpty else {
            recordFieldValidationError("Use Clear range to remove the saved end frame.",
                note: note, field: .rangeEnd, canEdit: canEdit, isPassive: isPassive)
            return
        }
        guard let end = Int64(entered) else {
            recordFieldValidationError("Enter a whole-number end frame.",
                note: note, field: .rangeEnd, canEdit: canEdit, isPassive: isPassive)
            return
        }
        guard update(end) else {
            recordFieldValidationError("End frame must be from the note's start through the last media frame.",
                note: note, field: .rangeEnd, canEdit: canEdit, isPassive: isPassive)
            return
        }
        finishRangeEndCommit(noteID: note.id)
    }

    /// Ordinary Return/blur validation can select a finding just as its row
    /// disappears under a filter. Reveal that correction from the stable
    /// popover, including when reopening it or restoring editing after load.
    func filterRevealingCorrection(
        in notes: [CompareReviewNote], query: String, canEdit: Bool
    ) -> String {
        guard canEdit, let noteID = correctionRequest?.noteID,
              notes.contains(where: { $0.id == noteID }),
              !CompareReviewNavigation.filtered(notes, query: query).contains(where: { $0.id == noteID })
        else { return query }
        return ""
    }

    func hasPendingEdits(in notes: [CompareReviewNote]) -> Bool {
        !newNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || notes.contains { note in
            let textChanged = noteDrafts[note.id].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) != note.text
            } ?? false
            let rangeChanged = rangeDrafts[note.id].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    != (note.primaryEndFrame.map(String.init) ?? "")
            } ?? false
            return textChanged || rangeChanged
        }
    }

    /// A successful same-sidecar save can merge another window's deletion.
    /// Its removed finding must no longer arbitrate blur or correction focus
    /// for surviving rows. Loading temporarily empties notes, so reconcile
    /// only after the current review is editable again.
    mutating func reconcileNotes(_ notes: [CompareReviewNote], canEdit: Bool) {
        guard canEdit else { return }
        let noteIDs = Set(notes.map(\.id))
        noteDrafts = noteDrafts.filter { noteIDs.contains($0.key) }
        noteActionErrors = noteActionErrors.filter { noteIDs.contains($0.key) }
        rangeDrafts = rangeDrafts.filter { noteIDs.contains($0.key) }
        rangeActionErrors = rangeActionErrors.filter { noteIDs.contains($0.key) }
        if let selectedID = correctionRequest?.noteID, !noteIDs.contains(selectedID) {
            clearActionNotice()
        } else if let noticeID = rangeActionNoticeNoteID, !noteIDs.contains(noticeID) {
            clearActionNotice()
        }
    }

    mutating func clear() { self = Self() }
}

/// The window owns relinking so its transient Review popover can close while
/// the file picker and explicit mapping confirmation remain available.
struct CompareReviewRelinkPresentation: ViewModifier {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    @Binding var showReviewNotes: Bool

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { compareSession.reviewRelinkPreview },
                set: { if $0 == nil { compareSession.cancelReviewRelink() } }
            )) { preview in
                if let migration = preview.migration {
                    CompareReviewTimebaseMigrationConfirmationView(
                        preview: preview, migration: migration,
                        primaryController: primaryController, compareSession: compareSession
                    )
                } else {
                    CompareReviewRelinkConfirmationView(
                        preview: preview,
                        primaryController: primaryController,
                        compareSession: compareSession
                    )
                }
            }
            .alert("Could Not Complete Review Action", isPresented: Binding(
                get: { compareSession.reviewRelinkFailure != nil },
                set: { if !$0 { compareSession.dismissReviewRelinkFailure() } }
            )) {
                Button("OK") { compareSession.dismissReviewRelinkFailure() }
            } message: {
                Text(compareSession.reviewRelinkFailure ?? "")
            }
            .onChange(of: compareSession.isReviewRelinking) { _, isRelinking in
                if isRelinking { showReviewNotes = false }
            }
            .onChange(of: primaryController.preparationID) { _, _ in
                compareSession.cancelReviewRelink()
            }
    }
}

struct CompareReviewView: View {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    let timecodeMode: TimecodeDisplayMode
    @Binding var requestedFocus: CompareReviewFocusTarget?
    @Binding var requestedExport: CompareReviewReportFormat?
    @Binding var drafts: CompareReviewDraftState

    @FocusState private var focusedField: CompareReviewFieldFocusTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comparison Review")
                    .font(.headline)
                Spacer()
                Text(compareSession.reviewSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "\(compareSession.reviewNotes.count) notes"
                     : "\(compareSession.filteredReviewNotes.count) of \(compareSession.reviewNotes.count) notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Note at current frame", text: Binding(
                    get: { drafts.newNoteDraft },
                    set: { drafts.updateNewNoteDraft($0) }
                ))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .newNote)
                    .accessibilityIdentifier("compare-review-new-note")
                    .onSubmit {
                        if canAddNote { addNote() }
                    }

                Button(action: addNote) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add review note")
                .accessibilityIdentifier("compare-review-add-note")
                .help("Add note at the current source A frame")
                .disabled(!canAddNote)
            }
            if let newNoteActionError = drafts.newNoteActionError {
                Text(newNoteActionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("compare-review-new-note-error")
            }

            if compareSession.isReviewLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Loading notes…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Review status")
                .accessibilityValue("Loading notes")
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("compare-review-load-status")
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Filter review notes", text: $compareSession.reviewSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .filter)
                    .accessibilityLabel("Filter review notes")
                    .accessibilityIdentifier("compare-review-filter")
                    .help("Filter note text, severity, category, status, and timeline markers. Exports always include all notes.")
                if !compareSession.reviewSearchQuery.isEmpty {
                    Button {
                        // Clearing removes this button from the view hierarchy.
                        // Keep keyboard traversal in Review at the filter field.
                        focusedField = .filter
                        compareSession.reviewSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Clear review filter")
                    .accessibilityIdentifier("compare-review-clear-filter")
                }
                navigationButton(.previous, label: "Previous matching note", icon: "chevron.left")
                navigationButton(.next, label: "Next matching note", icon: "chevron.right")
            }

            if compareSession.reviewNotes.isEmpty {
                ContentUnavailableView(
                    "No Review Notes",
                    systemImage: "text.badge.plus",
                    description: Text("Add a note to mark the current source A frame.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if compareSession.filteredReviewNotes.isEmpty {
                ContentUnavailableView(
                    "No Matching Notes",
                    systemImage: "magnifyingglass",
                    description: Text("Change or clear the filter to see your notes.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(compareSession.filteredReviewNotes.enumerated()), id: \.element.id) { entry in
                                noteRow(entry.element, position: entry.offset + 1,
                                        count: compareSession.filteredReviewNotes.count)
                                    .id(entry.element.id)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .onAppear {
                        // A filter with no matches replaces the whole list. When
                        // clearing it creates this scroll view, onChange has no
                        // previous value to observe.
                        if let id = drafts.rangeActionNoticeNoteID {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onChange(of: drafts.correctionRequest) { _, request in
                        guard let request else { return }
                        scrollProxy.scrollTo(request.noteID, anchor: .center)
                    }
                    .onChange(of: compareSession.filteredReviewNotes.map(\.id)) { _, ids in
                        guard let id = drafts.rangeActionNoticeNoteID, ids.contains(id) else { return }
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            if let rangeActionNotice = drafts.rangeActionNotice {
                Text(rangeActionNotice)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Review action needs attention")
                    .accessibilityValue(rangeActionNotice)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("compare-review-range-action-error")
            }

            if let reviewError = compareSession.reviewError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(reviewError)
                        .font(.caption)
                        .accessibilityLabel("Review error")
                        .accessibilityValue(reviewError)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("compare-review-error-status")
                    Spacer()
                    if compareSession.hasUnsavedReviewChanges {
                        Button("Retry Save") {
                            performReviewAction { _, _ in }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(!compareSession.canManageReviewCopy || compareSession.isReviewActionPending)
                        .accessibilityLabel("Retry saving review notes")
                    } else if !compareSession.canEditReviewNotes {
                        Button("Retry") {
                            compareSession.retryReviewLoad(primary: primaryController)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .accessibilityLabel("Retry loading review notes")
                    } else {
                        Button("Dismiss") { compareSession.dismissReviewError() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .accessibilityLabel("Dismiss review error")
                    }
                }
            }

            HStack(spacing: 8) {
                if let sidecarURL = compareSession.reviewSidecarURL {
                    Text("Sidecar: \(sidecarURL.lastPathComponent)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(sidecarURL.path)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Active review sidecar")
                        .accessibilityValue(sidecarURL.path)
                        .accessibilityIdentifier("compare-review-active-sidecar")
                }

                Spacer()

                Menu("Notes") {
                    Button("Open Notes Copy…") {
                        performReviewAction { $0.chooseReviewCopy(primary: $1) }
                    }
                    .disabled(!compareSession.canManageReviewCopy)
                    .help("Open an existing sidecar for this exact A/B pair. Edits save to the selected copy.")
                    Button("Migrate Rounded Timebases…") {
                        performReviewAction { $0.previewReviewTimebaseMigration(primary: $1) }
                    }
                    .disabled(!compareSession.canManageReviewCopy || !compareSession.canEditReviewNotes || compareSession.reviewNotes.isEmpty
                              || primaryController.mediaItem?.metadata?.primaryVideoStream?.frameRate == nil
                              || compareSession.secondaryController.mediaItem?.metadata?.primaryVideoStream?.frameRate == nil)
                    .help("Preview correction of historical decimal broadcast rates and save a new copy, preserving recorded frame numbers.")
                    Divider()
                    Button("Relink Notes…") {
                        performReviewAction { $0.chooseReviewSidecarToRelink(primary: $1) }
                    }
                    .disabled(!compareSession.canRelinkReviewNotes)
                    .help("Relink a sidecar to this A/B pair. Requires an empty review and a new destination.")
                }
                .fixedSize()
                .accessibilityIdentifier("compare-review-notes-menu")

                Menu {
                    Button("CSV Report…") {
                        performReviewAction { $0.exportReviewReport(.csv, primary: $1) }
                    }
                    Button("PDF Report…") {
                        performReviewAction { $0.exportReviewReport(.pdf, primary: $1) }
                    }
                    Divider()
                    Button("DaVinci Resolve Markers (.edl)…") {
                        performReviewAction { $0.exportReviewReport(.resolveMarkersEDL, primary: $1) }
                    }
                    Button("Premiere Pro Sequence Markers (.xml)…") {
                        performReviewAction { $0.exportReviewReport(.premiereProXML, primary: $1) }
                    }
                    Button("Final Cut Pro Markers (.fcpxml)…") {
                        performReviewAction { $0.exportReviewReport(.finalCutProXML, primary: $1) }
                    }
                    Button("Avid Media Composer Markers (.txt)…") {
                        performReviewAction { $0.exportReviewReport(.avidMarkersText, primary: $1) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Export all review notes, including notes hidden by the filter")
                .accessibilityIdentifier("compare-review-export-menu")
                .disabled(!compareSession.canRequestReviewExport)
            }

            switch compareSession.reviewExportState {
            case .idle:
                EmptyView()
            case .exporting:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Exporting review…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Review export status")
                .accessibilityValue("Exporting")
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("compare-review-export-status")
            case .succeeded(let url):
                exportFeedback(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    statusLabel: "Review export completed",
                    message: "Saved \(url.lastPathComponent)"
                )
            case .failed(let message):
                exportFeedback(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    statusLabel: "Review export failed",
                    message: message
                )
            }
        }
        .padding(14)
        .frame(width: 420)
        .disabled(compareSession.isReviewActionPending)
        .onAppear {
            drafts.reconcileNotes(compareSession.reviewNotes, canEdit: compareSession.canEditReviewNotes)
            revealSelectedCorrection()
            let target = drafts.initialFocusTarget(
                requested: requestedFocus, notes: compareSession.reviewNotes,
                canEdit: compareSession.canEditReviewNotes)
            if requestedFocus != nil { drafts.allowExplicitNavigation() }
            focusedField = target
            requestedFocus = nil
            consumeExportRequest()
        }
        .onChange(of: requestedExport) { _, _ in consumeExportRequest() }
        .onChange(of: drafts.correctionRequest) { _, _ in revealSelectedCorrection() }
        .onChange(of: compareSession.canEditReviewNotes) { _, available in
            if available { revealSelectedCorrection() }
        }
        .onChange(of: requestedFocus) { _, target in
            guard let target else { return }
            drafts.allowExplicitNavigation()
            focusedField = CompareReviewFieldFocusTarget(target)
            requestedFocus = nil
        }
        .onDisappear { requestedExport = nil }
        .onChange(of: compareSession.reviewSidecarURL) { _, _ in
            drafts.noteDrafts.removeAll()
            drafts.noteActionErrors.removeAll()
            drafts.rangeDrafts.removeAll()
            drafts.rangeActionErrors.removeAll()
            drafts.clearActionNotice()
            requestedExport = nil
        }
    }

    private func noteRow(_ note: CompareReviewNote, position: Int, count: Int) -> some View {
        CompareReviewNoteRow(
            note: note,
            position: position,
            count: count,
            correctionRequest: drafts.correctionRequest.flatMap { $0.noteID == note.id ? $0 : nil },
            activeCorrectionRequest: drafts.correctionRequest,
            canRestoreCorrectionFocus: !drafts.isCorrectionFocusSuspended,
            focusedField: $focusedField,
            onMountedCorrectionFocus: { field in
                await restoreMountedCorrectionFocus(noteID: note.id, field: field)
            },
            draft: Binding(
                get: { drafts.noteDrafts[note.id] ?? note.text },
                set: {
                    if !compareSession.isReviewActionPending {
                        drafts.updateNoteTextDraft($0, noteID: note.id)
                    }
                }
            ),
            noteActionError: Binding(
                get: { drafts.noteActionErrors[note.id] },
                set: {
                    drafts.recordFieldValidationError($0, note: note, field: .text,
                                                      canEdit: compareSession.canEditReviewNotes)
                }
            ),
            endFrameDraft: Binding(
                get: { drafts.rangeDrafts[note.id] ?? note.primaryEndFrame.map(String.init) ?? "" },
                set: {
                    if !compareSession.isReviewActionPending {
                        drafts.updateRangeEndDraft($0, noteID: note.id)
                    }
                }
            ),
            rangeActionError: Binding(
                get: { drafts.rangeActionErrors[note.id] },
                set: {
                    drafts.recordFieldValidationError($0, note: note, field: .rangeEnd,
                                                      canEdit: compareSession.canEditReviewNotes)
                }
            ),
            timecodeLabel: timecodeLabel(for: note),
            canEdit: compareSession.canEditReviewNotes,
            onSeek: {
                compareSession.seekToReviewNote(note, primary: primaryController)
            },
            onTextCommit: {
                guard let currentNote = compareSession.reviewNotes.first(where: { $0.id == note.id }) else { return }
                drafts.commitNoteText(note: currentNote, canEdit: compareSession.canEditReviewNotes) {
                    compareSession.updateReviewNote(id: note.id, text: $0)
                }
            },
            onTextDeparture: {
                guard let currentNote = compareSession.reviewNotes.first(where: { $0.id == note.id }) else { return }
                drafts.commitTextOnDeparture(note: currentNote, canEdit: compareSession.canEditReviewNotes) {
                    compareSession.updateReviewNote(id: note.id, text: $0)
                }
            },
            onDelete: {
                drafts.deleteNote(noteID: note.id) {
                    compareSession.deleteReviewNote(id: note.id)
                }
            },
            onClassification: { severity, category, status in
                compareSession.updateReviewClassification(
                    id: note.id, severity: severity, category: category, status: status
                )
            },
            onRange: { endFrame in
                guard compareSession.updateReviewRange(id: note.id, endFrame: endFrame) else { return false }
                drafts.finishRangeEndCommit(noteID: note.id)
                return true
            },
            onRangeCommit: {
                guard let currentNote = compareSession.reviewNotes.first(where: { $0.id == note.id }) else { return }
                drafts.commitRangeEnd(note: currentNote, canEdit: compareSession.canEditReviewNotes) {
                    compareSession.updateReviewRange(id: note.id, endFrame: $0)
                }
            },
            onRangeDeparture: {
                guard let currentNote = compareSession.reviewNotes.first(where: { $0.id == note.id }) else { return }
                drafts.commitRangeOnDeparture(note: currentNote, canEdit: compareSession.canEditReviewNotes) {
                    compareSession.updateReviewRange(id: note.id, endFrame: $0)
                }
            },
            onCurrentEnd: {
                drafts.applyCurrentRangeEnd(noteID: note.id) {
                    guard compareSession.endReviewRangeAtCurrentFrame(id: note.id, primary: primaryController) else {
                        return nil
                    }
                    return compareSession.reviewNotes.first { $0.id == note.id }?.primaryEndFrame
                }
            },
            onSeekEnd: {
                compareSession.seekToReviewRangeEnd(note, primary: primaryController)
            }
        )
    }

    private func consumeExportRequest() {
        guard let format = requestedExport else { return }
        requestedExport = nil
        guard compareSession.canRequestReviewExport else { return }
        performReviewAction { $0.exportReviewReport(format, primary: $1) }
    }

    private func performReviewAction(
        _ action: @escaping @MainActor (CompareSessionController, PlayerController) -> Void
    ) {
        guard !compareSession.isReviewActionPending else { return }
        drafts.reconcileNotes(compareSession.reviewNotes, canEdit: compareSession.canEditReviewNotes)
        if !drafts.newNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.newNoteActionError = "Add or clear the new note before continuing."
            focusedField = .newNote
            return
        }
        if drafts.hasPendingEdits(in: compareSession.reviewNotes), !compareSession.canEditReviewNotes {
            drafts.rangeActionNotice = "Review notes cannot be edited right now. Retry loading the review before continuing."
            drafts.rangeActionNoticeNoteID = nil
            drafts.correctionRequest = nil
            return
        }
        // Reject an empty changed note before applying any pending range or
        // text edit. Exporting its previous text would silently discard input.
        for note in compareSession.reviewNotes {
            guard let draft = drafts.noteDrafts[note.id],
                  draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            drafts.blockAction(
                noteID: note.id, field: .text,
                error: "Enter note text before continuing.",
                notice: "Review note at source A frame \(note.primaryFrame) needs text before this action."
            )
            revealInvalidNote(note.id)
            return
        }
        // Menus and app commands can act while a range field still owns focus.
        // Validate every draft before changing any note. A later invalid field
        // must not leave earlier range edits saved when the action is blocked.
        var rangeUpdates: [(id: UUID, endFrame: Int64)] = []
        for note in compareSession.reviewNotes {
            guard let draft = drafts.rangeDrafts[note.id] else { continue }
            let entered = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = note.primaryEndFrame.map(String.init) ?? ""
            if entered.isEmpty {
                if note.primaryEndFrame != nil {
                    drafts.blockAction(
                        noteID: note.id, field: .rangeEnd,
                        error: "Use Clear range to remove the saved end frame.",
                        notice: "Review note at source A frame \(note.primaryFrame) still has a saved end frame. Use Clear range before this action."
                    )
                    revealInvalidNote(note.id)
                    return
                }
                continue
            }
            guard entered != saved else { continue }
            guard let endFrame = Int64(entered) else {
                drafts.blockAction(
                    noteID: note.id, field: .rangeEnd,
                    error: "Enter a whole-number end frame before continuing.",
                    notice: "Review note at source A frame \(note.primaryFrame) needs a whole-number end frame before this action."
                )
                revealInvalidNote(note.id)
                return
            }
            guard compareSession.canSetReviewRangeEnd(id: note.id, endFrame: endFrame) else {
                drafts.blockAction(
                    noteID: note.id, field: .rangeEnd,
                    error: "End frame must be from the note's start through the last media frame.",
                    notice: "Review note at source A frame \(note.primaryFrame) needs an end frame from its start through the last media frame before this action."
                )
                revealInvalidNote(note.id)
                return
            }
            rangeUpdates.append((note.id, endFrame))
        }
        for update in rangeUpdates {
            guard compareSession.updateReviewRange(id: update.id, endFrame: update.endFrame) else {
                drafts.blockAction(
                    noteID: update.id, field: .rangeEnd,
                    error: "This range could not be updated. Retry the edit.",
                    notice: "A Review range could not be updated. Correct the finding and retry."
                )
                revealInvalidNote(update.id)
                return
            }
            drafts.finishRangeEndCommit(noteID: update.id)
        }
        drafts.clearActionNotice()
        // TextField bindings record drafts immediately, before focus-loss or
        // onDisappear callbacks. Flush them before an action disables editing
        // or captures the notes for an export.
        for note in compareSession.reviewNotes {
            if let text = drafts.noteDrafts[note.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty, text != note.text {
                guard compareSession.updateReviewNote(id: note.id, text: text) else {
                    drafts.blockAction(
                        noteID: note.id, field: .text,
                        error: "This note could not be updated. Retry the edit.",
                        notice: "Review note at source A frame \(note.primaryFrame) could not be updated."
                    )
                    revealInvalidNote(note.id)
                    return
                }
            }
        }
        drafts.noteDrafts.removeAll()
        drafts.noteActionErrors.removeAll()
        // Preflight also accepted unchanged endpoint input; retire those
        // drafts so subsequent same-sidecar merges remain authoritative.
        drafts.rangeDrafts.removeAll()
        drafts.rangeActionErrors.removeAll()
        compareSession.performReviewActionAfterSaving(primary: primaryController, action: action)
    }

    private func revealInvalidNote(_ id: UUID) {
        if !compareSession.filteredReviewNotes.contains(where: { $0.id == id }) {
            compareSession.reviewSearchQuery = ""
        }
    }

    private func revealSelectedCorrection() {
        let query = drafts.filterRevealingCorrection(
            in: compareSession.reviewNotes, query: compareSession.reviewSearchQuery,
            canEdit: compareSession.canEditReviewNotes
        )
        if query != compareSession.reviewSearchQuery { compareSession.reviewSearchQuery = query }
        if let target = drafts.correctionFocusTarget(
            in: compareSession.reviewNotes, canEdit: compareSession.canEditReviewNotes
        ) {
            focusedField = target
        }
    }

    /// A lazy row and its disclosure content may not exist when preflight
    /// chooses a correction. Its mounted field performs the actual handoff,
    /// using the live draft owner again after yielding so newer navigation or
    /// corrections cannot be overwritten by an earlier field's task.
    private func restoreMountedCorrectionFocus(
        noteID: UUID, field: CompareReviewCorrectionRequest.Field
    ) async {
        func liveTarget() -> CompareReviewCorrectionRequest.Field? {
            guard compareSession.reviewNotes.contains(where: { $0.id == noteID }) else { return nil }
            return CompareReviewCorrectionFocusPolicy.target(
                noteID: noteID, correctionRequest: drafts.correctionRequest,
                textError: drafts.noteActionErrors[noteID], rangeError: drafts.rangeActionErrors[noteID],
                canEdit: compareSession.canEditReviewNotes,
                canRestoreFocus: !drafts.isCorrectionFocusSuspended)
        }
        guard !Task.isCancelled, liveTarget() == field else { return }
        let request = drafts.correctionRequest
        focusedField = nil
        await Task.yield()
        guard !Task.isCancelled, drafts.correctionRequest == request,
              liveTarget() == field else { return }
        switch field {
        case .text: focusedField = .noteText(noteID)
        case .rangeEnd: focusedField = .rangeEnd(noteID)
        }
    }

    private func navigationButton(
        _ direction: CompareReviewDirection, label: String, icon: String
    ) -> some View {
        let identifier = switch direction {
        case .previous: "compare-review-previous-note"
        case .next: "compare-review-next-note"
        }
        return Button {
            compareSession.seekToAdjacentReviewNote(direction, primary: primaryController)
        } label: {
            Image(systemName: icon)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .help(label)
        .disabled(compareSession.adjacentReviewNote(direction, primary: primaryController) == nil)
    }

    private func addNote() {
        if compareSession.addReviewNote(drafts.newNoteDraft, primary: primaryController) {
            drafts.updateNewNoteDraft("")
        }
        focusedField = .newNote
    }

    private func exportFeedback(
        icon: String, color: Color, statusLabel: String, message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .accessibilityLabel(statusLabel)
                .accessibilityValue(message)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("compare-review-export-status")
            Spacer()
            Button("Dismiss") { compareSession.dismissReviewExportFeedback() }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("Dismiss review export result")
        }
    }

    private var canAddNote: Bool {
        !drafts.newNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && compareSession.canEditReviewNotes
    }

    private func timecodeLabel(for note: CompareReviewNote) -> String {
        guard let item = primaryController.mediaItem else {
            return TimecodeFormatter.formatTraditionalTime(note.primaryTime)
        }
        let time = compareSession.reviewNotePrimaryTime(note, primaryItem: item)
        return TimecodeFormatter.formatTimeForDisplayWithMode(
            seconds: time,
            item: item,
            mode: timecodeMode
        )
    }
}

/// Hosted by the stable player window, because the review popover can close
/// as soon as the native sidecar picker takes focus.
struct CompareReviewRelinkConfirmationView: View {
    let preview: CompareReviewRelinkPreview
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Relink \(preview.document.notes.count) Review Notes?").font(.headline)
            Text("Confirm that the currently loaded files are the intended replacements. Media matches are not inferred; note frames and classifications remain unchanged.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    relinkPath("Original sidecar", path: preview.sourceURL.path)
                    relinkPath("Previous source A", path: preview.document.primarySource.canonicalPath)
                    relinkPath("Current source A", path: preview.primaryURL.path)
                    Divider()
                    relinkPath("Previous source B", path: preview.document.secondarySource.canonicalPath)
                    relinkPath("Current source B", path: preview.secondaryURL.path)
                    Divider()
                    relinkPath("New sidecar", path: preview.destinationURL.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 350)
            Text("The original sidecar stays unchanged. The new sidecar must not already exist. If an old sidecar occupies that path, move it aside first, then select it again.")
                .font(.callout)
            HStack {
                Spacer()
                if compareSession.isReviewRelinkSaving {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel") { compareSession.cancelReviewRelink() }
                    .keyboardShortcut(.cancelAction)
                Button("Confirm A/B Mapping and Relink") {
                    compareSession.confirmReviewRelink(primary: primaryController)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(compareSession.isReviewRelinkSaving)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func relinkPath(_ label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(path)
    }

}

/// Keep a rejected edit in its field so leaving the field with Tab or a
/// pointer cannot make an unsaved change appear committed.
nonisolated enum CompareReviewTextCommitResult: Equatable {
    case accepted
    case empty
    case unavailable
    case rejected

    static func attempt(
        draft: String, savedText: String, canEdit: Bool, update: (String) -> Bool
    ) -> Self {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard text != savedText else { return .accepted }
        guard canEdit else { return .unavailable }
        return update(text) ? .accepted : .rejected
    }
}

private struct CompareReviewNoteRow: View {
    let note: CompareReviewNote
    let position: Int
    let count: Int
    let correctionRequest: CompareReviewCorrectionRequest?
    // Every field respects the selected correction during passive callbacks,
    // including a range correction in another finding.
    let activeCorrectionRequest: CompareReviewCorrectionRequest?
    let canRestoreCorrectionFocus: Bool
    let focusedField: FocusState<CompareReviewFieldFocusTarget?>.Binding
    let onMountedCorrectionFocus: @MainActor (CompareReviewCorrectionRequest.Field) async -> Void
    let timecodeLabel: String
    let canEdit: Bool
    let onSeek: () -> Void
    let onTextCommit: () -> Void
    let onTextDeparture: () -> Void
    let onDelete: () -> Bool
    let onClassification: (CompareReviewSeverity?, CompareReviewCategory?, CompareReviewStatus?) -> Void
    let onRange: (Int64?) -> Bool
    let onRangeCommit: () -> Void
    let onRangeDeparture: () -> Void
    let onCurrentEnd: () -> Bool
    let onSeekEnd: () -> Void

    // Untouched input reads the saved endpoint through its binding. Explicit
    // range actions update the draft themselves; a deferred saved-value
    // observer would overwrite input typed after that action was accepted.
    @Binding private var endFrameDraft: String
    @Binding private var rangeActionError: String?
    @State private var isRangeExpanded = false

    @Binding private var draft: String
    @Binding private var noteActionError: String?
    @State private var isDeleting = false

    init(
        note: CompareReviewNote,
        position: Int,
        count: Int,
        correctionRequest: CompareReviewCorrectionRequest?,
        activeCorrectionRequest: CompareReviewCorrectionRequest?,
        canRestoreCorrectionFocus: Bool,
        focusedField: FocusState<CompareReviewFieldFocusTarget?>.Binding,
        onMountedCorrectionFocus: @escaping @MainActor (CompareReviewCorrectionRequest.Field) async -> Void,
        draft: Binding<String>,
        noteActionError: Binding<String?>,
        endFrameDraft: Binding<String>,
        rangeActionError: Binding<String?>,
        timecodeLabel: String,
        canEdit: Bool,
        onSeek: @escaping () -> Void,
        onTextCommit: @escaping () -> Void,
        onTextDeparture: @escaping () -> Void,
        onDelete: @escaping () -> Bool,
        onClassification: @escaping (CompareReviewSeverity?, CompareReviewCategory?, CompareReviewStatus?) -> Void,
        onRange: @escaping (Int64?) -> Bool,
        onRangeCommit: @escaping () -> Void,
        onRangeDeparture: @escaping () -> Void,
        onCurrentEnd: @escaping () -> Bool,
        onSeekEnd: @escaping () -> Void
    ) {
        self.note = note
        self.position = position
        self.count = count
        self.correctionRequest = correctionRequest
        self.activeCorrectionRequest = activeCorrectionRequest
        self.canRestoreCorrectionFocus = canRestoreCorrectionFocus
        self.focusedField = focusedField
        self.onMountedCorrectionFocus = onMountedCorrectionFocus
        self.timecodeLabel = timecodeLabel
        self.canEdit = canEdit
        self.onSeek = onSeek
        self.onTextCommit = onTextCommit
        self.onTextDeparture = onTextDeparture
        self.onDelete = onDelete
        self.onClassification = onClassification
        self.onRange = onRange
        self.onRangeCommit = onRangeCommit
        self.onRangeDeparture = onRangeDeparture
        self.onCurrentEnd = onCurrentEnd
        self.onSeekEnd = onSeekEnd
        _draft = draft
        _noteActionError = noteActionError
        _endFrameDraft = endFrameDraft
        _rangeActionError = rangeActionError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onSeek) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timecodeLabel)
                            .font(.caption.monospacedDigit())
                        Text(note.primaryEndFrame.map { "Frames \(note.primaryFrame)–\($0)" } ?? "Frame \(note.primaryFrame)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 94, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seek to \(noteIdentity)")
                .accessibilityIdentifier(identifier("seek"))
                .help("Seek both sources to this review note")

                TextField("Review note", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Text for \(noteIdentity)")
                    .accessibilityIdentifier(identifier("text"))
                    .lineLimit(1...4)
                    .focused(focusedField, equals: .noteText(note.id))
                    .disabled(!canEdit)
                    .onSubmit(commit)
                    .task(id: mountedFocusRequest) { await onMountedCorrectionFocus(.text) }
                Button(role: .destructive) {
                    isDeleting = onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Delete \(noteIdentity)")
                .accessibilityIdentifier(identifier("delete"))
                .help("Delete review note")
                .disabled(!canEdit)
            }
            if let noteActionError {
                Text(noteActionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Note text error for \(noteIdentity)")
                    .accessibilityValue(noteActionError)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier(identifier("text-error"))
            }
            DisclosureGroup(isExpanded: $isRangeExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Severity", selection: Binding(
                        get: { note.severity }, set: { onClassification($0, nil, nil) }
                    )) {
                        ForEach(CompareReviewSeverity.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityLabel("Severity for \(noteIdentity)")
                    .accessibilityIdentifier(identifier("severity"))
                    Picker("Category", selection: Binding(
                        get: { note.category }, set: { onClassification(nil, $0, nil) }
                    )) {
                        ForEach(CompareReviewCategory.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityLabel("Category for \(noteIdentity)")
                    .accessibilityIdentifier(identifier("category"))
                    Picker("Status", selection: Binding(
                        get: { note.status }, set: { onClassification(nil, nil, $0) }
                    )) {
                        ForEach(CompareReviewStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityLabel("Status for \(noteIdentity)")
                    .accessibilityIdentifier(identifier("status"))
                    rangeEditor
                        .onDisappear {
                            if !isDeleting { onRangeDeparture() }
                        }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            rangeActions
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            rangeActions
                        }
                    }
                    if let error = rangeActionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Range error for \(noteIdentity)")
                            .accessibilityValue(error)
                            .accessibilityAddTraits(.updatesFrequently)
                            .accessibilityIdentifier(identifier("range-error"))
                    }
                }
                .padding(.top, 6)
                .disabled(!canEdit)
            } label: {
                Text("\(note.severity.title) · \(note.category.title) · \(note.status.title)")
                    // Labelling the group itself overrides its expanded controls.
                    .accessibilityLabel("Classification and range for \(noteIdentity): \(note.severity.title), \(note.category.title), \(note.status.title)")
                    .accessibilityIdentifier(identifier("classification-and-range"))
            }
            .font(.caption)
        }
        .onChange(of: rangeActionError) { _, error in
            if error != nil { restoreCorrectionFocus() }
        }
        .onChange(of: noteActionError) { _, error in
            if error != nil { restoreCorrectionFocus() }
        }
        .onChange(of: correctionRequest) { _, request in
            if request != nil { restoreCorrectionFocus() }
        }
        .onAppear(perform: restoreCorrectionFocus)
        .onChange(of: focusedField.wrappedValue) { previous, current in
            if previous == .noteText(note.id), current != previous {
                commitOnFocusLoss()
            }
            if previous == .rangeEnd(note.id), current != previous, !isDeleting {
                // Blur and removal use the same live owner state. Another
                // field may have selected a correction since this render.
                onRangeDeparture()
            }
        }
        .onChange(of: canEdit) { _, available in
            if available { restoreCorrectionFocus() }
            else if focusedField.wrappedValue == .noteText(note.id)
                || focusedField.wrappedValue == .rangeEnd(note.id) {
                focusedField.wrappedValue = nil
            }
        }
        .onChange(of: isRangeExpanded) { _, expanded in
            if expanded && correctionFocusTarget == .rangeEnd {
                focusedField.wrappedValue = .rangeEnd(note.id)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear {
            guard !isDeleting else { return }
            commitOnFocusLoss()
            onRangeDeparture()
        }
    }

    @ViewBuilder
    private var rangeActions: some View {
        Button("End at current frame") {
            if onCurrentEnd() {
                rangeActionError = nil
            } else {
                rangeActionError = "Current frame is before the note's start. Enter an end frame or seek forward."
                focusedField.wrappedValue = .rangeEnd(note.id)
            }
        }
        .accessibilityLabel("End \(noteIdentity) at the current frame")
        .accessibilityIdentifier(identifier("range-end-current"))
        if let endFrame = note.primaryEndFrame {
            Button("Seek end", action: onSeekEnd)
                .accessibilityLabel("Seek to source A frame \(endFrame), the end of \(noteIdentity)")
                .accessibilityIdentifier(identifier("range-seek-end"))
            Button("Clear range") {
                if onRange(nil) { rangeActionError = nil }
            }
            .accessibilityLabel("Clear range for \(noteIdentity)")
            .accessibilityIdentifier(identifier("range-clear"))
        }
    }

    private var rangeEditor: some View {
        HStack {
            TextField("End frame (inclusive)", text: $endFrameDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Inclusive range end frame for \(noteIdentity)")
                .accessibilityHint(rangeActionError ?? "Enter a whole source A frame number from the note's start through the last media frame.")
                .accessibilityIdentifier(identifier("range-end"))
                .focused(focusedField, equals: .rangeEnd(note.id))
                .onSubmit(applyRange)
                .task(id: mountedFocusRequest) { await onMountedCorrectionFocus(.rangeEnd) }
            Button("Apply", action: applyRange)
                .accessibilityLabel("Apply range end for \(noteIdentity)")
                .accessibilityIdentifier(identifier("range-apply"))
        }
    }

    private func identifier(_ component: String) -> String {
        "compare-review-note-\(note.id.uuidString.lowercased())-\(component)"
    }

    private var noteIdentity: String {
        "review note \(position) of \(count) at source A frame \(note.primaryFrame)"
    }

    private var correctionFocusTarget: CompareReviewCorrectionRequest.Field? {
        CompareReviewCorrectionFocusPolicy.target(
            noteID: note.id, correctionRequest: activeCorrectionRequest,
            textError: noteActionError, rangeError: rangeActionError, canEdit: canEdit,
            canRestoreFocus: canRestoreCorrectionFocus
        )
    }

    private var mountedFocusRequest: CompareReviewMountedFocusRequest {
        CompareReviewMountedFocusRequest(
            correctionRequest: activeCorrectionRequest,
            textError: noteActionError, rangeError: rangeActionError,
            canEdit: canEdit, canRestoreFocus: canRestoreCorrectionFocus)
    }

    private func restoreCorrectionFocus() {
        if let target = correctionFocusTarget { focusCorrection(target) }
    }

    private func focusCorrection(_ field: CompareReviewCorrectionRequest.Field) {
        guard canEdit else { return }
        switch field {
        case .text:
            focusedField.wrappedValue = .noteText(note.id)
        case .rangeEnd:
            if isRangeExpanded { focusedField.wrappedValue = .rangeEnd(note.id) }
            else { isRangeExpanded = true }
        }
    }

    private func applyRange() {
        guard !isDeleting else { return }
        onRangeCommit()
    }

    private func commitOnFocusLoss() {
        guard !isDeleting else { return }
        onTextDeparture()
    }

    private func commit() {
        guard !isDeleting else { return }
        onTextCommit()
    }
}
