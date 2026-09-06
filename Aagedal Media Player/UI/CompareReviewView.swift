// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CompareReviewView: View {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController
    let timecodeMode: TimecodeDisplayMode

    @State private var draft = ""
    @FocusState private var isDraftFocused: Bool

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
                    .focused($isDraftFocused)
                    .onSubmit {
                        if canAddNote { addNote() }
                    }

                Button(action: addNote) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("Add note at the current source A frame")
                .disabled(!canAddNote)
            }

            if compareSession.isReviewLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading notes…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Filter review notes", text: $compareSession.reviewSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter review notes")
                    .help("Filter note text, severity, category, status, and timeline markers. Exports always include all notes.")
                if !compareSession.reviewSearchQuery.isEmpty {
                    Button {
                        compareSession.reviewSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Clear review filter")
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
                        ForEach(compareSession.filteredReviewNotes) { note in
                            noteRow(note)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            if let reviewError = compareSession.reviewError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(reviewError)
                        .font(.caption)
                    Spacer()
                    if !compareSession.canEditReviewNotes {
                        Button("Retry") {
                            compareSession.retryReviewLoad(primary: primaryController)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else {
                        Button("Dismiss") { compareSession.dismissReviewError() }
                            .buttonStyle(.link)
                            .font(.caption)
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
                }

                Spacer()

                Menu {
                    Button("CSV Report…") {
                        compareSession.exportReviewReport(.csv, primary: primaryController)
                    }
                    Button("PDF Report…") {
                        compareSession.exportReviewReport(.pdf, primary: primaryController)
                    }
                    Divider()
                    Button("DaVinci Resolve Markers (.edl)…") {
                        compareSession.exportReviewReport(
                            .resolveMarkersEDL,
                            primary: primaryController
                        )
                    }
                    Button("Final Cut Pro Markers (.fcpxml)…") {
                        compareSession.exportReviewReport(
                            .finalCutProXML,
                            primary: primaryController
                        )
                    }
                    Button("Avid Media Composer Markers (.txt)…") {
                        compareSession.exportReviewReport(
                            .avidMarkersText,
                            primary: primaryController
                        )
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Export all review notes, including notes hidden by the filter")
                .disabled(
                    compareSession.reviewNotes.isEmpty
                        || compareSession.isReviewLoading
                        || compareSession.reviewExportState.isInFlight
                )
            }

            switch compareSession.reviewExportState {
            case .idle:
                EmptyView()
            case .exporting:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Exporting review…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .succeeded(let url):
                exportFeedback(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    message: "Saved \(url.lastPathComponent)"
                )
            case .failed(let message):
                exportFeedback(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    message: message
                )
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear { isDraftFocused = true }
    }

    private func noteRow(_ note: CompareReviewNote) -> some View {
        CompareReviewNoteRow(
            note: note,
            timecodeLabel: timecodeLabel(for: note),
            canEdit: compareSession.canEditReviewNotes,
            onSeek: {
                compareSession.seekToReviewNote(note, primary: primaryController)
            },
            onUpdate: { text in
                compareSession.updateReviewNote(id: note.id, text: text)
            },
            onDelete: {
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

    private func navigationButton(
        _ direction: CompareReviewDirection, label: String, icon: String
    ) -> some View {
        Button {
            compareSession.seekToAdjacentReviewNote(direction, primary: primaryController)
        } label: {
            Image(systemName: icon)
        }
        .accessibilityLabel(label)
        .help(label)
        .disabled(compareSession.adjacentReviewNote(direction, primary: primaryController) == nil)
    }

    private func addNote() {
        if compareSession.addReviewNote(draft, primary: primaryController) {
            draft = ""
        }
        isDraftFocused = true
    }

    private func exportFeedback(icon: String, color: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { compareSession.dismissReviewExportFeedback() }
                .buttonStyle(.link)
                .font(.caption)
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

private struct CompareReviewNoteRow: View {
    let note: CompareReviewNote
    let timecodeLabel: String
    let canEdit: Bool
    let onSeek: () -> Void
    let onUpdate: (String) -> Void
    let onDelete: () -> Void
    let onClassification: (CompareReviewSeverity?, CompareReviewCategory?, CompareReviewStatus?) -> Void
    let onRange: (Int64?) -> Bool
    let onCurrentEnd: () -> Bool
    let onSeekEnd: () -> Void

    @State private var endFrameDraft = ""
    @State private var rangeError: String?

    @State private var draft: String
    @State private var isDeleting = false
    @FocusState private var isFocused: Bool

    init(
        note: CompareReviewNote,
        timecodeLabel: String,
        canEdit: Bool,
        onSeek: @escaping () -> Void,
        onUpdate: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onClassification: @escaping (CompareReviewSeverity?, CompareReviewCategory?, CompareReviewStatus?) -> Void,
        onRange: @escaping (Int64?) -> Bool,
        onCurrentEnd: @escaping () -> Bool,
        onSeekEnd: @escaping () -> Void
    ) {
        self.note = note
        self.timecodeLabel = timecodeLabel
        self.canEdit = canEdit
        self.onSeek = onSeek
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onClassification = onClassification
        self.onRange = onRange
        self.onCurrentEnd = onCurrentEnd
        self.onSeekEnd = onSeekEnd
        _endFrameDraft = State(initialValue: note.primaryEndFrame.map(String.init) ?? "")
        _draft = State(initialValue: note.text)
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
                .help("Seek both sources to this review note")

                TextField("Review note", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .disabled(!canEdit)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { wasFocused, focused in
                        if wasFocused && !focused { commit() }
                    }
                    .onChange(of: note.text) { _, text in
                        if !isFocused { draft = text }
                    }

                Button(role: .destructive) {
                    isDeleting = true
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete review note")
                .disabled(!canEdit)
            }
            DisclosureGroup("\(note.severity.title) · \(note.category.title) · \(note.status.title)") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Severity", selection: Binding(
                        get: { note.severity }, set: { onClassification($0, nil, nil) }
                    )) {
                        ForEach(CompareReviewSeverity.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Category", selection: Binding(
                        get: { note.category }, set: { onClassification(nil, $0, nil) }
                    )) {
                        ForEach(CompareReviewCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Status", selection: Binding(
                        get: { note.status }, set: { onClassification(nil, nil, $0) }
                    )) {
                        ForEach(CompareReviewStatus.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        TextField("End frame (inclusive)", text: $endFrameDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Inclusive range end frame")
                            .onSubmit(applyRange)
                        Button("Apply", action: applyRange)
                    }
                    HStack {
                        Button("End at current frame") {
                            rangeError = onCurrentEnd() ? nil : "End must be at or after the note's start."
                        }
                        if note.primaryEndFrame != nil {
                            Button("Seek end", action: onSeekEnd)
                            Button("Clear range") {
                                if onRange(nil) { endFrameDraft = ""; rangeError = nil }
                            }
                        }
                    }
                    if let rangeError {
                        Text(rangeError).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.top, 6)
                .disabled(!canEdit)
            }
            .font(.caption)
        }
        .onChange(of: note.primaryEndFrame) { _, end in
            endFrameDraft = end.map(String.init) ?? ""
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { commit() }
    }

    private func applyRange() {
        guard let end = Int64(endFrameDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
              onRange(end) else {
            rangeError = "Enter an end frame from the note's start through the last media frame."
            return
        }
        rangeError = nil
    }

    private func commit() {
        guard !isDeleting, canEdit else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            draft = note.text
            return
        }
        guard text != note.text else { return }
        onUpdate(text)
    }
}
