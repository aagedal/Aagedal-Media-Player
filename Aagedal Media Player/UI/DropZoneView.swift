// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Placeholder shown when no media file is loaded.

import SwiftUI

struct DropZoneView: View {
    let isDropTargeted: Bool
    let onOpenFile: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Drop a media file here")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("or use File \u{2192} Open")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            Button("Open File\u{2026}") {
                onOpenFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 80)
        )
    }
}
