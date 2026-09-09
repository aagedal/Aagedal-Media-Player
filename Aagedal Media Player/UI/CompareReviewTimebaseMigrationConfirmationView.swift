// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CompareReviewTimebaseMigrationConfirmationView: View {
    let preview: CompareReviewRelinkPreview
    let migration: CompareReviewTimebaseMigration
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var compareSession: CompareSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Migrate Rounded Timebases in \(migration.changedNotes.count) Notes?")
                .font(.headline)
            Text("Keep the recorded A/B frame numbers and inclusive A range endpoints. Correct recognized rounded rates to the loaded media’s exact broadcast rates and recalculate seconds for the changed sources.")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    path("Source A", preview.primaryURL.path)
                    path("Source B", preview.secondaryURL.path)
                    path("Original sidecar — retained unchanged", preview.sourceURL.path)
                    path("New sidecar — becomes active in this session", preview.destinationURL.path)
                    Divider()
                    ForEach(Array(migration.original.notes.indices), id: \.self) { index in
                        let old = migration.original.notes[index]
                        let new = migration.migrated.notes[index]
                        if old != new {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Note \(index + 1): \(old.text)")
                                    .font(.callout.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                coordinate("A", frame: old.primaryFrame,
                                    oldNumerator: old.primaryRateNumerator, oldDenominator: old.primaryRateDenominator,
                                    newNumerator: new.primaryRateNumerator, newDenominator: new.primaryRateDenominator,
                                    oldFallback: old.primaryTime, newFallback: new.primaryTime)
                                if let end = old.primaryEndFrame {
                                    coordinate("A inclusive end", frame: end,
                                        oldNumerator: old.primaryRateNumerator, oldDenominator: old.primaryRateDenominator,
                                        newNumerator: new.primaryRateNumerator, newDenominator: new.primaryRateDenominator)
                                }
                                coordinate("B", frame: old.secondaryFrame,
                                    oldNumerator: old.secondaryRateNumerator, oldDenominator: old.secondaryRateDenominator,
                                    newNumerator: new.secondaryRateNumerator, newDenominator: new.secondaryRateDenominator,
                                    oldFallback: old.secondaryTime, newFallback: new.secondaryTime)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 320)
            Text("Review the resulting frames after migration: this cannot recover a different intended frame if historical rounding affected capture. Text, classifications, note IDs, creation dates and source identities are retained; changed notes receive a new edit timestamp.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Reopening the media uses its original sidecar. Use Notes → Open Notes Copy… to reopen this migrated copy; subsequent edits and exports use the active copy.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if compareSession.isReviewRelinkSaving { ProgressView().controlSize(.small) }
                Button("Cancel") { compareSession.cancelReviewRelink() }
                    .keyboardShortcut(.cancelAction)
                Button("Save and Use Migrated Copy") {
                    compareSession.confirmReviewRelink(primary: primaryController)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(compareSession.isReviewRelinkSaving)
            }
        }
        .padding(24)
        .frame(width: 660)
    }

    private func path(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func coordinate(
        _ source: String, frame: Int64,
        oldNumerator: Int64, oldDenominator: Int64,
        newNumerator: Int64, newDenominator: Int64,
        oldFallback: Double? = nil, newFallback: Double? = nil
    ) -> some View {
        let changed = oldNumerator != newNumerator || oldDenominator != newDenominator
        let oldTime = Double(frame) * Double(oldDenominator) / Double(oldNumerator)
        let newTime = Double(frame) * Double(newDenominator) / Double(newNumerator)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(source) frame \(frame) retained")
            if changed {
                Text("Rate: \(oldNumerator)/\(oldDenominator) → \(newNumerator)/\(newDenominator) fps")
                Text("Frame time: \(seconds(oldTime)) → \(seconds(newTime)) s")
                if let oldFallback, let newFallback {
                    Text("Stored seconds: \(seconds(oldFallback)) → \(seconds(newFallback)) s")
                }
            } else {
                Text("Rate and seconds unchanged (\(oldNumerator)/\(oldDenominator) fps)")
            }
        }
        .font(.caption.monospaced())
        .accessibilityElement(children: .combine)
    }

    private func seconds(_ time: Double) -> String {
        String(format: "%.9f", time)
    }
}
