// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

@MainActor
final class AudioWaveformGeneratorTests: XCTestCase {
    func testCancelImmediatelyClearsLoadingStateAndKeepsItCleared() async {
        let generator = AudioWaveformGenerator()
        let missingURL = URL(fileURLWithPath: "/nonexistent/waveform-test.mov")

        generator.generate(
            url: missingURL,
            streamIndex: 0,
            channels: 2,
            channelLayout: "stereo",
            duration: 1
        )
        XCTAssertTrue(generator.isGenerating)

        generator.cancel()
        XCTAssertFalse(generator.isGenerating)

        await Task.yield()
        XCTAssertFalse(generator.isGenerating)
    }
}
