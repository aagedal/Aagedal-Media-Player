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
            "-hide_banner", "-nostdin", "-nostats", "-loglevel", "error",
            "-ss", "0.000000000", "-accurate_seek",
            "-readrate", "1", "-readrate_catchup", "1",
            "-readrate_initial_burst", "0.002000000",
            "-drc_scale", "0", "-target_level", "0",
            "-f", "wav", "-i", "/tmp/live-meter-source.wav",
            "-map", "0:a:2", "-vn", "-sn", "-dn", "-map_metadata", "-1",
            "-af", "asettb=expr=1/sr,atrim=start_pts=96,asetpts=PTS-96",
            "-c:a", "pcm_f32le", "-f", "tee",
            "[f=f32le]pipe:1|[f=framecrc]pipe:2",
        ])
        let inputIndex = try XCTUnwrap(arguments.firstIndex(of: "-i"))
        XCTAssertLessThan(try XCTUnwrap(arguments.firstIndex(of: "-readrate")), inputIndex)
        XCTAssertLessThan(try XCTUnwrap(arguments.firstIndex(of: "-readrate_catchup")), inputIndex)
        let filterIndex = try XCTUnwrap(arguments.firstIndex(of: "-af"))
        XCTAssertFalse(arguments[filterIndex + 1].contains("volume"))
        XCTAssertFalse(arguments[filterIndex + 1].contains("pan"))
        XCTAssertFalse(arguments[filterIndex + 1].contains("channelmap"))
        XCTAssertFalse(arguments.contains("-ar"), "The declared source rate must not be silently resampled")
        XCTAssertFalse(arguments.contains("-ac"), "The declared speaker layout must not be silently remixed")
    }

    func testLongSeekUsesBoundedAccurateDecoderPreroll() throws {
        let request = try makeRequest(startFrame: 48_000 * 123)
        let arguments = LiveAudioMeterDecoder.arguments(for: request)
        let inputIndex = try XCTUnwrap(arguments.firstIndex(of: "-i"))
        let seekIndexes = arguments.indices.filter { arguments[$0] == "-ss" }

        XCTAssertEqual(seekIndexes.count, 1)
        XCTAssertEqual(arguments[seekIndexes[0] + 1], "122.000000000")
        XCTAssertLessThan(seekIndexes[0], inputIndex)
        let burstIndex = try XCTUnwrap(arguments.firstIndex(of: "-readrate_initial_burst"))
        XCTAssertEqual(arguments[burstIndex + 1], "1.000000000")
        let filterIndex = try XCTUnwrap(arguments.firstIndex(of: "-af"))
        XCTAssertEqual(
            arguments[filterIndex + 1],
            "asettb=expr=1/sr,atrim=start_pts=48000,asetpts=PTS-48000"
        )
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

    func testTimestampedProcessorVerifiesContiguousPacketsAcrossArbitraryChunks() throws {
        let request = try makeRequest()
        let received = SnapshotBox()
        let processor = try LiveAudioMeterTimestampedStreamProcessor(request: request) {
            received.append($0)
        }
        let first = bytes([Float](repeating: 0.1, count: 128 * 2))
        let second = bytes([Float](repeating: -0.2, count: 1_024 * 2))

        XCTAssertNil(processor.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(processor.consumeTimingLine("#sample_rate 0: 48000"))
        XCTAssertNil(processor.consumeTimingLine("unrelated ffmpeg diagnostic"))
        XCTAssertNil(processor.consumeTimingLine(frameCRCLine(
            pts: 0, frames: 128, data: first
        )))
        try processor.consumePCM(first.prefix(7))
        try processor.consumePCM(first.dropFirst(7) + second.prefix(13))
        XCTAssertNil(processor.consumeTimingLine(frameCRCLine(
            pts: 128, frames: 1_024, data: second
        )))
        try processor.consumePCM(second.dropFirst(13))
        processor.finishTiming()

        let (final, summary) = try processor.finish()
        XCTAssertEqual(summary, .init(packetCount: 2, frameCount: 1_152))
        XCTAssertEqual(final?.endFrame, 1_152)
        XCTAssertEqual(received.values.last?.endFrame, 1_152)
    }

    func testTimestampedProcessorNormalizesSubMillisecondPacketTimestampJitter() throws {
        let request = try makeRequest()
        let received = SnapshotBox()
        let processor = try LiveAudioMeterTimestampedStreamProcessor(request: request) {
            received.append($0)
        }
        let first = bytes([Float](repeating: 0.1, count: 128 * 2))
        let second = bytes([Float](repeating: 0.2, count: 128 * 2))
        let third = bytes([Float](repeating: 0.3, count: 128 * 2))

        XCTAssertNil(processor.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(processor.consumeTimingLine("#sample_rate 0: 48000"))
        XCTAssertNil(processor.consumeTimingLine(frameCRCLine(pts: 0, frames: 128, data: first)))
        // A real extracted stream reported this eight-frame overlap. It is
        // 0.167 ms at 48 kHz and reflects timestamp quantization, not missing PCM.
        XCTAssertNil(processor.consumeTimingLine(frameCRCLine(pts: 120, frames: 128, data: second)))
        XCTAssertNil(processor.consumeTimingLine(frameCRCLine(pts: 264, frames: 128, data: third)))
        try processor.consumePCM(first + second + third)
        processor.finishTiming()

        let (final, summary) = try processor.finish()
        XCTAssertEqual(summary, .init(packetCount: 3, frameCount: 384))
        XCTAssertEqual(final?.endFrame, 384)
        XCTAssertEqual(received.values.last?.endFrame, 384)
    }

    func testTimestampedProcessorRejectsMalformedGapAndChecksumMismatch() throws {
        let request = try makeRequest()
        let malformed = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertEqual(
            malformed.consumeTimingLine("0, NOPTS, NOPTS, 128, 1024, 0x00000000"),
            .malformedFrameTimestamp
        )

        let gap = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertNil(gap.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(gap.consumeTimingLine("#sample_rate 0: 48000"))
        let packet = bytes([Float](repeating: 0, count: 1_024 * 2))
        XCTAssertNil(gap.consumeTimingLine(frameCRCLine(pts: 0, frames: 1_024, data: packet)))
        XCTAssertEqual(
            gap.consumeTimingLine(frameCRCLine(pts: 1_073, frames: 1_024, data: packet)),
            .timestampDiscontinuity(expectedFrame: 1_024, actualFrame: 1_073)
        )

        let checksum = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertNil(checksum.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(checksum.consumeTimingLine("#sample_rate 0: 48000"))
        XCTAssertNil(checksum.consumeTimingLine(
            "0, 0, 0, 1024, \(packet.count), 0x00000001"
        ))
        XCTAssertThrowsError(try checksum.consumePCM(packet)) { error in
            guard case .timestampChecksumMismatch = error as? LiveAudioMeterDecoder.Failure else {
                return XCTFail("Expected checksum mismatch, got \(error)")
            }
        }
    }

    func testTimestampedProcessorRequiresHeadersEvenForEmptyStream() throws {
        let request = try makeRequest()
        let missingHeaders = try LiveAudioMeterTimestampedStreamProcessor(
            request: request
        ) { _ in }
        missingHeaders.finishTiming()
        XCTAssertThrowsError(try missingHeaders.finish()) { error in
            XCTAssertEqual(
                error as? LiveAudioMeterDecoder.Failure,
                .missingFrameTimestampHeader
            )
        }

        let headered = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertNil(headered.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(headered.consumeTimingLine("#sample_rate 0: 48000"))
        headered.finishTiming()
        let (final, summary) = try headered.finish()
        XCTAssertNil(final)
        XCTAssertEqual(summary, .init(packetCount: 0, frameCount: 0))
    }

    func testTimestampedProcessorSupportsAllRatesAndMultichannelPacketSizes() throws {
        for (sampleRate, layout) in [
            (44_100, LiveAudioMeterFormat.Layout.surround5Point1),
            (96_000, LiveAudioMeterFormat.Layout.surround7Point1),
        ] {
            let format = try LiveAudioMeterFormat(sampleRate: sampleRate, layout: layout)
            let request = try LiveAudioMeterDecodeRequest(
                url: URL(fileURLWithPath: "/tmp/source.wav"),
                audioStreamOrderIndex: 0, format: format,
                startSourceFrame: 0, startSourceTime: 0
            )
            let processor = try LiveAudioMeterTimestampedStreamProcessor(
                request: request
            ) { _ in }
            let packet = bytes([Float](repeating: 0, count: 128 * format.channelCount))
            XCTAssertNil(processor.consumeTimingLine("#tb 0: 1/\(sampleRate)"))
            XCTAssertNil(processor.consumeTimingLine("#sample_rate 0: \(sampleRate)"))
            XCTAssertNil(processor.consumeTimingLine(
                frameCRCLine(pts: 0, frames: 128, data: packet)
            ))
            try processor.consumePCM(packet)
            processor.finishTiming()
            let (_, summary) = try processor.finish()
            XCTAssertEqual(summary, .init(packetCount: 1, frameCount: 128))
        }
    }

    func testTimestampedProcessorCancellationWakesBothUnmatchedSides() async throws {
        let request = try makeRequest()
        let pcmFirst = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        let oversizedCallback = bytes([Float](repeating: 0, count: (12_000 + 1) * 2))
        let pcmTask = Task.detached { try pcmFirst.consumePCM(oversizedCallback) }
        try await Task.sleep(for: .milliseconds(40))
        pcmFirst.cancel()
        do {
            try await pcmTask.value
            XCTFail("Expected cancellation to wake PCM waiting for timestamps")
        } catch let failure as LiveAudioMeterDecoder.Failure {
            XCTAssertEqual(failure, .cancelled)
        }

        let timingFirst = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertNil(timingFirst.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(timingFirst.consumeTimingLine("#sample_rate 0: 48000"))
        let fullBound = bytes([Float](repeating: 0, count: 12_000 * 2))
        XCTAssertNil(timingFirst.consumeTimingLine(
            frameCRCLine(pts: 0, frames: 12_000, data: fullBound)
        ))
        let finalFrame = bytes([Float](repeating: 0, count: 2))
        let finalRecord = frameCRCLine(pts: 12_000, frames: 1, data: finalFrame)
        let timingTask = Task.detached { timingFirst.consumeTimingLine(finalRecord) }
        try await Task.sleep(for: .milliseconds(40))
        timingFirst.cancel()
        let timingResult = await timingTask.value
        XCTAssertNil(timingResult)
        XCTAssertThrowsError(try timingFirst.finish()) { error in
            XCTAssertEqual(error as? LiveAudioMeterDecoder.Failure, .cancelled)
        }
    }

    func testTimestampedProcessorBackpressuresThenDrainsBothUnmatchedSides() async throws {
        let request = try makeRequest()
        let packet = bytes([Float](repeating: 0, count: 6_000 * 2))
        let allPCM = packet + packet + packet

        let pcmFirst = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertNil(pcmFirst.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(pcmFirst.consumeTimingLine("#sample_rate 0: 48000"))
        let pcmFinished = FlagBox()
        let pcmTask = Task.detached {
            defer { pcmFinished.set() }
            try pcmFirst.consumePCM(allPCM)
        }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(pcmFinished.value)
        XCTAssertNil(pcmFirst.consumeTimingLine(frameCRCLine(pts: 0, frames: 6_000, data: packet)))
        try await pcmTask.value
        XCTAssertTrue(pcmFinished.value)
        XCTAssertNil(pcmFirst.consumeTimingLine(frameCRCLine(pts: 6_000, frames: 6_000, data: packet)))
        XCTAssertNil(pcmFirst.consumeTimingLine(frameCRCLine(pts: 12_000, frames: 6_000, data: packet)))
        pcmFirst.finishTiming()
        XCTAssertEqual(try pcmFirst.finish().1.frameCount, 18_000)

        let timingFirst = try LiveAudioMeterTimestampedStreamProcessor(request: request) { _ in }
        XCTAssertNil(timingFirst.consumeTimingLine("#tb 0: 1/48000"))
        XCTAssertNil(timingFirst.consumeTimingLine("#sample_rate 0: 48000"))
        XCTAssertNil(timingFirst.consumeTimingLine(frameCRCLine(pts: 0, frames: 6_000, data: packet)))
        XCTAssertNil(timingFirst.consumeTimingLine(frameCRCLine(pts: 6_000, frames: 6_000, data: packet)))
        let timingFinished = FlagBox()
        let finalRecord = frameCRCLine(pts: 12_000, frames: 6_000, data: packet)
        let timingTask = Task.detached {
            defer { timingFinished.set() }
            return timingFirst.consumeTimingLine(finalRecord)
        }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(timingFinished.value)
        try timingFirst.consumePCM(allPCM)
        let timingResult = await timingTask.value
        XCTAssertNil(timingResult)
        XCTAssertTrue(timingFinished.value)
        timingFirst.finishTiming()
        XCTAssertEqual(try timingFirst.finish().1.frameCount, 18_000)
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

    func testWorkerGateBoundsSingleCallbackAndHonorsSuspendResume() async throws {
        let request = try makeRequest()
        let frames = 48_000
        let samples = (0..<frames).flatMap { frame -> [Float] in
            let sample = Float(0.2 * sin(2 * .pi * 997 * Double(frame) / 48_000))
            return [sample, -sample]
        }
        let expected = try directSnapshots(request: request, samples: samples)
        let received = SnapshotBox()
        let gate = LiveAudioMeterWorkerGate(request: request)
        let processor = try LiveAudioMeterPCMStreamProcessor(
            request: request, workerGate: gate
        ) { received.append($0) }
        let data = bytes(samples)
        gate.update(playbackTime: 0)

        let consumeTask = Task.detached { try processor.consume(data) }
        await eventually { received.values.last?.endFrame == 12_000 }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(received.values.last?.endFrame, 12_000)
        XCTAssertEqual(gate.permittedEndFrame, 12_000)

        gate.suspend()
        gate.update(playbackTime: 0.1)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(received.values.last?.endFrame, 12_000)

        gate.resume()
        await eventually { received.values.last?.endFrame == 16_800 }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(received.values.last?.endFrame, 16_800)

        gate.update(playbackTime: 1)
        try await consumeTask.value
        _ = try processor.finish()
        XCTAssertEqual(received.values, expected)
    }

    func testWorkerGateCancellationReleasesBlockedConsumer() async throws {
        let request = try makeRequest()
        let gate = LiveAudioMeterWorkerGate(request: request)
        let processor = try LiveAudioMeterPCMStreamProcessor(
            request: request, workerGate: gate
        ) { _ in }
        let data = bytes([Float](repeating: 0, count: 48_000 * 2))
        let consumeTask = Task.detached { try processor.consume(data) }

        try await Task.sleep(for: .milliseconds(40))
        gate.cancel()
        do {
            try await consumeTask.value
            XCTFail("Expected gate cancellation")
        } catch is CancellationError {
            // Expected: cancellation wakes the condition instead of deadlocking
            // process termination behind the stdout callback.
        }
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

    func testWorkerClearMaximaReachesDSPAndOrdersExactBucketEOFRevision() throws {
        let request = try makeRequest()
        let gate = LiveAudioMeterWorkerGate(request: request)
        let received = SnapshotBox()
        let processor = try LiveAudioMeterPCMStreamProcessor(
            request: request, workerGate: gate
        ) { received.append($0) }
        let frames = request.format.sampleRate * 4 / 10
        gate.update(playbackTime: 0.15)

        try processor.consume(bytes([Float](
            repeating: 0.5,
            count: frames * request.format.channelCount
        )))
        XCTAssertEqual(received.values.last?.maximaResetRevision, 0)
        XCTAssertNotNil(received.values.last?.maximumMomentaryLUFS)
        XCTAssertEqual(
            try XCTUnwrap(received.values.last?.maximumSamplePeakDBFS.first),
            20 * log10(0.5),
            accuracy: 0.000_001
        )

        let revision = gate.clearMaxima()
        let final = try XCTUnwrap(processor.finish())

        XCTAssertEqual(revision, 1)
        XCTAssertEqual(final.maximaResetRevision, revision)
        XCTAssertEqual(
            final.maximumSamplePeakDBFS,
            [-.infinity, -.infinity],
            "The exact-bucket EOF revision must not restore the pre-clear sample maximum"
        )
        XCTAssertNil(
            final.maximumMomentaryLUFS,
            "EOF must not restore the complete pre-clear loudness window as a maximum"
        )
        XCTAssertEqual(final.endFrame, Int64(frames))
        XCTAssertTrue(final.isFinal)
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

    func testBundledDecoderHonorsWorkerGateAndReturnsVersionedProvenance() async throws {
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
        let gate = LiveAudioMeterWorkerGate(request: request)
        gate.update(playbackTime: 0)

        let decodeTask = Task {
            try await LiveAudioMeterDecoder.decode(request, workerGate: gate) {
                received.append($0)
            }
        }
        await eventually(timeout: .seconds(3)) {
            received.values.last?.endFrame == 12_000
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(
            received.values.last?.endFrame,
            12_000,
            "The real FFmpeg pipe must stop at the playback-clock admission boundary"
        )
        gate.update(playbackTime: 1)
        let completion = try await decodeTask.value

        XCTAssertTrue(completion.provenance.decoderVersion.hasPrefix("ffmpeg version "))
        XCTAssertEqual(completion.provenance.request, request)
        XCTAssertEqual(completion.provenance.sampleFormat, "f32le")
        XCTAssertTrue(completion.provenance.dynamicRangeCompressionDisabled)
        XCTAssertTrue(completion.provenance.codecNormalizationDisabled)
        XCTAssertEqual(completion.provenance.timestampSource, .ffmpegFrameCRC)
        XCTAssertEqual(completion.provenance.timestampTimeBase, "1/48000")
        XCTAssertEqual(completion.provenance.timestampFrameCount, Int64(frameCount))
        XCTAssertEqual(completion.finalSnapshot?.endFrame, Int64(frameCount))
        XCTAssertTrue(completion.finalSnapshot?.isFinal == true)
        XCTAssertEqual(received.values.filter(\.isFinal).count, 1)
    }

    func testBundledDecoderFrameCRCSupportsNon48kAndMultichannelPCM() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let cases: [(Int, LiveAudioMeterFormat.Layout)] = [
            (44_100, .stereo),
            (96_000, .surround5Point1),
        ]
        for (sampleRate, layout) in cases {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "live-meter-framecrc-\(sampleRate)-\(UUID().uuidString).wav"
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let frameCount = sampleRate / 20
            let samples = [Float](
                repeating: 0.05,
                count: frameCount * layout.channelCount
            )
            try float32Wave(
                samples: samples, channels: layout.channelCount, sampleRate: sampleRate
            ).write(to: url)
            let format = try LiveAudioMeterFormat(sampleRate: sampleRate, layout: layout)
            let request = try LiveAudioMeterDecodeRequest(
                url: url, audioStreamOrderIndex: 0, format: format,
                startSourceFrame: 0, startSourceTime: 0
            )

            let completion = try await LiveAudioMeterDecoder.decode(request) { _ in }

            XCTAssertEqual(completion.provenance.timestampTimeBase, "1/\(sampleRate)")
            XCTAssertEqual(completion.provenance.timestampFrameCount, Int64(frameCount))
            XCTAssertEqual(completion.finalSnapshot?.endFrame, Int64(frameCount))
            XCTAssertEqual(completion.finalSnapshot?.samplePeakDBFS.count, layout.channelCount)
        }
    }

    func testBundledDecoderPreservesExactCompressedSeekIntervalsAndGain() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-meter-compressed-seek-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let waveURL = directory.appendingPathComponent("source.wav")
        let frameCount = 96_000
        let samples = (0..<frameCount).flatMap { frame -> [Float] in
            let value: Float = frame < 48_000
                ? 0
                : Float(0.1 * sin(2 * .pi * 1_000 * Double(frame) / 48_000))
            return [value, value]
        }
        try float32Wave(samples: samples, channels: 2, sampleRate: 48_000).write(to: waveURL)
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .stereo)

        for (codec, filename) in [
            ("aac", "source-aac.m4a"),
            ("alac", "source-alac.m4a"),
            ("ac3", "source-ac3.mp4"),
        ] {
            let compressedURL = directory.appendingPathComponent(filename)
            try await FFmpegService.run(arguments: [
                "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
                "-i", waveURL.path, "-c:a", codec, compressedURL.path,
            ])
            let request = try LiveAudioMeterDecodeRequest(
                url: compressedURL,
                audioStreamOrderIndex: 0,
                format: format,
                startSourceFrame: 48_000,
                startSourceTime: 1
            )
            let completion = try await LiveAudioMeterDecoder.decode(request) { _ in }

            XCTAssertEqual(
                completion.finalSnapshot?.endFrame,
                96_000,
                "\(codec) seek must preserve the exact requested one-second source interval"
            )
            let samplePeak = try XCTUnwrap(completion.finalSnapshot?.samplePeakDBFS.first)
            XCTAssertEqual(
                samplePeak,
                -20,
                accuracy: 0.75,
                "\(codec) decode must not apply unexpected gain normalization"
            )
            XCTAssertEqual(completion.provenance.timestampFrameCount, 48_000)
        }
    }

    func testBundledDecoderRejectsCompressedTimestampGapInsteadOfConcatenatingPCM() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-meter-timestamp-gap-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=1",
            "-af", "aselect=not(between(t\\,0.4\\,0.5))",
            "-c:a", "aac", url.path,
        ])
        let request = try LiveAudioMeterDecodeRequest(
            url: url, audioStreamOrderIndex: 0,
            format: LiveAudioMeterFormat(sampleRate: 48_000, layout: .mono),
            startSourceFrame: 0, startSourceTime: 0
        )

        do {
            _ = try await LiveAudioMeterDecoder.decode(request) { _ in }
            XCTFail("A timestamp gap must not be presented as contiguous source PCM")
        } catch let failure as LiveAudioMeterDecoder.Failure {
            guard case .timestampDiscontinuity(let expected, let actual) = failure else {
                return XCTFail("Expected timestamp discontinuity, got \(failure)")
            }
            XCTAssertGreaterThan(actual, expected)
        }
    }

    func testBundledDecoderPreservesInitialAudioDelayWhenRequestStartsInsideGap() async throws {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is required") }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-meter-initial-delay-\(UUID().uuidString).mkv")
        defer { try? FileManager.default.removeItem(at: url) }
        try await FFmpegService.run(arguments: [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=black:s=16x16:r=25:d=1",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=0.5",
            "-filter_complex", "[1:a]asetpts=PTS+0.5/TB[a]",
            "-map", "0:v:0", "-map", "[a]", "-c:v", "ffv1", "-c:a", "flac", url.path,
        ])
        let request = try LiveAudioMeterDecodeRequest(
            url: url, audioStreamOrderIndex: 0,
            format: LiveAudioMeterFormat(sampleRate: 48_000, layout: .mono),
            startSourceFrame: 12_000, startSourceTime: 0.25
        )

        do {
            _ = try await LiveAudioMeterDecoder.decode(request) { _ in }
            XCTFail("The delayed track must not be shifted to the requested boundary")
        } catch let failure as LiveAudioMeterDecoder.Failure {
            guard case .timestampDiscontinuity(let expected, let actual) = failure else {
                return XCTFail("Expected initial timestamp discontinuity, got \(failure)")
            }
            XCTAssertEqual(expected, 0)
            XCTAssertGreaterThan(actual, expected)
        }
    }

    private func frameCRCLine(
        pts: Int64, frames: Int64, data: Data
    ) -> String {
        String(
            format: "0, %lld, %lld, %lld, %d, 0x%08x",
            pts, pts, frames, data.count, adler32(data)
        )
    }

    private func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 0
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
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
        let samplesPerBlock = request.format.sampleRate / 20 * request.format.channelCount
        var output: [LiveAudioMeterSnapshot] = []
        var sampleOffset = 0
        while sampleOffset < samples.count {
            let end = min(sampleOffset + samplesPerBlock, samples.count)
            output += try meter.process(
                Array(samples[sampleOffset..<end]), startFrame: meter.nextFrame
            )
            sampleOffset = end
        }
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

    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @Sendable () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition not satisfied before timeout")
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

    private final class FlagBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = false

        var value: Bool { lock.withLock { storage } }
        func set() { lock.withLock { storage = true } }
    }
}
