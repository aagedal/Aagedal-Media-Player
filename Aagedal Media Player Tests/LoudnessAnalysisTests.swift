// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LoudnessAnalysisTests: XCTestCase {
    // Independently synthesize the specified PCM; FFmpeg is only the meter under test.
    // EBU Tech 3341 (2023), Table 1: https://tech.ebu.ch/docs/tech/tech3341.pdf
    func testEBUAbsoluteStereoCalibrationReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        for level in [-23.0, -33.0] {
            let url = try writeReferenceTone(segments: [(20, pow(10, level / 20))])
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTAssertEqual(result.integratedLoudness, level, accuracy: 0.1, "EBU cases 1 and 2")
            XCTAssertEqual(result.truePeak, level, accuracy: 0.1)
        }
    }

    func testEBUAbsoluteAndRelativeGatingReference() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // Case 4: both the below-absolute-gate and below-relative-gate sections
        // must be excluded from the integrated result.
        let url = try writeReferenceTone(segments: [
            (10, pow(10, -72.0 / 20)), (10, pow(10, -36.0 / 20)),
            (60, pow(10, -23.0 / 20)),
            (10, pow(10, -36.0 / 20)), (10, pow(10, -72.0 / 20)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        XCTAssertEqual(result.integratedLoudness, -23, accuracy: 0.1, "EBU case 4")
    }

    func testEBUPhaseSensitiveTruePeakReferences() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        // Cases 15–19. Case 16 has a sample peak near −9 dBFS but a true peak
        // near −6 dBTP; case 19's unclipped samples reconstruct above full scale.
        let cases: [(divisor: Double, phase: Double, amplitude: Double, expected: Double)] = [
            (4, 0, 0.5, -6), (4, 45, 0.5, -6), (6, 60, 0.5, -6),
            (8, 67.5, 0.5, -6), (4, 45, 1.41, 3),
        ]
        for (index, reference) in cases.enumerated() {
            let url = try writeReferenceTone(
                segments: [(2, reference.amplitude)], frequency: 48_000 / reference.divisor,
                phase: reference.phase * .pi / 180, fadeSeconds: 0.01
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTAssertGreaterThanOrEqual(result.truePeak, reference.expected - 0.4, "EBU case \(index + 15)")
            XCTAssertLessThanOrEqual(result.truePeak, reference.expected + 0.2, "EBU case \(index + 15)")
        }
    }

    /// Little-endian stereo IEEE Float32 WAV, with identical in-phase channels.
    /// Float PCM preserves the reference levels without integer quantization.
    private func writeReferenceTone(
        segments: [(seconds: Int, amplitude: Double)], frequency: Double = 1_000,
        phase: Double = 0, fadeSeconds: Double = 0
    ) throws -> URL {
        let sampleRate = 48_000
        let frames = segments.reduce(0) { $0 + $1.seconds * sampleRate }
        let payloadBytes = frames * 2 * MemoryLayout<Float>.size
        var data = Data(capacity: 44 + payloadBytes)
        func appendInteger<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        appendInteger(UInt32(36 + payloadBytes))
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendInteger(UInt32(16))
        appendInteger(UInt16(3)) // WAVE_FORMAT_IEEE_FLOAT
        appendInteger(UInt16(2))
        appendInteger(UInt32(sampleRate))
        appendInteger(UInt32(sampleRate * 8))
        appendInteger(UInt16(8))
        appendInteger(UInt16(32))
        data.append(contentsOf: "data".utf8)
        appendInteger(UInt32(payloadBytes))
        let fadeFrames = Int(fadeSeconds * Double(sampleRate))
        var frame = 0
        for segment in segments {
            for _ in 0..<(segment.seconds * sampleRate) {
                let envelope = fadeFrames == 0 ? 1 : min(
                    1, Double(min(frame, frames - 1 - frame)) / Double(fadeFrames)
                )
                let sample = Float(segment.amplitude * envelope * sin(
                    2 * .pi * frequency * Double(frame) / Double(sampleRate) + phase
                ))
                appendInteger(sample.bitPattern)
                appendInteger(sample.bitPattern)
                frame += 1
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ebu-reference-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

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

    func testMultichannelStreamWeightingAndIndependentTrackSelection() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("multichannel-loudness-\(UUID().uuidString).mka")
        defer { try? FileManager.default.removeItem(at: url) }
        // All six channels have the same samples. R128 sums three front
        // channels and two surrounds weighted by 1.41, excluding the LFE.
        // The third track is 20 dB quieter to catch accidental stream mixing.
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:sample_rate=48000:duration=3",
            "-filter_complex", "[0:a]asplit=3[mono][surround][quiet];[surround]pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0[six];[quiet]volume=0.1[low]",
            "-map", "[mono]", "-map", "[six]", "-map", "[low]",
            "-c:a", "pcm_s24le", "-y", url.path,
        ])
        let mono = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        let surround = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 1)
        let quiet = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 2)
        XCTAssertEqual(surround.integratedLoudness - mono.integratedLoudness, 10 * log10(3 + 2 * 1.41), accuracy: 0.2)
        XCTAssertEqual(surround.truePeak, mono.truePeak, accuracy: 0.1, "True peak is a channel maximum, not the summed loudness")
        XCTAssertEqual(mono.integratedLoudness - quiet.integratedLoudness, 20, accuracy: 0.2)
        XCTAssertEqual(mono.truePeak - quiet.truePeak, 20, accuracy: 0.2)
        XCTAssertNil(surround.analysisRange)

        let range = try FFmpegService.LoudnessRange(start: 0.25, end: 2.75)
        let selected = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 1, range: range)
        XCTAssertEqual(selected.integratedLoudness, surround.integratedLoudness, accuracy: 0.1)
        XCTAssertEqual(selected.truePeak, surround.truePeak, accuracy: 0.1)
        XCTAssertEqual(selected.analysisRange, range)
    }

    func testMalformedAudioAndMissingStreamFailWithoutPublishingMeasurements() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("This is not a WAV file".utf8).write(to: url)
        do {
            _ = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
            XCTFail("Malformed audio must fail instead of returning a silence summary")
        } catch FFmpegError.processFailed(let message) {
            XCTAssertFalse(message.isEmpty)
        }

        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=1", "-y", url.path,
        ])
        do {
            _ = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 1)
            XCTFail("A missing stream must not fall back to a different audio track")
        } catch FFmpegError.processFailed(let message) {
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testCancelledAnalysisReturnsCancellationAndSubsequentAnalysisSucceeds() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cancelled-loudness-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=1", "-y", url.path,
        ])
        // Main-actor serialization makes cancellation-before-start deterministic.
        let task = Task { @MainActor in
            try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled analysis must never return a measurement")
        } catch {
            XCTAssertEqual(error as? FFmpegError, .cancelled)
        }
        let retry = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0)
        XCTAssertTrue(retry.integratedLoudness.isFinite)
        XCTAssertTrue(retry.truePeak.isFinite)
    }

    func testEmptySelectionsBeyondEOFAndBeforeDelayedStreamAreRejected() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-loudness-\(UUID().uuidString).mka")
        defer { try? FileManager.default.removeItem(at: url) }
        // The file spans four seconds, but the second stream starts at second
        // two. A valid interval in the media timeline can contain no samples
        // for that stream. The first stream is real digital silence.
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "anullsrc=r=48000:cl=mono:d=4", "-itsoffset", "2", "-f", "lavfi",
            "-i", "sine=frequency=1000:sample_rate=48000:duration=2",
            "-map", "0:a:0", "-map", "1:a:0", "-c:a", "pcm_s24le", "-y", url.path,
        ])
        let beforeAudio = try FFmpegService.LoudnessRange(start: 0.25, end: 1.25)
        let beyondEOF = try FFmpegService.LoudnessRange(start: 8, end: 10)
        for (stream, range) in [(0, beyondEOF), (1, beforeAudio)] {
            do {
                _ = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: stream, range: range)
                XCTFail("An interval without decoded samples must not return FFmpeg's default summary")
            } catch {
                XCTAssertEqual(error as? FFmpegError, .loudnessNoSamples)
            }
        }
        let silence = try await FFmpegService.analyzeLUFS(url: url, audioStreamIndex: 0, range: beforeAudio)
        XCTAssertEqual(silence.truePeak, -.infinity, "Actual silence has samples and must remain measurable")
        let audible = try await FFmpegService.analyzeLUFS(
            url: url, audioStreamIndex: 1,
            range: FFmpegService.LoudnessRange(start: 2.25, end: 3.25)
        )
        XCTAssertTrue(audible.truePeak.isFinite)
    }

}
