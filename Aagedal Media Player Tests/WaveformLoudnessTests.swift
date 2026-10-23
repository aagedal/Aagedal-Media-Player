// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class WaveformLoudnessTests: XCTestCase {
    func testRangeHistoryUsesWholeFileClockAndIndependentWindows() throws {
        let range = try FFmpegService.LoudnessRange(start: 20, end: 30)
        let samples: [FFmpegService.LoudnessSample] = [
            .init(seconds: 20.4, momentary: -35, shortTerm: nil),
            .init(seconds: 23, momentary: -14, shortTerm: -21),
            .init(seconds: 30, momentary: -7, shortTerm: -14)
        ]
        let momentary = WaveformLoudnessGeometry.segments(samples: samples, duration: 100, range: range, shortTerm: false)
        let shortTerm = WaveformLoudnessGeometry.segments(samples: samples, duration: 100, range: range, shortTerm: true)
        XCTAssertEqual(momentary.count, 1)
        XCTAssertEqual(momentary[0].map(\.x), [0.204, 0.23, 0.3])
        XCTAssertEqual(momentary[0][0].y, 0.5)
        XCTAssertEqual(shortTerm[0].map(\.x), [0.23, 0.3])
        XCTAssertEqual(shortTerm[0][0].y, 0.3, accuracy: 0.000001)
    }

    func testMissingOrInvalidSamplesBreakLinesAndLevelsClipToFixedScale() {
        let samples: [FFmpegService.LoudnessSample] = [
            .init(seconds: 1, momentary: -100, shortTerm: nil),
            .init(seconds: 2, momentary: nil, shortTerm: nil),
            .init(seconds: 3, momentary: 5, shortTerm: nil),
            .init(seconds: 3, momentary: -20, shortTerm: nil), // duplicate
            .init(seconds: 4, momentary: .infinity, shortTerm: nil),
            .init(seconds: .nan, momentary: -10, shortTerm: nil),
            .init(seconds: 5, momentary: -35, shortTerm: nil),
            .init(seconds: 11, momentary: -10, shortTerm: nil) // beyond file
        ]
        let segments = WaveformLoudnessGeometry.segments(samples: samples, duration: 10, range: nil, shortTerm: false)
        XCTAssertEqual(segments.map(\.count), [1, 1, 1])
        XCTAssertEqual(segments.flatMap { $0 }.map(\.x), [0.1, 0.3, 0.5])
        XCTAssertEqual(segments.flatMap { $0 }.map(\.y), [1, 0, 0.5])
        for duration in [0, -1, Double.nan, .infinity] {
            XCTAssertTrue(WaveformLoudnessGeometry.segments(samples: samples, duration: duration, range: nil, shortTerm: false).isEmpty)
        }
    }

    func testRangeDoesNotPlotUnmeasuredAudio() throws {
        let range = try FFmpegService.LoudnessRange(start: 2, end: 4)
        let samples = (0...10).map { FFmpegService.LoudnessSample(seconds: Double($0), momentary: -23, shortTerm: -24) }
        let segments = WaveformLoudnessGeometry.segments(samples: samples, duration: 10, range: range, shortTerm: false)
        XCTAssertEqual(segments.flatMap { $0 }.map(\.x), [0.2, 0.3, 0.4])
    }

    func testPlayerKeepsResultsByAudioOrdinalAndRejectsReplacementIdentity() throws {
        let player = PlayerController()
        var item = makeItem()
        player.mediaItem = item
        player.recordWaveformLoudness(result(), streamIndex: 1, mediaID: item.id)
        XCTAssertNil(player.waveformLoudnessResults[0])
        XCTAssertEqual(player.waveformLoudnessResults[1]?.integratedLoudness, -23)
        player.recordWaveformLoudness(result(), streamIndex: 7, mediaID: item.id)
        XCTAssertEqual(player.waveformLoudnessResults.count, 1)
        item.durationSeconds = 120 // enrichment keeps the media identity
        player.mediaItem = item
        XCTAssertNotNil(player.waveformLoudnessResults[1])
        let replacement = makeItem() // same URL, new playback identity
        player.mediaItem = replacement
        XCTAssertTrue(player.waveformLoudnessResults.isEmpty)
        player.recordWaveformLoudness(result(), streamIndex: 1, mediaID: item.id)
        XCTAssertTrue(player.waveformLoudnessResults.isEmpty)
        let programme = ProgrammeLoudnessResult(mapping: .init(layout: .stereo, audioStreamIndices: [0, 1]), loudness: result())
        player.recordWaveformProgrammeLoudness(programme, mediaID: replacement.id)
        XCTAssertNotNil(player.waveformProgrammeLoudness)
        XCTAssertTrue(player.waveformUsesProgrammeLoudness)
        player.recordWaveformLoudness(result(), streamIndex: 0, mediaID: replacement.id)
        XCTAssertFalse(player.waveformUsesProgrammeLoudness)
        XCTAssertNotNil(player.waveformProgrammeLoudness, "Both completed sources remain selectable")
        player.mediaItem = nil
        XCTAssertNil(player.waveformProgrammeLoudness)
        XCTAssertTrue(player.waveformLoudnessResults.isEmpty)
        player.teardown()
    }

    func testRenderedTracesStayInAnalyzedRangeAndUseDistinctLineColors() throws {
        var measured = result()
        measured.analysisRange = try .init(start: 20, end: 60)
        measured.samples = [
            .init(seconds: 20, momentary: -35, shortTerm: -14),
            .init(seconds: 60, momentary: -35, shortTerm: -14)
        ]
        let view = WaveformLoudnessOverlay(result: measured, duration: 100, title: "Track 1 · In–Out")
            .frame(width: 800, height: 200).background(.black)
        let renderer = ImageRenderer(content: view)
        let image = try XCTUnwrap(renderer.cgImage)
        let pixels = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 300, y: 100))
        XCTAssertGreaterThan(pixels.greenComponent, 0.4)
        XCTAssertGreaterThan(pixels.blueComponent, 0.4)
        let bitmap = NSBitmapImageRep(cgImage: image)
        XCTAssertTrue((180...470).contains { x in
            guard let color = bitmap.colorAt(x: x, y: 40) else { return false }
            return color.redComponent > 0.4 && color.greenComponent > 0.4 && color.blueComponent < 0.2
        }, "Short-term trace must be yellow and distinct from the cyan momentary trace")
        let outside = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 600, y: 100))
        XCTAssertLessThan(outside.greenComponent, 0.1, "A range graph must not stretch across the whole waveform")
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero))
        attachment.name = "Waveform LUFS range overlay"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["WAVEFORM_LUFS_PREVIEW_DIR"] {
            let destination = URL(fileURLWithPath: directory).appendingPathComponent("waveform-lufs-overlay.png")
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: destination)
        }
    }

    func testHistoryLessResultsDoNotHideThePlottableSource() {
        let player = PlayerController()
        defer { player.teardown() }
        let item = makeItem()
        player.mediaItem = item
        var empty = result()
        empty.samples = []
        player.recordWaveformLoudness(result(), streamIndex: 0, mediaID: item.id)
        player.recordWaveformProgrammeLoudness(.init(
            mapping: .init(layout: .stereo, audioStreamIndices: [0, 1]), loudness: empty), mediaID: item.id)
        XCTAssertNotNil(player.waveformProgrammeLoudness)
        XCTAssertFalse(player.waveformUsesProgrammeLoudness, "An empty programme history must not hide the track graph")
        player.recordWaveformProgrammeLoudness(.init(
            mapping: .init(layout: .stereo, audioStreamIndices: [0, 1]), loudness: result()), mediaID: item.id)
        XCTAssertTrue(player.waveformUsesProgrammeLoudness)
        player.recordWaveformLoudness(empty, streamIndex: 1, mediaID: item.id)
        XCTAssertTrue(player.waveformUsesProgrammeLoudness, "An empty track history must not hide the programme graph")
        player.mediaItem = makeItem()
        XCTAssertFalse(player.waveformUsesProgrammeLoudness, "New media starts on the track graph")
    }

    func testWaveformCompositeKeepsGraphVisibleAboveChannelImages() throws {
        let player = PlayerController()
        let item = makeItem()
        player.mediaItem = item
        var measured = result()
        measured.samples = (1...99).map { second in
            .init(seconds: Double(second), momentary: -35 + 7 * sin(Double(second) / 8),
                  shortTerm: second >= 3 ? -24 + 4 * sin(Double(second) / 12) : nil)
        }
        player.recordWaveformProgrammeLoudness(.init(
            mapping: .init(layout: .stereo, audioStreamIndices: [0, 1]), loudness: measured), mediaID: item.id)
        let generator = AudioWaveformGenerator()
        defer { generator.cancel(); player.teardown() }
        let waveform = NSImage(size: NSSize(width: 800, height: 100))
        waveform.lockFocus()
        NSColor.systemPurple.withAlphaComponent(0.65).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for x in 0..<800 {
            let level = 8 + 30 * abs(sin(Double(x) / 29) * cos(Double(x) / 7))
            path.move(to: CGPoint(x: Double(x), y: 50 - level))
            path.line(to: CGPoint(x: Double(x), y: 50 + level))
        }
        path.stroke()
        waveform.unlockFocus()
        generator.channelImages = [waveform, waveform]
        generator.channelLabels = ["Left", "Right"]
        let renderer = ImageRenderer(content: AudioWaveformView(generator: generator, controller: player, isOverlay: true)
            .frame(width: 800, height: 240))
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let cyanPixels = (60..<210).reduce(0) { count, y in
            count + (80..<720).filter { x in
                guard let color = bitmap.colorAt(x: x, y: y) else { return false }
                return color.greenComponent > 0.6 && color.blueComponent > 0.6 && color.redComponent < 0.3
            }.count
        }
        XCTAssertGreaterThan(cyanPixels, 100, "Momentary graph must draw above the actual waveform view")
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero))
        attachment.name = "LUFS above stereo waveform"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["WAVEFORM_LUFS_PREVIEW_DIR"] {
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("waveform-lufs-composite.png"))
        }
    }

    private func result() -> FFmpegService.LUFSResult {
        .init(integratedLoudness: -23, loudnessRange: 4, truePeak: -1,
              samples: [.init(seconds: 1, momentary: -23, shortTerm: nil)])
    }

    private func makeItem() -> MediaItem {
        let streams = (0...1).map { index in
            MediaMetadata.AudioStream(index: index + 10, languageCode: nil, title: nil, codec: "pcm_s24le",
                codecLongName: nil, profile: nil, sampleRate: 48_000, channels: 1, channelLayout: "mono",
                bitDepth: 24, bitRate: nil, isDefault: false)
        }
        let metadata = MediaMetadata(duration: 100, formatName: "wav", containerLongName: nil,
            sizeBytes: nil, bitRate: nil, timecode: nil, comment: nil, encoder: nil, frameCount: nil,
            videoStreams: [], audioStreams: streams, subtitleStreams: [], chapters: [])
        return MediaItem(url: URL(fileURLWithPath: "/tmp/waveform-lufs.wav"), name: "waveform-lufs.wav", size: 0,
                         durationSeconds: 100, hasVideoStream: false, metadata: metadata)
    }
}
