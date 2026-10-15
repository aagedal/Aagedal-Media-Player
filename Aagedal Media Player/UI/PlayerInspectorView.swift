// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PlayerInspectorView: View {
    enum Tab: String, CaseIterable { case metadata = "Metadata", playback = "Playback" }

    @ObservedObject var controller: PlayerController
    @ObservedObject var comparison: CompareSessionController
    let item: MediaItem
    let isLoadingMetadata: Bool
    let metadataError: String?
    let onRetryMetadata: () -> Void
    @Binding var isPresented: Bool
    @State private var selectedTab = Tab.metadata

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Inspector tab", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("inspector-tab-picker")
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close inspector")
                .accessibilityLabel("Close inspector")
            }
            .padding(12)
            .background(.bar)
            Divider()
            // Keep both trees mounted: a tab change must not call the metadata
            // view's onDisappear, cancel LUFS work or discard its local results.
            ZStack {
                MetadataInspectorView(
                    item: item, useMPV: controller.useMPV,
                    trimIn: controller.trimIn, trimOut: controller.trimOut,
                    isLoadingMetadata: isLoadingMetadata,
                    metadataError: metadataError, onRetryMetadata: onRetryMetadata,
                    isPresented: $isPresented
                )
                .opacity(selectedTab == .metadata ? 1 : 0)
                .allowsHitTesting(selectedTab == .metadata)
                .disabled(selectedTab != .metadata)
                .accessibilityHidden(selectedTab != .metadata)

                PlaybackInspectorView(primary: controller, comparison: comparison)
                    .opacity(selectedTab == .playback ? 1 : 0)
                    .allowsHitTesting(selectedTab == .playback)
                    .disabled(selectedTab != .playback)
                    .accessibilityHidden(selectedTab != .playback)
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onExitCommand { isPresented = false }
    }
}
