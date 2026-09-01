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
        XCTAssertEqual(channels[0].maxs[0], 0.4, accuracy: 0.0001)
        XCTAssertEqual(channels[0].mins[0], 0, accuracy: 0.0001)
        XCTAssertEqual(channels[0].maxs[1], 0, accuracy: 0.0001)
        XCTAssertEqual(channels[0].mins[1], -0.6, accuracy: 0.0001)
        XCTAssertEqual(channels[1].maxs[0], 0, accuracy: 0.0001)
        XCTAssertEqual(channels[1].mins[0], -0.4, accuracy: 0.0001)
        XCTAssertEqual(channels[1].maxs[1], 0.6, accuracy: 0.0001)
        XCTAssertEqual(channels[1].mins[1], 0, accuracy: 0.0001)
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
