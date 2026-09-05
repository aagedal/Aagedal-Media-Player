// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CompareAudioLayoutIndicator: View {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var secondaryController: PlayerController
    @State private var isPresented = false

    private var summary: CompareAudioLayoutSummary {
        CompareAudioLayoutSummary(
            primaryCount: primaryController.selectedAudioChannelCount,
            primaryLayout: primaryController.selectedAudioStream?.channelLayout,
            secondaryCount: secondaryController.selectedAudioChannelCount,
            secondaryLayout: secondaryController.selectedAudioStream?.channelLayout
        )
    }

    var body: some View {
        let summary = summary
        Button { isPresented.toggle() } label: {
            Image(systemName: summary.hasMismatch ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(summary.hasMismatch ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Show selected audio track layouts and channel labels for A and B")
        .accessibilityLabel("Compared audio layouts")
        .accessibilityValue(summary.hasMismatch ? "Layouts differ" : "Show channel details")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected audio tracks").font(.headline)
                    if summary.hasMismatch {
                        Label("Audio layouts differ", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    source("A", layout: summary.primaryLayout, labels: summary.primaryLabels,
                           unmatched: summary.unmatchedPrimary)
                    source("B", layout: summary.secondaryLayout, labels: summary.secondaryLabels,
                           unmatched: summary.unmatchedSecondary)
                    Text(summary.matchingExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .frame(width: 360)
            .frame(maxHeight: 440)
        }
    }

    private func source(_ name: String, layout: String, labels: [String], unmatched: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(name) · \(layout)").font(.subheadline.bold())
            if !labels.isEmpty {
                Text(labels.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: " · "))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !unmatched.isEmpty {
                Text("No match: \(unmatched.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
