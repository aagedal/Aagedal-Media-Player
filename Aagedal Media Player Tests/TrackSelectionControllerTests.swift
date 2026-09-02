// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
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

    func testAVAudioRoutesKeepDisplayOrderSeparateFromSourceOrder() {
        let routes = TrackSelectionController.avAudioTrackRoutes(
            metadataStreamCount: 4,
            orderedStreamIndices: [1, 2, 0, 3],
            mediaOptionCount: 4
        )

        XCTAssertEqual(routes.map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(routes.map(\.streamIndex), [1, 2, 0, 3])
        XCTAssertEqual(routes.map(\.mediaOptionIndex), [1, 2, 0, 3])
    }

    func testAVAudioRoutesFillIncompleteOrderAndHandleMissingMediaOptions() {
        let routes = TrackSelectionController.avAudioTrackRoutes(
            metadataStreamCount: 4,
            orderedStreamIndices: [2, 2, -1, 8],
            mediaOptionCount: 2
        )

        XCTAssertEqual(routes.map(\.streamIndex), [2, 0, 1, 3])
        XCTAssertEqual(routes.map(\.mediaOptionIndex), [nil, 0, 1, nil])
    }

    func testAVAudioRoutesSupportMediaOptionsWithoutMetadata() {
        let routes = TrackSelectionController.avAudioTrackRoutes(
            metadataStreamCount: 0,
            orderedStreamIndices: [],
            mediaOptionCount: 2
        )

        XCTAssertEqual(routes.map(\.streamIndex), [0, 1])
        XCTAssertEqual(routes.map(\.mediaOptionIndex), [0, 1])
    }

    func testSupersededAVAudioRefreshCannotPublishStaleOptions() async {
        let loader = SuspendedAudioMediaGroupLoader()
        let controller = TrackSelectionController(audioMediaGroupLoader: loader.load)
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/old.mov"))
        let oldItem = mediaItem(audioStreams: [
            audioStream(index: 10, channels: 2, isDefault: false),
            audioStream(index: 11, channels: 1, isDefault: false)
        ])
        let newItem = mediaItem(audioStreams: [
            audioStream(index: 99, channels: 6, isDefault: true)
        ])

        let oldRefresh = Task {
            await controller.refreshAudioTrackOptions(
                mediaItem: oldItem,
                playerItem: playerItem,
                mpvPlayer: nil,
                useMPV: false
            )
        }
        await loader.waitUntilStarted()

        await controller.refreshAudioTrackOptions(
            mediaItem: newItem,
            playerItem: nil,
            mpvPlayer: nil,
            useMPV: false
        )
        loader.resumeFirstLoad()
        await oldRefresh.value

        XCTAssertEqual(controller.audioTrackOptions.map(\.title), ["#99"])
    }

    func testResetInvalidatesPendingAVAudioSelection() async {
        let loader = SuspendedAudioMediaGroupLoader()
        let controller = TrackSelectionController(audioMediaGroupLoader: loader.load)
        controller.rebuildMPVTrackOptions(
            audioNames: ["One", "Two"],
            audioIndexes: [1, 2],
            subtitleNames: [],
            subtitleIndexes: []
        )
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/old.mov"))

        let selection = Task {
            await controller.selectAudioTrack(
                at: 1,
                playerItem: playerItem,
                mpvPlayer: nil,
                useMPV: false
            )
        }
        await loader.waitUntilStarted()

        controller.reset(preservingSelections: false)
        loader.resumeFirstLoad()

        let didSelect = await selection.value
        XCTAssertFalse(didSelect)
        XCTAssertTrue(controller.audioTrackOptions.isEmpty)
        XCTAssertEqual(controller.selectedAudioTrackOrderIndex, 0)
    }

    func testSupersededAVChapterRefreshCannotPublishStaleOptions() async {
        let loader = SuspendedChapterMetadataGroupLoader()
        let controller = TrackSelectionController(chapterMetadataGroupLoader: loader.load)
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/old.mov"))

        let oldRefresh = Task {
            await controller.refreshChapterOptions(
                playerItem: playerItem,
                mpvPlayer: nil,
                useMPV: false
            )
        }
        await loader.waitUntilStarted()

        await controller.refreshChapterOptions(
            playerItem: nil,
            mpvPlayer: nil,
            useMPV: false
        )
        loader.resumeFirstLoad()
        await oldRefresh.value

        XCTAssertTrue(controller.chapterOptions.isEmpty)
    }

    private func mediaItem(audioStreams: [MediaMetadata.AudioStream]) -> MediaItem {
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
            audioStreams: audioStreams,
            subtitleStreams: [],
            chapters: []
        )
        return MediaItem(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            name: "test",
            size: 0,
            metadata: metadata
        )
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

@MainActor
private final class SuspendedAudioMediaGroupLoader {
    private var firstLoadContinuation: CheckedContinuation<AVMediaSelectionGroup?, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var loadCount = 0

    func load(_ playerItem: AVPlayerItem) async -> AVMediaSelectionGroup? {
        _ = playerItem
        loadCount += 1
        guard loadCount == 1 else { return nil }

        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard loadCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstLoad() {
        firstLoadContinuation?.resume(returning: nil)
        firstLoadContinuation = nil
    }
}

@MainActor
private final class SuspendedChapterMetadataGroupLoader {
    private var firstLoadContinuation: CheckedContinuation<[AVTimedMetadataGroup], Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func load(_ asset: AVAsset) async -> [AVTimedMetadataGroup] {
        _ = asset
        didStart = true
        let waiters = startWaiters
        startWaiters = []
        waiters.forEach { $0.resume() }

        return await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstLoad() {
        let group = AVTimedMetadataGroup(
            items: [],
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        )
        firstLoadContinuation?.resume(returning: [group])
        firstLoadContinuation = nil
    }
}
