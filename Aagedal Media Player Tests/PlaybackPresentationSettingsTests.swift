// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlaybackPresentationSettingsTests: XCTestCase {
    func testPictureAdjustmentsAreBoundedAndRejectNonFiniteInput() {
        var adjustments = VideoPictureAdjustments()
        XCTAssertTrue(adjustments.isNeutral)
        adjustments[.brightness] = 12.4
        XCTAssertEqual(adjustments[.brightness], 12)
        adjustments[.contrast] = 500
        XCTAssertEqual(adjustments[.contrast], 100)
        adjustments[.gamma] = -500
        XCTAssertEqual(adjustments[.gamma], -100)
        adjustments[.contrast] = .nan
        XCTAssertEqual(adjustments[.contrast], 100)
        XCTAssertFalse(adjustments.isNeutral)
        for kind in VideoPictureAdjustments.Kind.allCases { adjustments[kind] = 0 }
        XCTAssertEqual(adjustments, VideoPictureAdjustments())
    }

    func testSubtitlePresentationIsBounded() {
        var presentation = SubtitlePresentation()
        presentation.delayMilliseconds = 60_000
        presentation.scale = 0.1
        presentation.position = 400.4
        XCTAssertEqual(presentation.delayMilliseconds, 10_000)
        XCTAssertEqual(presentation.scale, 0.5)
        XCTAssertEqual(presentation.position, 150)
        presentation.delayMilliseconds = -.infinity
        XCTAssertEqual(presentation.delayMilliseconds, 10_000)
    }

    func testSettingsSurviveBackendRebuildAndResetOnDifferentFile() {
        let player = PlayerController(proResRAWDetector: { _, _ in false })
        let first = MediaItem(url: URL(fileURLWithPath: "/tmp/presentation-first.mov"), name: "first", size: 0)
        let second = MediaItem(url: URL(fileURLWithPath: "/tmp/presentation-second.mov"), name: "second", size: 0)
        defer { player.teardown() }
        player.loadMedia(first)
        player.setDeinterlaceMode(.on)
        player.setPictureAdjustment(.saturation, to: -40)
        var subtitles = SubtitlePresentation()
        subtitles.delayMilliseconds = 750
        subtitles.scale = 1.5
        player.setSubtitlePresentation(subtitles)
        player.loadMedia(first)
        XCTAssertEqual(player.deinterlaceMode, .on)

        player.teardown()
        player.setupMPV(url: first.url, startTime: 0)
        XCTAssertEqual(player.mpvPlayer?.requestedDeinterlace, .on)
        XCTAssertEqual(player.mpvPlayer?.requestedPictureAdjustments[.saturation], -40)
        XCTAssertEqual(player.mpvPlayer?.requestedSubtitlePresentation, subtitles)

        player.loadMedia(second)
        XCTAssertEqual(player.deinterlaceMode, .auto)
        XCTAssertTrue(player.pictureAdjustments.isNeutral)
        XCTAssertEqual(player.subtitlePresentation, SubtitlePresentation())
        XCTAssertTrue(player.externalSubtitleURLs.isEmpty)
    }

    func testActualMPVPropertiesBeforeInitializationLiveAndExternalSubtitle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("presentation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clip.mkv")
        let subtitleURL = directory.appendingPathComponent("clip.srt")
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=gray:s=320x180:r=25:d=3",
            "-c:v", "ffv1", "-y", url.path
        ])
        try "1\n00:00:00,000 --> 00:00:03,000\nHello\n".write(to: subtitleURL, atomically: true, encoding: .utf8)

        let player = MPVPlayer()
        defer { player.destroy() }
        var adjustments = VideoPictureAdjustments()
        adjustments[.brightness] = 20
        player.setPictureAdjustments(adjustments)
        player.setDeinterlace(.off)
        var subtitles = SubtitlePresentation()
        subtitles.delayMilliseconds = 500
        subtitles.scale = 1.5
        subtitles.position = 80
        player.setSubtitlePresentation(subtitles)

        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let layer = MPVMetalLayer(); layer.frame = view.bounds; layer.drawableSize = view.bounds.size
        view.layer = layer; view.wantsLayer = true
        player.attachDrawable(layer)
        XCTAssertEqual(Double(player.propertyStringSnapshot("brightness") ?? ""), 20)
        XCTAssertEqual(player.propertyStringSnapshot("deinterlace"), "no")
        XCTAssertEqual(Double(player.propertyStringSnapshot("sub-delay") ?? ""), 0.5)
        XCTAssertEqual(Double(player.propertyStringSnapshot("sub-scale") ?? ""), 1.5)
        XCTAssertEqual(Double(player.propertyStringSnapshot("sub-pos") ?? ""), 80)

        player.load(url: url)
        for _ in 0..<500 where !player.isFileLoaded {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(player.isFileLoaded)
        let trackID = try XCTUnwrap(player.addExternalSubtitle(subtitleURL))
        XCTAssertEqual(player.currentSubtitleTrackIndex, trackID)
        XCTAssertEqual(player.externalSubtitlePaths, [subtitleURL.path])

        adjustments[.brightness] = -30
        player.setPictureAdjustments(adjustments)
        for _ in 0..<100 where Double(player.propertyStringSnapshot("brightness") ?? "") != -30 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(Double(player.propertyStringSnapshot("brightness") ?? ""), -30)
        withExtendedLifetime(view) {}
    }
}
