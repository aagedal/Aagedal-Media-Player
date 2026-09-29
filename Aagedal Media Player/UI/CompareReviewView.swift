// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

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

    @State private var draft = ""
    @State private var noteDrafts: [UUID: String] = [:]
    @State private var noteActionErrors: [UUID: String] = [:]
    @State private var rangeDrafts: [UUID: String] = [:]
    @State private var rangeActionErrors: [UUID: String] = [:]
    @State private var rangeActionNotice: String?
    @State private var rangeActionNoticeNoteID: UUID?
    @FocusState private var focusedField: CompareReviewFocusTarget?

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
                TextField("Note at current frame", text: $draft)
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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(compareSession.filteredReviewNotes.enumerated()), id: \.element.id) { entry in
                            noteRow(entry.element, position: entry.offset + 1,
                                    count: compareSession.filteredReviewNotes.count)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            if let rangeActionNotice {
                Text(rangeActionNotice)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Review action needs a valid finding")
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
            focusedField = requestedFocus ?? .newNote
            requestedFocus = nil
            consumeExportRequest()
        }
        .onChange(of: requestedExport) { _, _ in consumeExportRequest() }
        .onChange(of: requestedFocus) { _, target in
            guard let target else { return }
            focusedField = target
            requestedFocus = nil
        }
        .onDisappear { requestedExport = nil }
        .onChange(of: compareSession.reviewSidecarURL) { _, _ in
            noteDrafts.removeAll()
            noteActionErrors.removeAll()
            rangeDrafts.removeAll()
            rangeActionErrors.removeAll()
            rangeActionNotice = nil
            rangeActionNoticeNoteID = nil
            requestedExport = nil
        }
        .onChange(of: primaryController.preparationID) { _, _ in
            noteDrafts.removeAll()
            noteActionErrors.removeAll()
            rangeDrafts.removeAll()
            rangeActionErrors.removeAll()
            rangeActionNotice = nil
            rangeActionNoticeNoteID = nil
            requestedExport = nil
        }
    }

    private func noteRow(_ note: CompareReviewNote, position: Int, count: Int) -> some View {
        CompareReviewNoteRow(
            note: note,
            position: position,
            count: count,
            draft: Binding(
                get: { noteDrafts[note.id] ?? note.text },
                set: {
                    if !compareSession.isReviewActionPending {
                        noteDrafts[note.id] = $0
                        noteActionErrors[note.id] = nil
                        if rangeActionNoticeNoteID == note.id {
                            rangeActionNotice = nil
                            rangeActionNoticeNoteID = nil
                        }
                    }
                }
            ),
            noteActionError: Binding(
                get: { noteActionErrors[note.id] },
                set: { noteActionErrors[note.id] = $0 }
            ),
            endFrameDraft: Binding(
                get: { rangeDrafts[note.id] ?? note.primaryEndFrame.map(String.init) ?? "" },
                set: {
                    if !compareSession.isReviewActionPending {
                        rangeDrafts[note.id] = $0
                        if rangeActionNoticeNoteID == note.id {
                            rangeActionNotice = nil
                            rangeActionNoticeNoteID = nil
                        }
                    }
                }
            ),
            rangeActionError: Binding(
                get: { rangeActionErrors[note.id] },
                set: { rangeActionErrors[note.id] = $0 }
            ),
            timecodeLabel: timecodeLabel(for: note),
            canEdit: compareSession.canEditReviewNotes,
            onSeek: {
                compareSession.seekToReviewNote(note, primary: primaryController)
            },
            onUpdate: { text in
                compareSession.updateReviewNote(id: note.id, text: text)
            },
            onCommitFinished: { noteDrafts[note.id] = nil },
            onDelete: {
                noteDrafts[note.id] = nil
                noteActionErrors[note.id] = nil
                rangeDrafts[note.id] = nil
                rangeActionErrors[note.id] = nil
                if rangeActionNoticeNoteID == note.id {
                    rangeActionNotice = nil
                    rangeActionNoticeNoteID = nil
                }
                compareSession.deleteReviewNote(id: note.id)
            },
            onClassification: { severity, category, status in
                compareSession.updateReviewClassification(
                    id: note.id, severity: severity, category: category, status: status
                )
            },
            onRange: { compareSession.updateReviewRange(id: note.id, endFrame: $0) },
            onCurrentEnd: {
                compareSession.endReviewRangeAtCurrentFrame(id: note.id, primary: primaryController)
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
        // Reject an empty changed note before applying any pending range or
        // text edit. Exporting its previous text would silently discard input.
        for note in compareSession.reviewNotes {
            guard let draft = noteDrafts[note.id],
                  draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            noteActionErrors[note.id] = "Enter note text before continuing."
            rangeActionNotice = "Review note at source A frame \(note.primaryFrame) needs text before this action."
            rangeActionNoticeNoteID = note.id
            revealInvalidNote(note.id)
            return
        }
        // Menus and app commands can act while a range field still owns focus.
        // Validate every draft before changing any note. A later invalid field
        // must not leave earlier range edits saved when the action is blocked.
        var rangeUpdates: [(id: UUID, endFrame: Int64)] = []
        for note in compareSession.reviewNotes {
            guard let draft = rangeDrafts[note.id] else { continue }
            let entered = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = note.primaryEndFrame.map(String.init) ?? ""
            if entered.isEmpty {
                if note.primaryEndFrame != nil {
                    rangeActionErrors[note.id] = "Use Clear range to remove the saved end frame."
                    rangeActionNotice = "Review note at source A frame \(note.primaryFrame) still has a saved end frame. Use Clear range before this action."
                    rangeActionNoticeNoteID = note.id
                    revealInvalidNote(note.id)
                    return
                }
                continue
            }
            guard entered != saved else { continue }
            guard let endFrame = Int64(entered) else {
                rangeActionErrors[note.id] = "Enter a whole-number end frame before continuing."
                rangeActionNotice = "Review note at source A frame \(note.primaryFrame) needs a whole-number end frame before this action."
                rangeActionNoticeNoteID = note.id
                revealInvalidNote(note.id)
                return
            }
            guard compareSession.canSetReviewRangeEnd(id: note.id, endFrame: endFrame) else {
                rangeActionErrors[note.id] = "End frame must be from the note's start through the last media frame."
                rangeActionNotice = "Review note at source A frame \(note.primaryFrame) needs an end frame from its start through the last media frame before this action."
                rangeActionNoticeNoteID = note.id
                revealInvalidNote(note.id)
                return
            }
            rangeUpdates.append((note.id, endFrame))
        }
        for update in rangeUpdates {
            guard compareSession.updateReviewRange(id: update.id, endFrame: update.endFrame) else { return }
            rangeDrafts[update.id] = String(update.endFrame)
            rangeActionErrors[update.id] = nil
        }
        rangeActionNotice = nil
        rangeActionNoticeNoteID = nil
        // TextField bindings record drafts immediately, before focus-loss or
        // onDisappear callbacks. Flush them before an action disables editing
        // or captures the notes for an export.
        for note in compareSession.reviewNotes {
            if let text = noteDrafts[note.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty, text != note.text {
                compareSession.updateReviewNote(id: note.id, text: text)
            }
        }
        noteDrafts.removeAll()
        noteActionErrors.removeAll()
        compareSession.performReviewActionAfterSaving(primary: primaryController, action: action)
    }

    private func revealInvalidNote(_ id: UUID) {
        if !compareSession.filteredReviewNotes.contains(where: { $0.id == id }) {
            compareSession.reviewSearchQuery = ""
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
        if compareSession.addReviewNote(draft, primary: primaryController) {
            draft = ""
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
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

private struct CompareReviewNoteRow: View {
    let note: CompareReviewNote
    let position: Int
    let count: Int
    let timecodeLabel: String
    let canEdit: Bool
    let onSeek: () -> Void
    let onUpdate: (String) -> Void
    let onCommitFinished: () -> Void
    let onDelete: () -> Void
    let onClassification: (CompareReviewSeverity?, CompareReviewCategory?, CompareReviewStatus?) -> Void
    let onRange: (Int64?) -> Bool
    let onCurrentEnd: () -> Bool
    let onSeekEnd: () -> Void

    @Binding private var endFrameDraft: String
    @Binding private var rangeActionError: String?
    @State private var rangeError: String?
    @State private var isRangeExpanded = false

    @Binding private var draft: String
    @Binding private var noteActionError: String?
    @State private var isDeleting = false
    @FocusState private var isFocused: Bool
    @FocusState private var isEndFrameFocused: Bool

    init(
        note: CompareReviewNote,
        position: Int,
        count: Int,
        draft: Binding<String>,
        noteActionError: Binding<String?>,
        endFrameDraft: Binding<String>,
        rangeActionError: Binding<String?>,
        timecodeLabel: String,
        canEdit: Bool,
        onSeek: @escaping () -> Void,
        onUpdate: @escaping (String) -> Void,
        onCommitFinished: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onClassification: @escaping (CompareReviewSeverity?, CompareReviewCategory?, CompareReviewStatus?) -> Void,
        onRange: @escaping (Int64?) -> Bool,
        onCurrentEnd: @escaping () -> Bool,
        onSeekEnd: @escaping () -> Void
    ) {
        self.note = note
        self.position = position
        self.count = count
        self.timecodeLabel = timecodeLabel
        self.canEdit = canEdit
        self.onSeek = onSeek
        self.onUpdate = onUpdate
        self.onCommitFinished = onCommitFinished
        self.onDelete = onDelete
        self.onClassification = onClassification
        self.onRange = onRange
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
                    .focused($isFocused)
                    .disabled(!canEdit)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { wasFocused, focused in
                        if wasFocused && !focused { commit() }
                    }
                Button(role: .destructive) {
                    isDeleting = true
                    onDelete()
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
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            rangeActions
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            rangeActions
                        }
                    }
                    if let error = rangeError ?? rangeActionError {
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
        .onChange(of: note.primaryEndFrame) { _, end in
            endFrameDraft = end.map(String.init) ?? ""
        }
        .onChange(of: rangeActionError) { _, error in
            if error != nil {
                if isRangeExpanded { isEndFrameFocused = true }
                else { isRangeExpanded = true }
            }
        }
        .onChange(of: noteActionError) { _, error in
            if error != nil { isFocused = true }
        }
        .onAppear {
            if noteActionError != nil { isFocused = true }
            else if rangeActionError != nil { isRangeExpanded = true }
        }
        .onChange(of: isRangeExpanded) { _, expanded in
            if expanded && rangeActionError != nil { isEndFrameFocused = true }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { commit() }
    }

    @ViewBuilder
    private var rangeActions: some View {
        Button("End at current frame") {
            if onCurrentEnd() {
                rangeError = nil
            } else {
                rangeError = "Current frame is before the note's start. Enter an end frame or seek forward."
                isEndFrameFocused = true
            }
        }
        .accessibilityLabel("End \(noteIdentity) at the current frame")
        .accessibilityIdentifier(identifier("range-end-current"))
        if let endFrame = note.primaryEndFrame {
            Button("Seek end", action: onSeekEnd)
                .accessibilityLabel("Seek to source A frame \(endFrame), the end of \(noteIdentity)")
                .accessibilityIdentifier(identifier("range-seek-end"))
            Button("Clear range") {
                if onRange(nil) { endFrameDraft = ""; rangeError = nil }
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
                .accessibilityHint(rangeError ?? rangeActionError ?? "Enter a whole source A frame number from the note's start through the last media frame.")
                .accessibilityIdentifier(identifier("range-end"))
                .focused($isEndFrameFocused)
                .onSubmit(applyRange)
                .onChange(of: isEndFrameFocused) { wasFocused, focused in
                    guard wasFocused && !focused else { return }
                    let entered = endFrameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    let saved = note.primaryEndFrame.map(String.init) ?? ""
                    // Tab and pointer navigation commit like Return or Apply.
                    // Keep an empty draft for the explicit Clear range action.
                    if !entered.isEmpty && entered != saved { applyRange() }
                }
                .onChange(of: endFrameDraft) { _, _ in
                    rangeError = nil
                    rangeActionError = nil
                }
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

    private func applyRange() {
        guard let end = Int64(endFrameDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            rangeError = "Enter a whole-number end frame."
            isEndFrameFocused = true
            return
        }
        guard onRange(end) else {
            rangeError = "End frame must be from the note's start through the last media frame."
            isEndFrameFocused = true
            return
        }
        endFrameDraft = String(end)
        rangeError = nil
    }

    private func commit() {
        guard !isDeleting, canEdit else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            noteActionError = "Enter note text before continuing."
            isFocused = true
            return
        }
        if text != note.text { onUpdate(text) }
        onCommitFinished()
    }
}
