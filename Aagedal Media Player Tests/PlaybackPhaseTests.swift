// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class PlaybackPhaseTests: XCTestCase {
    func testOnlyReadyAndBufferingPermitPlaybackControls() {
        XCTAssertFalse(PlaybackPhase.idle.permitsPlaybackControls)
        XCTAssertFalse(PlaybackPhase.preparing.permitsPlaybackControls)
        XCTAssertTrue(PlaybackPhase.ready.permitsPlaybackControls)
        XCTAssertTrue(PlaybackPhase.buffering.permitsPlaybackControls)

        let failure = PlaybackFailure(
            backend: .mpv,
            stage: .loading,
            message: "File not found",
            mediaURL: nil
        )
        XCTAssertFalse(PlaybackPhase.failed(failure).permitsPlaybackControls)
    }

    func testFailureDiagnosticsContainActionableContext() {
        let url = URL(fileURLWithPath: "/tmp/example.mov")
        let failure = PlaybackFailure(
            backend: .avFoundation,
            stage: .playback,
            message: "Decoder stopped",
            mediaURL: url
        )

        XCTAssertEqual(PlaybackPhase.failed(failure).failure, failure)
        XCTAssertTrue(failure.diagnosticText.contains("Apple AVFoundation"))
        XCTAssertTrue(failure.diagnosticText.contains("Playback"))
        XCTAssertTrue(failure.diagnosticText.contains("Decoder stopped"))
        XCTAssertTrue(failure.diagnosticText.contains(url.path))
    }
}
