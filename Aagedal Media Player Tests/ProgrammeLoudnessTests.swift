// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class ProgrammeLoudnessTests: XCTestCase {
    private var files: [URL] = []

    override func tearDown() async throws {
        await MainActor.run {
            for file in files { try? FileManager.default.removeItem(at: file) }
            files.removeAll()
        }
        try await super.tearDown()
    }

    private func temporary(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("programme-\(UUID().uuidString).\(ext)")
        files.append(url)
        return url
    }

    private func streams(_ count: Int, channels: Int? = 1, rate: Int? = 48_000) -> [MediaMetadata.AudioStream] {
        (0..<count).map {
            MediaMetadata.AudioStream(index: $0 + 10, languageCode: nil, title: nil, codec: "pcm_f32le",
                codecLongName: nil, profile: nil, sampleRate: rate, channels: channels,
                channelLayout: channels == 1 ? "mono" : nil, bitDepth: 32, bitRate: nil, isDefault: false)
        }
    }

    func testMappingRejectsDuplicateMissingNonMonoAndUnknownChannels() throws {
        let invalid = [[], [0], [0, 1, 2], [0, 0], [-1, 1], [0, 8]]
        for indices in invalid {
            XCTAssertThrowsError(try ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: indices)
                .validate(audioStreams: streams(8)))
        }
        let mapping = ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [7, 2])
        try mapping.validate(audioStreams: streams(8))
        for count in [nil, 0, 2, 6] as [Int?] {
            XCTAssertThrowsError(try mapping.validate(audioStreams: streams(8, channels: count)))
        }
        for rate in [nil, 0, -1, Int.max] as [Int?] {
            XCTAssertThrowsError(try mapping.validate(audioStreams: streams(8, rate: rate)))
        }
        let decoded = try JSONDecoder().decode(ProgrammeLoudnessMapping.self, from: JSONEncoder().encode(mapping))
        XCTAssertEqual(decoded, mapping)
    }

    func testArgumentsUseExplicitRolesBoundedTimelineAndAudioOrdinals() throws {
        let mapping = ProgrammeLoudnessMapping(layout: .surround5Point1, audioStreamIndices: [7, 6, 5, 4, 3, 2])
        let range = try FFmpegService.LoudnessRange(start: 1.25, end: 3.75)
        let arguments = try FFmpegService.programmeLoudnessArguments(url: temporary("mov"), mapping: mapping,
            audioStreams: streams(8), duration: 4, range: range)
        let graph = arguments[try XCTUnwrap(arguments.firstIndex(of: "-filter_complex")) + 1]
        XCTAssertTrue(graph.contains("[0:a:7]aresample=48000:async=1:first_pts=0"))
        XCTAssertTrue(graph.contains("apad=whole_dur=3.75,atrim=start=1.25:end=3.75,asetpts=PTS-STARTPTS"))
        XCTAssertTrue(graph.contains("channel_layout=5.1(side):map=0.0-FL|1.0-FR|2.0-FC|3.0-LFE|4.0-SL|5.0-SR"))
        XCTAssertFalse(graph.contains("amix"))
        XCTAssertFalse(graph.contains("[0:a:0]"))
        XCTAssertFalse(graph.contains("[0:a:17]"), "Mapping uses audio ordinals, not metadata absolute indices")
        for duration in [nil, 0, -1, .nan, .infinity] as [Double?] {
            XCTAssertThrowsError(try FFmpegService.programmeLoudnessArguments(url: temporary("mov"), mapping: mapping,
                audioStreams: streams(8), duration: duration))
        }
        XCTAssertThrowsError(try FFmpegService.programmeLoudnessArguments(url: temporary("mov"), mapping: mapping,
            audioStreams: streams(8), duration: 3, range: range))
    }

    func testStereoInEightMonoTracksMatchesIndependentStereoIncludingOppositePolarity() async throws {
        for trailingGain in [0.0, 10.0] {
            let gains = [1.0, -1.0] + [Double](repeating: trailingGain, count: 6)
            let url = try await monoContainer(gains: gains)
            let result = try await FFmpegService.analyzeProgrammeLUFS(url: url,
                mapping: ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [0, 1]),
                audioStreams: streams(8), duration: 4)
            let reference = try tone(gains: [1, -1], mask: 3)
            let measured = try await FFmpegService.analyzeLUFS(url: reference, audioStreamIndex: 0)
            XCTAssertEqual(result.loudness.integratedLoudness, -23, accuracy: 0.1)
            XCTAssertEqual(result.loudness.integratedLoudness, measured.integratedLoudness, accuracy: 0.1)
            XCTAssertEqual(result.loudness.truePeak, -23, accuracy: 0.1)
            XCTAssertNil(result.loudness.analysisRange)
        }
    }

    func testRealMetadataAndControllerMeasureStereoFromEightMonoTracksAfterVideoStream() async throws {
        let url = try await monoContainer(gains: [1, -1, 0, 0, 0, 0, 0, 0], includeVideo: true)
        let metadata = try await MetadataService.shared.metadata(for: url)
        XCTAssertEqual(metadata.videoStreams.count, 1)
        XCTAssertEqual(metadata.audioStreams.count, 8)
        XCTAssertTrue(metadata.audioStreams.allSatisfy { $0.channels == 1 })
        XCTAssertEqual(metadata.audioStreams.compactMap(\.index), Array(0..<8),
                       "The metadata library uses audio-relative indices even when video precedes audio")
        let duration = try XCTUnwrap(metadata.duration)
        XCTAssertEqual(duration, 4, accuracy: 0.01)
        let controller = ProgrammeLoudnessController()
        defer { controller.cancel(resetResult: true) }
        controller.configure(url: url, audioStreams: metadata.audioStreams)
        XCTAssertEqual(controller.mapping?.audioStreamIndices, [0, 1])
        XCTAssertEqual(controller.monoStreamIndices, Array(0..<8))
        XCTAssertNil(controller.mappingError)
        controller.measure(duration: duration, range: nil)
        let deadline = ContinuousClock.now + .seconds(10)
        while controller.isAnalyzing && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(controller.isAnalyzing, "Programme analysis did not finish")
        XCTAssertNil(controller.error)
        let result = try XCTUnwrap(controller.result)
        XCTAssertEqual(result.mapping.audioStreamIndices, [0, 1])
        XCTAssertEqual(result.loudness.integratedLoudness, -23, accuracy: 0.1)
        XCTAssertEqual(result.loudness.truePeak, -23, accuracy: 0.1)
        let json = try MetadataInspectorView.metadataJSON(metadata: metadata, lufsResults: [:], programmeLoudness: result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let programme = try XCTUnwrap(object["programmeLoudness"] as? [String: Any])
        let mapping = try XCTUnwrap(programme["mapping"] as? [String: Any])
        XCTAssertEqual(mapping["audioStreamIndices"] as? [Int], [0, 1])
        XCTAssertEqual(object["duration"] as? Double, duration)
    }

    func testSurroundRolesApplyLFEExclusionAndSurroundWeightingWithIndependentReference() async throws {
        let gains = [1.0, 0.5, 0.25, 10, 0.75, 0.4, 10, 10]
        let url = try await monoContainer(gains: gains)
        let mapping = ProgrammeLoudnessMapping(layout: .surround5Point1, audioStreamIndices: [0, 1, 2, 3, 4, 5])
        let range = try FFmpegService.LoudnessRange(start: 0.25, end: 3.75)
        let result = try await FFmpegService.analyzeProgrammeLUFS(url: url, mapping: mapping,
            audioStreams: streams(8), duration: 4, range: range)
        let reference = try tone(gains: Array(gains.prefix(6)), mask: 0x60F)
        let measured = try await FFmpegService.analyzeLUFS(url: reference, audioStreamIndex: 0, range: range)
        let energy = 1 + 0.25 + 0.0625 + 1.41 * (0.5625 + 0.16)
        XCTAssertEqual(result.loudness.integratedLoudness, -23 + 10 * log10(energy / 2), accuracy: 0.1)
        XCTAssertEqual(result.loudness.integratedLoudness, measured.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(result.loudness.truePeak, -3, accuracy: 0.1)
        XCTAssertEqual(result.loudness.analysisRange, range)
        let swapped = ProgrammeLoudnessMapping(layout: .surround5Point1, audioStreamIndices: [3, 1, 2, 0, 4, 5])
        let other = try await FFmpegService.analyzeProgrammeLUFS(url: url, mapping: swapped,
            audioStreams: streams(8), duration: 4, range: range)
        XCTAssertGreaterThan(other.loudness.integratedLoudness, result.loudness.integratedLoudness + 15)
        XCTAssertEqual(other.loudness.truePeak, result.loudness.truePeak, accuracy: 0.1)
    }

    func testUnequalDurationsAndDelayedChannelsKeepFileTimeline() async throws {
        let long = try tone(gains: [1], seconds: 6)
        let short = try tone(gains: [1], seconds: 2)
        let container = temporary("mka")
        try await FFmpegService.run(arguments: ["-hide_banner", "-loglevel", "error", "-i", long.path,
            "-itsoffset", "2", "-i", short.path, "-map", "0:a", "-map", "1:a", "-c:a", "pcm_f32le", container.path])
        let mapping = ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [0, 1])
        for (start, expected) in [(0.25, -26.0), (2.25, -23.0), (4.25, -26.0)] {
            let range = try FFmpegService.LoudnessRange(start: start, end: start + 1.5)
            let result = try await FFmpegService.analyzeProgrammeLUFS(url: container, mapping: mapping,
                audioStreams: streams(2), duration: 6, range: range)
            XCTAssertEqual(result.loudness.integratedLoudness, expected, accuracy: 0.1, "Range starting \(start)")
            XCTAssertEqual(result.loudness.truePeak, -23, accuracy: 0.1)
        }
        // A nonzero container origin must be normalized once for the whole
        // file, retaining the second stream's relative two-second offset.
        let offset = temporary("mka")
        try await FFmpegService.run(arguments: ["-hide_banner", "-loglevel", "error", "-i", container.path,
            "-map", "0:a", "-c:a", "copy", "-output_ts_offset", "7", offset.path])
        let result = try await FFmpegService.analyzeProgrammeLUFS(url: offset, mapping: mapping,
            audioStreams: streams(2), duration: 6, range: FFmpegService.LoudnessRange(start: 2.25, end: 3.75))
        XCTAssertEqual(result.loudness.integratedLoudness, -23, accuracy: 0.1)
        // Reordering puts the short source first: join must still measure the
        // long source's tail instead of silently stopping at the shorter one.
        let reordered = try await FFmpegService.analyzeProgrammeLUFS(url: container,
            mapping: ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [1, 0]),
            audioStreams: streams(2), duration: 6, range: FFmpegService.LoudnessRange(start: 4.25, end: 5.75))
        XCTAssertEqual(reordered.loudness.integratedLoudness, -26, accuracy: 0.1)
    }

    func testMixedSampleRatesAndTrueSilence() async throws {
        let left = try tone(gains: [1], rate: 44_100)
        let right = try tone(gains: [-1], rate: 96_000)
        let url = temporary("mov")
        // This valid negative-polarity 96 kHz WAV triggers a bundled FFmpeg
        // MPEG-TS probing false positive. Exercise production signature-based
        // demuxer selection directly, as well as when muxing this fixture.
        let direct = try await FFmpegService.analyzeLUFS(url: right, audioStreamIndex: 0)
        XCTAssertEqual(direct.integratedLoudness, -26, accuracy: 0.1)
        XCTAssertEqual(direct.truePeak, -23, accuracy: 0.1)
        let leftArguments = try RIFXAudioDecoding.ffmpegInputArguments(for: left)
        let rightArguments = try RIFXAudioDecoding.ffmpegInputArguments(for: right)
        try await FFmpegService.run(arguments: ["-hide_banner", "-loglevel", "error"] + leftArguments +
            ["-i", left.path] + rightArguments +
            ["-i", right.path, "-map", "0:a", "-map", "1:a", "-c:a", "pcm_f32le", url.path])
        let mapping = ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [0, 1])
        let metadata = streams(1, rate: 44_100) + streams(1, rate: 96_000)
        let result = try await FFmpegService.analyzeProgrammeLUFS(url: url, mapping: mapping,
            audioStreams: metadata, duration: 4)
        XCTAssertEqual(result.loudness.integratedLoudness, -23, accuracy: 0.1)
        XCTAssertEqual(result.loudness.truePeak, -23, accuracy: 0.1)
        let silent = try await monoContainer(gains: [0, 0])
        let silence = try await FFmpegService.analyzeProgrammeLUFS(url: silent, mapping: mapping,
            audioStreams: streams(2), duration: 4)
        XCTAssertEqual(silence.loudness.truePeak, -.infinity)
    }

    func testCancellationAndMissingStreamDoNotPublishResults() async throws {
        let url = try await monoContainer(gains: [1, 1])
        let mapping = ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [0, 1])
        let task = Task { @MainActor in
            try await FFmpegService.analyzeProgrammeLUFS(url: url, mapping: mapping, audioStreams: streams(2), duration: 4)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled analysis returned a result") }
        catch { XCTAssertEqual(error as? FFmpegError, .cancelled) }
        let missing = ProgrammeLoudnessMapping(layout: .stereo, audioStreamIndices: [0, 2])
        do {
            _ = try await FFmpegService.analyzeProgrammeLUFS(url: url, mapping: missing, audioStreams: streams(3), duration: 4)
            XCTFail("Missing real stream returned a result")
        } catch FFmpegError.processFailed { }
        let malformed = temporary("mov")
        try Data("not audio".utf8).write(to: malformed)
        do {
            _ = try await FFmpegService.analyzeProgrammeLUFS(url: malformed, mapping: mapping,
                audioStreams: streams(2), duration: 4)
            XCTFail("Malformed input returned a result")
        } catch FFmpegError.processFailed { }
        let retry = try await FFmpegService.analyzeProgrammeLUFS(url: url, mapping: mapping, audioStreams: streams(2), duration: 4)
        XCTAssertEqual(retry.loudness.integratedLoudness, -23, accuracy: 0.1)
    }

    private func monoContainer(gains: [Double], includeVideo: Bool = false) async throws -> URL {
        var arguments = ["-hide_banner", "-loglevel", "error"]
        if includeVideo {
            arguments += ["-f", "lavfi", "-i", "color=c=black:s=16x16:r=1:d=4"]
        }
        for gain in gains {
            let source = try tone(gains: [gain])
            arguments += try RIFXAudioDecoding.ffmpegInputArguments(for: source) + ["-i", source.path]
        }
        if includeVideo { arguments += ["-map", "0:v:0", "-c:v", "mpeg4", "-q:v", "8"] }
        for index in gains.indices { arguments += ["-map", "\(index + (includeVideo ? 1 : 0)):a:0"] }
        let url = temporary("mov")
        try await FFmpegService.run(arguments: arguments + ["-c:a", "pcm_f32le", url.path])
        return url
    }

    /// Independent EBU -23 dBFS, 1 kHz float-PCM signal and WAV channel masks.
    /// FFmpeg only muxes the mono files and measures the resulting programme.
    private func tone(gains: [Double], seconds: Int = 4, mask: UInt32? = nil, rate: Int = 48_000) throws -> URL {
        let frames = seconds * rate
        let align = gains.count * 4
        let formatBytes = mask == nil ? 16 : 40
        var data = Data(capacity: 28 + formatBytes + frames * align)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(20 + formatBytes + frames * align))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(formatBytes))
        append(UInt16(mask == nil ? 3 : 0xFFFE))
        append(UInt16(gains.count))
        append(UInt32(rate)); append(UInt32(rate * align))
        append(UInt16(align)); append(UInt16(32))
        if let mask {
            append(UInt16(22)); append(UInt16(32)); append(mask)
            append(UInt32(3)); append(UInt16(0)); append(UInt16(0x10))
            data.append(contentsOf: [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])
        }
        data.append(contentsOf: "data".utf8)
        append(UInt32(frames * align))
        let amplitude = pow(10, -23.0 / 20)
        for frame in 0..<frames {
            let sample = amplitude * sin(2 * .pi * 1_000 * Double(frame) / Double(rate))
            for gain in gains { append(Float(sample * gain).bitPattern) }
        }
        let url = temporary("wav")
        try data.write(to: url)
        return url
    }
}
