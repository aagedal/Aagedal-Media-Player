// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PlayerInspectorView: View {
    enum Tab: String, CaseIterable {
        case metadata = "Metadata", playback = "Playback", video = "Video", audio = "Audio", subtitles = "Subtitles"

        var systemImage: String {
            switch self {
            case .metadata: "info.circle"
            case .playback: "play.circle"
            case .video: "film"
            case .audio: "speaker.wave.2"
            case .subtitles: "captions.bubble"
            }
        }

        var playbackSection: PlaybackInspectorSection? {
            switch self {
            case .metadata: nil
            case .playback: .playback
            case .video: .video
            case .audio: .audio
            case .subtitles: .subtitles
            }
        }
    }

    @ObservedObject var controller: PlayerController
    @ObservedObject var comparison: CompareSessionController
    let item: MediaItem
    let isLoadingMetadata: Bool
    let metadataError: String?
    let onRetryMetadata: () -> Void
    @Binding var isPresented: Bool
    @State private var selectedTab = Tab.metadata
    /// Shared by the Video, Audio and Subtitles tabs in Compare Mode.
    @State private var selectsSecondary = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("Inspector tab", selection: $selectedTab) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Label(tab.rawValue, systemImage: tab.systemImage)
                                .labelStyle(.iconOnly)
                                .help(tab.rawValue)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help(selectedTab.rawValue)
                    .accessibilityIdentifier("inspector-tab-picker")
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close inspector")
                    .accessibilityLabel("Close inspector")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
                Text(selectedTab.rawValue)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
            }
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
                    onLoudnessAnalysis: { mediaID, streamIndex, result in
                        controller.recordWaveformLoudness(result, streamIndex: streamIndex, mediaID: mediaID)
                    },
                    onProgrammeLoudnessAnalysis: { mediaID, result in
                        controller.recordWaveformProgrammeLoudness(result, mediaID: mediaID)
                    },
                    isPresented: $isPresented
                )
                .opacity(selectedTab == .metadata ? 1 : 0)
                .allowsHitTesting(selectedTab == .metadata)
                .disabled(selectedTab != .metadata)
                .accessibilityHidden(selectedTab != .metadata)

                if let section = selectedTab.playbackSection {
                    PlaybackInspectorView(
                        primary: controller, comparison: comparison,
                        section: section, selectsSecondary: $selectsSecondary
                    )
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onExitCommand { isPresented = false }
    }
}
