// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CompareMismatchIndicator: View {
    @ObservedObject var primaryController: PlayerController
    @ObservedObject var secondaryController: PlayerController
    let isActive: Bool
    @State private var isPresented = false

    private var mismatches: [CompareMismatch] {
        guard isActive,
              let primary = primaryController.mediaItem,
              let secondary = secondaryController.mediaItem else { return [] }
        return CompareMediaComparison.mismatches(primary: primary, secondary: secondary)
    }

    var body: some View {
        if !mismatches.isEmpty {
            Button(action: { isPresented.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(mismatches.count)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
            .help("Show source mismatches")
            .accessibilityLabel("Source mismatches")
            .accessibilityValue("\(mismatches.count) mismatches")
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                CompareMismatchView(mismatches: mismatches)
            }
        }
    }
}

struct CompareMismatchView: View {
    let mismatches: [CompareMismatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Source mismatch", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(mismatches) { mismatch in
                VStack(alignment: .leading, spacing: 3) {
                    Text(mismatch.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        value("A", mismatch.primaryValue)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        value("B", mismatch.secondaryValue)
                    }
                }
            }

            Text("Playback remains aligned to source A. Display-space difference results may reflect these source differences.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private func value(_ source: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(source)
                .fontWeight(.bold)
            Text(value)
                .lineLimit(1)
        }
        .font(.callout.monospacedDigit())
    }
}
