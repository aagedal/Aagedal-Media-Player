// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

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
}
