// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class TrackSelectionControllerTests: XCTestCase {
    func testMPVTrackMappingFiltersInvalidIDsAndKeepsContiguousPositions() {
        let controller = TrackSelectionController()

        controller.rebuildMPVTrackOptions(
            audioNames: ["Disabled", "English"],
            audioIndexes: [0, 4, 7],
            subtitleNames: ["Off", "French"],
            subtitleIndexes: [-1, 9]
        )

        XCTAssertEqual(controller.audioTrackOptions.map(\.id), [4, 7])
        XCTAssertEqual(controller.audioTrackOptions.map(\.position), [0, 1])
        XCTAssertEqual(controller.audioTrackOptions.map(\.streamIndex), [3, 6])
        XCTAssertEqual(controller.audioTrackOptions.map(\.title), ["English", "Track 7"])
        XCTAssertEqual(controller.subtitleTrackOptions.map(\.trackId), [9])
        XCTAssertEqual(controller.subtitleTrackOptions.map(\.position), [0])
        XCTAssertEqual(controller.subtitleTrackOptions.map(\.title), ["French"])
    }

    func testAudioSelectionRejectsInvalidPositionsAndClampsWhenTracksChange() async {
        let controller = TrackSelectionController()
        controller.rebuildMPVTrackOptions(
            audioNames: ["One", "Two"],
            audioIndexes: [1, 2],
            subtitleNames: [],
            subtitleIndexes: []
        )

        let rejected = await controller.selectAudioTrack(
            at: 3,
            playerItem: nil,
            mpvPlayer: nil,
            useMPV: false
        )
        let selected = await controller.selectAudioTrack(
            at: 1,
            playerItem: nil,
            mpvPlayer: nil,
            useMPV: false
        )

        XCTAssertFalse(rejected)
        XCTAssertTrue(selected)
        XCTAssertEqual(controller.selectedAudioTrackOrderIndex, 1)

        controller.rebuildMPVTrackOptions(
            audioNames: ["Only"],
            audioIndexes: [1],
            subtitleNames: [],
            subtitleIndexes: []
        )

        XCTAssertEqual(controller.selectedAudioTrackOrderIndex, 0)
    }

    func testResetCanPreserveOrClearSelection() async {
        let controller = TrackSelectionController()
        controller.rebuildMPVTrackOptions(
            audioNames: ["One", "Two"],
            audioIndexes: [1, 2],
            subtitleNames: [],
            subtitleIndexes: []
        )
        _ = await controller.selectAudioTrack(
            at: 1,
            playerItem: nil,
            mpvPlayer: nil,
            useMPV: false
        )

        controller.reset(preservingSelections: true)
        XCTAssertEqual(controller.selectedAudioTrackOrderIndex, 1)
        XCTAssertTrue(controller.audioTrackOptions.isEmpty)

        controller.reset(preservingSelections: false)
        XCTAssertEqual(controller.selectedAudioTrackOrderIndex, 0)
        XCTAssertEqual(controller.selectedSubtitleTrackOrderIndex, -1)
    }

    func testAudioStreamsOrderByDefaultThenChannelCountThenSourceOrder() {
        let metadata = MediaMetadata(
            duration: nil,
            formatName: nil,
            containerLongName: nil,
            sizeBytes: nil,
            bitRate: nil,
            timecode: nil,
            comment: nil,
            encoder: nil,
            frameCount: nil,
            videoStreams: [],
            audioStreams: [
                audioStream(index: 10, channels: 2, isDefault: false),
                audioStream(index: 11, channels: 1, isDefault: true),
                audioStream(index: 12, channels: 8, isDefault: false),
                audioStream(index: 13, channels: 2, isDefault: false)
            ],
            subtitleStreams: [],
            chapters: []
        )

        XCTAssertEqual(TrackSelectionController.orderAudioStreams(from: metadata), [1, 2, 0, 3])
    }

    private func audioStream(index: Int, channels: Int, isDefault: Bool) -> MediaMetadata.AudioStream {
        MediaMetadata.AudioStream(
            index: index,
            languageCode: nil,
            title: nil,
            codec: nil,
            codecLongName: nil,
            profile: nil,
            sampleRate: nil,
            channels: channels,
            channelLayout: nil,
            bitDepth: nil,
            bitRate: nil,
            isDefault: isDefault
        )
    }
}
