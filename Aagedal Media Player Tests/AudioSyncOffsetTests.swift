// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class AudioSyncOffsetTests: XCTestCase {
    func testPlaybackShortcutsYieldToNativeFieldEditorsAndEditableControls() {
        let field = NSTextField()
        let editor = NSTextView()
        XCTAssertTrue(PlaybackKeyboardFocus.isEditingText(field))
        XCTAssertTrue(PlaybackKeyboardFocus.isEditingText(editor))
        editor.isEditable = false
        XCTAssertFalse(PlaybackKeyboardFocus.isEditingText(editor))
        XCTAssertFalse(PlaybackKeyboardFocus.isEditingText(NSTextField(labelWithString: "Read only")))
        XCTAssertFalse(PlaybackKeyboardFocus.isEditingText(NSView()))
        XCTAssertFalse(PlaybackKeyboardFocus.isEditingText(nil))
    }

    func testOffsetIsBoundedAndNonFiniteInputCannotReachPlayback() {
        let player = PlayerController()
        defer { player.teardown() }
        player.setAudioSyncOffset(milliseconds: 125.3)
        XCTAssertEqual(player.audioSyncOffsetMilliseconds, 125)
        for invalid in [Double.nan, .infinity, -.infinity] {
            player.setAudioSyncOffset(milliseconds: invalid)
            XCTAssertEqual(player.audioSyncOffsetMilliseconds, 125)
        }
        player.setAudioSyncOffset(milliseconds: 5000)
        XCTAssertEqual(player.audioSyncOffsetMilliseconds, 2000)
        player.setAudioSyncOffset(milliseconds: -5000)
        XCTAssertEqual(player.audioSyncOffsetMilliseconds, -2000)
        player.setAudioSyncOffset(milliseconds: 0)
        XCTAssertEqual(player.audioSyncOffsetMilliseconds, 0)
    }

    func testOffsetSurvivesSameFileReloadAndResetsOnDifferentFile() {
        let player = PlayerController(proResRAWDetector: { _, _ in false })
        let first = MediaItem(url: URL(fileURLWithPath: "/tmp/sync-first.mov"), name: "first", size: 0)
        let second = MediaItem(url: URL(fileURLWithPath: "/tmp/sync-second.mov"), name: "second", size: 0)
        defer { player.teardown() }
        player.loadMedia(first)
        player.setAudioSyncOffset(milliseconds: -175)
        player.loadMedia(first)
        XCTAssertEqual(player.audioSyncOffsetMilliseconds, -175)
        player.teardown()
        player.setupMPV(url: first.url, startTime: 3)
        XCTAssertEqual(player.mpvPlayer?.requestedAudioSyncOffsetSeconds, -0.175)
        player.loadMedia(second)
        XCTAssertEqual(player.audioSyncOffsetMilliseconds, 0)
    }

    func testSourceOffsetsAreIndependentAndTrackRoutingDoesNotResetThem() {
        let first = PlayerController(), second = PlayerController()
        defer { first.teardown(); second.teardown() }
        first.setupMPV(url: URL(fileURLWithPath: "/tmp/sync-a.mov"), startTime: 0)
        second.setupMPV(url: URL(fileURLWithPath: "/tmp/sync-b.mov"), startTime: 0)
        first.setAudioSyncOffset(milliseconds: 321)
        second.setAudioSyncOffset(milliseconds: -65)
        first.mpvPlayer?.setAudioChannelRouting(.init(channelCount: 2, mutedChannels: [0]))
        XCTAssertEqual(first.mpvPlayer?.requestedAudioSyncOffsetSeconds, 0.321)
        XCTAssertEqual(second.mpvPlayer?.requestedAudioSyncOffsetSeconds, -0.065)
        first.setAudioSyncOffset(milliseconds: 0)
        XCTAssertEqual(second.audioSyncOffsetMilliseconds, -65)
    }

    func testActualMPVOffsetBeforeInitializationDuringPlaybackAndAfterSeek() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-sync-\(UUID()).mkv")
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=320x180:r=25:d=4",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=4",
            "-c:v", "ffv1", "-c:a", "pcm_s16le", "-y", url.path
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let player = MPVPlayer()
        defer { player.destroy() }
        player.isMuted = true
        player.setLooping(true)
        player.setAudioSyncOffset(milliseconds: 125)
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let layer = MPVMetalLayer(); layer.frame = view.bounds; layer.drawableSize = view.bounds.size
        view.layer = layer; view.wantsLayer = true
        player.attachDrawable(layer)
        XCTAssertEqual(try XCTUnwrap(player.audioSyncOffsetSnapshot()), 0.125, accuracy: 0.000_001)
        player.load(url: url, autostart: true)
        for _ in 0..<500 where !player.isFileLoaded || !player.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(player.isFileLoaded)
        XCTAssertTrue(player.isPlaying)
        for value in [-2000.0, -55, 2000, 0] {
            player.setAudioSyncOffset(milliseconds: value)
            for _ in 0..<100 {
                if let actual = player.audioSyncOffsetSnapshot(), abs(actual - value / 1000) < 0.000_001 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(try XCTUnwrap(player.audioSyncOffsetSnapshot()), value / 1000, accuracy: 0.000_001)
        }
        for value in 0..<100 { player.setAudioSyncOffset(milliseconds: Double(value * 10)) }
        player.setAudioSyncOffset(milliseconds: 250)
        for _ in 0..<100 where player.audioSyncOffsetSnapshot() != 0.25 {
            try await Task.sleep(for: .milliseconds(10))
        }
        player.pause()
        player.seek(to: 1)
        player.play()
        for _ in 0..<200 where (player.playbackTimeSnapshot() ?? 0) < 1 || !player.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(player.playbackTimeSnapshot() ?? 0, 1)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(try XCTUnwrap(player.audioSyncOffsetSnapshot()), 0.25, accuracy: 0.000_001)
        withExtendedLifetime(view) {}
    }
}
