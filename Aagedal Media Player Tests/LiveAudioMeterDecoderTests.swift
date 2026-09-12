// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class LiveAudioMeterDecoderTests: XCTestCase {
    func testArgumentsIdentifySourceAndDisableDecoderGainProcessing() throws {
        let request = try makeRequest(startFrame: 96)
        let arguments = LiveAudioMeterDecoder.arguments(
            for: request, inputAudioArguments: ["-f", "wav"]
        )

        XCTAssertEqual(arguments, [
            "-hide_banner", "-nostdin", "-loglevel", "error",
            "-ss", "0.002000000", "-readrate", "1", "-readrate_catchup", "1",
            "-drc_scale", "0", "-target_level", "0",
            "-f", "wav", "-i", "/tmp/live-meter-source.wav",
            "-map", "0:a:2", "-vn", "-sn", "-dn", "-map_metadata", "-1",
            "-c:a", "pcm_f32le", "-f", "f32le", "pipe:1",
        ])
        let inputIndex = try XCTUnwrap(arguments.firstIndex(of: "-i"))
        XCTAssertLessThan(try XCTUnwrap(arguments.firstIndex(of: "-readrate")), inputIndex)
        XCTAssertLessThan(try XCTUnwrap(arguments.firstIndex(of: "-readrate_catchup")), inputIndex)
        XCTAssertFalse(arguments.contains("-af"), "No normalization, volume, or rematrix filter is permitted")
        XCTAssertFalse(arguments.contains("-ar"), "The declared source rate must not be silently resampled")
        XCTAssertFalse(arguments.contains("-ac"), "The declared speaker layout must not be silently remixed")
    }

    func testRequestRejectsInvalidOrInconsistentIdentity() throws {
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .stereo)
        XCTAssertThrowsError(try LiveAudioMeterDecodeRequest(
            url: URL(fileURLWithPath: "/tmp/source.wav"), audioStreamOrderIndex: -1,
            format: format, startSourceFrame: 0, startSourceTime: 0
        )) { error in
            XCTAssertEqual(error as? LiveAudioMeterDecoder.Failure, .invalidAudioStreamOrderIndex(-1))
        }
        XCTAssertThrowsError(try LiveAudioMeterDecodeRequest(
            url: URL(fileURLWithPath: "/tmp/source.wav"), audioStreamOrderIndex: 0,
            format: format, startSourceFrame: 48_000, startSourceTime: 0.5
        )) { error in
            XCTAssertEqual(error as? LiveAudioMeterDecoder.Failure, .inconsistentStartPosition)
        }
    }

    func testArbitraryByteBoundariesMatchDirectDSPAndStayBounded() throws {
        let request = try makeRequest()
        let frames = 6_137
        let samples = (0..<frames).flatMap { frame -> [Float] in
            let sample = Float(0.2 * sin(2 * .pi * 997 * Double(frame) / 48_000))
            return [sample, -sample]
        }
        let expected = try directSnapshots(request: request, samples: samples)
        let received = SnapshotBox()
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request) { received.append($0) }
        let data = bytes(samples)
        let chunkSizes = [1, 7, 2, 19, 4, 511, 3, 8_193, 5, 64]
        var cursor = 0
        var chunkIndex = 0
        while cursor < data.count {
            let count = min(chunkSizes[chunkIndex % chunkSizes.count], data.count - cursor)
            try processor.consume(data.subdata(in: cursor..<(cursor + count)))
            XCTAssertLessThanOrEqual(processor.bufferedByteCount, processor.maximumBufferedByteCount)
            cursor += count
            chunkIndex += 1
        }
        _ = try processor.finish()

        XCTAssertEqual(received.values, expected)
        XCTAssertEqual(processor.maximumBufferedByteCount, 2_400 * 2 * MemoryLayout<Float>.size)
    }

    func testEOFPublishesFinalRevisionAndCannotFinishTwice() throws {
        let request = try makeRequest(startFrame: 240)
        let received = SnapshotBox()
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request) { received.append($0) }
        try processor.consume(bytes([Float](repeating: 0.25, count: 2_400 * 2)))
        let final = try XCTUnwrap(processor.finish())

        XCTAssertEqual(received.values.count, 2)
        XCTAssertFalse(received.values[0].isFinal)
        XCTAssertTrue(final.isFinal)
        XCTAssertEqual(final.endFrame, 2_640)
        XCTAssertEqual(final.endFrame, received.values[0].endFrame)
        XCTAssertThrowsError(try processor.finish()) { error in
            XCTAssertEqual(error as? LiveAudioMeterDecoder.Failure, .alreadyFinished)
        }
    }

    func testEmptyEOFDoesNotInventSamples() throws {
        let request = try makeRequest()
        let received = SnapshotBox()
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request) { received.append($0) }
        XCTAssertNil(try processor.finish())
        XCTAssertTrue(received.values.isEmpty)
    }

    func testTruncatedPCMAtEOFIsActionable() throws {
        let request = try makeRequest()
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request) { _ in }
        try processor.consume(Data(repeating: 0, count: 7))
        XCTAssertThrowsError(try processor.finish()) { error in
            let failure = error as? LiveAudioMeterDecoder.Failure
            XCTAssertEqual(failure, .truncatedPCM(frameByteCount: 8, trailingByteCount: 7))
            XCTAssertTrue(failure?.localizedDescription.contains("trailing PCM") == true)
        }
    }

    func testMalformedNonFinitePCMReportsDSPFailure() throws {
        let request = try makeRequest()
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request) { _ in }
        try processor.consume(bytes([.nan, 0]))
        XCTAssertThrowsError(try processor.finish()) { error in
            XCTAssertEqual(error as? LiveAudioMeterDecoder.Failure, .dsp(.nonFinitePCM))
            XCTAssertTrue(error.localizedDescription.contains("DSP rejected"))
        }
    }

    func testDSPPositionFailurePropagatesWithoutPartialOutput() throws {
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .stereo)
        let start = Int64.max - 1
        let request = try LiveAudioMeterDecodeRequest(
            url: URL(fileURLWithPath: "/tmp/source.wav"), audioStreamOrderIndex: 0,
            format: format, startSourceFrame: start,
            startSourceTime: Double(start) / Double(format.sampleRate)
        )
        let received = SnapshotBox()
        let processor = try LiveAudioMeterPCMStreamProcessor(request: request) { received.append($0) }
        try processor.consume(bytes([0, 0, 0, 0]))
        XCTAssertThrowsError(try processor.finish()) { error in
            XCTAssertEqual(error as? LiveAudioMeterDecoder.Failure, .dsp(.invalidPosition))
        }
        XCTAssertTrue(received.values.isEmpty)
    }

    func testBundledDecoderStreamsPCMAndReturnsVersionedProvenance() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-meter-decoder-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let frameCount = 48_000
        let samples = (0..<frameCount).flatMap { frame -> [Float] in
            let value = Float(0.1 * sin(2 * .pi * 1_000 * Double(frame) / 48_000))
            return [value, value]
        }
        try float32Wave(samples: samples, channels: 2, sampleRate: 48_000).write(to: url)
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .stereo)
        let request = try LiveAudioMeterDecodeRequest(
            url: url, audioStreamOrderIndex: 0, format: format,
            startSourceFrame: 0, startSourceTime: 0
        )
        let received = SnapshotBox()

        let clock = ContinuousClock()
        let started = clock.now
        let completion = try await LiveAudioMeterDecoder.decode(request) { received.append($0) }
        let elapsed = started.duration(to: clock.now)

        XCTAssertTrue(completion.provenance.decoderVersion.hasPrefix("ffmpeg version "))
        XCTAssertEqual(completion.provenance.request, request)
        XCTAssertEqual(completion.provenance.sampleFormat, "f32le")
        XCTAssertTrue(completion.provenance.dynamicRangeCompressionDisabled)
        XCTAssertTrue(completion.provenance.codecNormalizationDisabled)
        XCTAssertEqual(completion.finalSnapshot?.endFrame, Int64(frameCount))
        XCTAssertTrue(completion.finalSnapshot?.isFinal == true)
        XCTAssertEqual(received.values.filter(\.isFinal).count, 1)
        XCTAssertGreaterThanOrEqual(
            elapsed, .milliseconds(500),
            "A one-second source must not be drained materially faster than forward 1x playback"
        )
    }

    private func makeRequest(startFrame: Int64 = 0) throws -> LiveAudioMeterDecodeRequest {
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .stereo)
        return try LiveAudioMeterDecodeRequest(
            url: URL(fileURLWithPath: "/tmp/live-meter-source.wav"),
            audioStreamOrderIndex: 2, format: format, startSourceFrame: startFrame,
            startSourceTime: Double(startFrame) / Double(format.sampleRate)
        )
    }

    private func directSnapshots(
        request: LiveAudioMeterDecodeRequest, samples: [Float]
    ) throws -> [LiveAudioMeterSnapshot] {
        var meter = try LiveAudioMeterDSP(format: request.format, startFrame: request.startSourceFrame)
        var output = try meter.process(samples, startFrame: request.startSourceFrame)
        if let final = try meter.finish() { output.append(final) }
        return output
    }

    private func bytes(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Float>.size)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func float32Wave(samples: [Float], channels: Int, sampleRate: Int) -> Data {
        let pcm = bytes(samples)
        var data = Data()
        func appendASCII(_ value: String) { data.append(contentsOf: value.utf8) }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        appendASCII("RIFF")
        append32(UInt32(36 + pcm.count))
        appendASCII("WAVEfmt ")
        append32(16)
        append16(3) // IEEE Float
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * channels * MemoryLayout<Float>.size))
        append16(UInt16(channels * MemoryLayout<Float>.size))
        append16(32)
        appendASCII("data")
        append32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [LiveAudioMeterSnapshot] = []

        var values: [LiveAudioMeterSnapshot] { lock.withLock { storage } }
        func append(_ snapshot: LiveAudioMeterSnapshot) { lock.withLock { storage.append(snapshot) } }
    }
}
