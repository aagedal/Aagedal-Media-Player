// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import AVFoundation
import XCTest

@MainActor
final class PlayerBackendAdapterTests: XCTestCase {
    func testProResRAWFourCCTagsUseAVFoundation() {
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "aprn", pixelFormat: nil),
            .avFoundation
        )
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "ProRes APRH", pixelFormat: nil),
            .avFoundation
        )
    }

    func testBayerPixelFormatsUseAVFoundation() {
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "prores", pixelFormat: "BAYER_RGGB16LE"),
            .avFoundation
        )
    }

    func testOrdinaryAndAudioOnlyMediaUseMPV() {
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: "hevc", pixelFormat: "yuv420p10le"),
            .mpv
        )
        XCTAssertEqual(
            PlaybackBackendSelector.backend(codec: nil, pixelFormat: nil),
            .mpv
        )
    }

    func testAVPlaybackObservationIdentityRequiresSamePreparationPlayerAndItem() {
        let firstItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/first.mov"))
        let replacementItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/replacement.mov"))
        let firstPlayer = AVPlayer(playerItem: firstItem)
        let replacementPlayer = AVPlayer(playerItem: replacementItem)
        let identity = AVPlaybackObservationIdentity(
            preparationID: 7,
            player: firstPlayer,
            playerItem: firstItem
        )

        XCTAssertTrue(identity.matches(
            preparationID: 7,
            player: firstPlayer,
            playerItem: firstItem
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 8,
            player: firstPlayer,
            playerItem: firstItem
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 7,
            player: replacementPlayer,
            playerItem: replacementItem
        ))
        XCTAssertFalse(identity.matches(
            preparationID: 7,
            player: firstPlayer,
            playerItem: replacementItem
        ))
    }
}
