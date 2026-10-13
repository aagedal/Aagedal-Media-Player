// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Placeholder shown when no media file is loaded.

import SwiftUI
import AppKit

struct DropZoneView: View {
    let isDropTargeted: Bool
    let onOpenFile: () -> Void
    let onOpenRecentFile: (URL) -> Void
    @State private var recentURLs: [URL] = []

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
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

                    if !recentURLs.isEmpty {
                        Menu("Open Recent") {
                            ForEach(recentURLs.prefix(10), id: \.self) { url in
                                Button(url.lastPathComponent) { onOpenRecentFile(url) }
                                    .help(url.path)
                            }
                        }
                        .fixedSize()
                    }

                    Divider().frame(maxWidth: 280)

                    Text("Compare a reference and encode")
                        .font(.subheadline.weight(.semibold))
                    Text("Open your reference, then choose Add comparison file in the toolbar or press ⌘⌥O to load the encode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 80))
            }
            .padding(.bottom, 80)
        }
        .onAppear(perform: refreshRecentFiles)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRecentFiles()
        }
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

    private func refreshRecentFiles() {
        recentURLs = NSDocumentController.shared.recentDocumentURLs
    }
}
