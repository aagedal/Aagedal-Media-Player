// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LoudnessAnalysisTests: XCTestCase {
    func testWholeFileKeepsStreamSelectionWithoutTrimming() throws {
        let arguments = try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media with spaces.wav"), audioStreamIndex: 2
        )
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "-map")) + 1], "0:a:2")
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "-af")) + 1], "ebur128=peak=true")
        XCTAssertTrue(arguments.contains("/tmp/media with spaces.wav"))
    }

    func testRangeTrimsSamplesBeforeLoudnessFilter() throws {
        let range = try FFmpegService.LoudnessRange(start: 1.125, end: 4.875)
        let arguments = try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media.wav"), audioStreamIndex: 0, range: range
        )
        let filter = arguments[try XCTUnwrap(arguments.firstIndex(of: "-af")) + 1]
        XCTAssertEqual(filter, "atrim=start=1.125:end=4.875,asetpts=PTS-STARTPTS,ebur128=peak=true")
        let limitIndex = try XCTUnwrap(arguments.firstIndex(of: "-t"))
        XCTAssertEqual(arguments[limitIndex + 1], "4.875")
        XCTAssertLessThan(limitIndex, try XCTUnwrap(arguments.firstIndex(of: "-i")), "Bound demuxing at the input so trailing material is not decoded")
        XCTAssertFalse(arguments.contains("-c"), "Range analysis must decode samples rather than stream-copy keyframes")
    }

    func testInvalidRangesAndStreamAreRejected() throws {
        for (start, end) in [(-1.0, 2.0), (2, 2), (3, 2), (.nan, 2), (0, .infinity), (-.infinity, 2)] {
            XCTAssertThrowsError(try FFmpegService.LoudnessRange(start: start, end: end)) {
                XCTAssertEqual($0 as? FFmpegError, .invalidLoudnessRange)
            }
        }
        XCTAssertThrowsError(try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media.wav"), audioStreamIndex: -1
        )) { XCTAssertEqual($0 as? FFmpegError, .invalidAudioStream) }

        let decoded = try JSONDecoder().decode(
            FFmpegService.LoudnessRange.self, from: Data(#"{"start":4,"end":2}"#.utf8)
        )
        XCTAssertThrowsError(try FFmpegService.loudnessArguments(
            url: URL(fileURLWithPath: "/tmp/media.wav"), audioStreamIndex: 0, range: decoded
        )) { XCTAssertEqual($0 as? FFmpegError, .invalidLoudnessRange) }
    }

    func testSelectedRangeMeasuresOnlyItsSamplesAndExportsBounds() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        // The second three seconds are 20 dB quieter. Non-integer boundaries
        // also exercise sample trimming independently of packet boundaries.
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:sample_rate=48000:duration=6",
            "-af", "volume=if(lt(t\\,3)\\,1\\,0.1):eval=frame", "-y", url.path,
        ])
        let loudRange = try FFmpegService.LoudnessRange(start: 0.25, end: 2.75)
        let quietRange = try FFmpegService.LoudnessRange(start: 3.25, end: 5.75)
        let loud = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: loudRange)
        let quiet = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: quietRange)
        XCTAssertEqual(loud.integratedLoudness - quiet.integratedLoudness, 20, accuracy: 0.2)
        XCTAssertEqual(loud.truePeak - quiet.truePeak, 20, accuracy: 0.2)
        XCTAssertEqual(quiet.analysisRange, quietRange)
        let decoded = try JSONDecoder().decode(FFmpegService.LUFSResult.self, from: JSONEncoder().encode(quiet))
        XCTAssertEqual(decoded.analysisRange, quietRange)

        // Container timestamps need not start at zero. Marker seconds still
        // address time relative to the file, rather than its raw packet PTS.
        let offsetURL = url.deletingPathExtension().appendingPathExtension("mka")
        defer { try? FileManager.default.removeItem(at: offsetURL) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-i", url.path,
            "-c:a", "copy", "-output_ts_offset", "7", "-y", offsetURL.path,
        ])
        let offsetQuiet = try await FFmpegService.analyzeLUFS(url: offsetURL, audioStreamIndex: 0, range: quietRange)
        XCTAssertEqual(offsetQuiet.integratedLoudness, quiet.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(offsetQuiet.truePeak, quiet.truePeak, accuracy: 0.1)

        let delayedURL = url.deletingPathExtension().appendingPathExtension("delayed.mka")
        defer { try? FileManager.default.removeItem(at: delayedURL) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-i", url.path,
            "-itsoffset", "1", "-i", url.path, "-map", "0:a:0", "-map", "1:a:0",
            "-c:a", "copy", "-y", delayedURL.path,
        ])
        // Stream 1's level drops at source second 4, not second 3. Resetting
        // each stream's initial timestamp before trimming would choose quiet audio.
        let delayedRange = try FFmpegService.LoudnessRange(start: 3.25, end: 3.75)
        let delayedLoud = try await FFmpegService.analyzeLUFS(url: delayedURL, audioStreamIndex: 1, range: delayedRange)
        XCTAssertEqual(delayedLoud.integratedLoudness, loud.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(delayedLoud.truePeak, loud.truePeak, accuracy: 0.1)

    }

    func testSilenceCanBeCopiedAsMetadataJSON() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "anullsrc=r=48000:cl=mono", "-t", "1", "-c:a", "alac", "-y", url.path,
        ])
        let range = try FFmpegService.LoudnessRange(start: 0, end: 1)
        let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: range)
        XCTAssertEqual(result.truePeak, -.infinity)
        let metadata = try await MetadataService.shared.metadata(for: url)
        let data = try MetadataInspectorView.metadataJSON(metadata: metadata, lufsResults: [0: result])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let streams = try XCTUnwrap(object["audioStreams"] as? [[String: Any]])
        let lufs = try XCTUnwrap(streams.first?["lufs"] as? [String: Any])
        XCTAssertEqual(lufs["truePeak"] as? String, "-Infinity")
        let bounds = try XCTUnwrap(lufs["analysisRange"] as? [String: Double])
        XCTAssertEqual(bounds["start"], 0)
        XCTAssertEqual(bounds["end"], 1)
    }

}
