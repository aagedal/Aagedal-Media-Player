// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class StreamingWaveformAccumulatorTests: XCTestCase {
    func testAggregatesInterleavedChannelsAcrossArbitraryByteChunks() throws {
        let accumulator = StreamingWaveformAccumulator(
            width: 2,
            channelCount: 2,
            expectedFrameCount: 4
        )
        let pcm = pcmData([
            0.2, -0.2,
            0.6, -0.6,
            -0.4, 0.4,
            -0.8, 0.8,
        ])

        accumulator.consume(pcm.subdata(in: 0..<3))
        accumulator.consume(pcm.subdata(in: 3..<11))
        accumulator.consume(pcm.subdata(in: 11..<pcm.count))

        let channels = try accumulator.finish()
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].maxs[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(channels[0].mins[0], 0, accuracy: 0.0001)
        XCTAssertEqual(channels[0].maxs[1], 0, accuracy: 0.0001)
        XCTAssertEqual(channels[0].mins[1], -0.8, accuracy: 0.0001)
        XCTAssertEqual(channels[1].maxs[0], 0, accuracy: 0.0001)
        XCTAssertEqual(channels[1].mins[0], -0.6, accuracy: 0.0001)
        XCTAssertEqual(channels[1].maxs[1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(channels[1].mins[1], 0, accuracy: 0.0001)
    }

    func testSingleSampleTransientSurvivesAveragingAndDisplayReduction() throws {
        let accumulator = StreamingWaveformAccumulator(width: 100, channelCount: 1, expectedFrameCount: 1000)
        var samples = [Float](repeating: 0.01, count: 1000)
        samples[445] = 1
        samples[446] = -0.9
        accumulator.consume(pcmData(samples))
        let data = try XCTUnwrap(accumulator.finish().first)
        let overview = data.resampled(to: 2)
        XCTAssertEqual(overview.maxs, [1, 0.01])
        XCTAssertEqual(overview.mins, [-0.9, 0])
        XCTAssertLessThan(overview.averageMaxs[0], 0.02)
        XCTAssertEqual(data.averageMins[44], -0.9, accuracy: 0.0001)
    }

    func testNonFiniteAndOutOfRangePCMProducesFiniteBoundedEnvelope() throws {
        let accumulator = StreamingWaveformAccumulator(width: 1, channelCount: 1, expectedFrameCount: 6)
        accumulator.consume(pcmData([.nan, .infinity, -.infinity, 8, -4, 0.25]))
        let data = try XCTUnwrap(accumulator.finish().first)
        XCTAssertEqual(data.mins, [-1])
        XCTAssertEqual(data.maxs, [1])
        XCTAssertEqual(data.averageMaxs[0], 0.625, accuracy: 0.0001)
        XCTAssertEqual(data.averageMins, [-1])
    }

    func testDisplayReductionPreservesAsymmetryAndEverySourceColumn() {
        let data = WaveformAmplitudeData(mins: [0, -0.8, 0, -0.1, 0], maxs: [0, 0, 0.9, 0, 0.2])
        XCTAssertEqual(data.resampled(to: 2).mins, [-0.8, -0.1])
        XCTAssertEqual(data.resampled(to: 2).maxs, [0, 0.9])
        let enlarged = data.resampled(to: 10)
        XCTAssertEqual(enlarged.maxs, [0, 0, 0, 0, 0.9, 0.9, 0, 0, 0.2, 0.2])
        XCTAssertTrue(data.resampled(to: 0).mins.isEmpty)
    }

    func testRetainedStorageDoesNotGrowWithInputDuration() throws {
        let accumulator = StreamingWaveformAccumulator(
            width: 400,
            channelCount: 8,
            expectedFrameCount: 10_000
        )
        let retainedScalarCount = accumulator.retainedScalarCount
        let chunk = pcmData(Array(repeating: Float(0.25), count: 8_000))

        for _ in 0..<100 {
            accumulator.consume(chunk)
        }

        XCTAssertEqual(accumulator.retainedScalarCount, retainedScalarCount)
        XCTAssertEqual(try accumulator.finish().count, 8)
    }

    func testEmptyStreamFailsAsMissingOutput() {
        let accumulator = StreamingWaveformAccumulator(
            width: 10,
            channelCount: 2,
            expectedFrameCount: 10
        )

        XCTAssertThrowsError(try accumulator.finish()) { error in
            XCTAssertEqual(error as? StreamingWaveformAccumulatorError, .outputMissing)
        }
    }

    private func pcmData(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<UInt32>.size)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }
}
