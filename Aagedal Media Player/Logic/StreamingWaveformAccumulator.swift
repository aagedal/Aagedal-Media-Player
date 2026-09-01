// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct WaveformAmplitudeData: Sendable, Equatable {
    let mins: [Float]
    let maxs: [Float]
}

nonisolated enum StreamingWaveformAccumulatorError: Error, LocalizedError, Equatable {
    case outputMissing

    nonisolated var errorDescription: String? {
        "ffmpeg produced no waveform samples"
    }
}

/// Incrementally reduces interleaved little-endian Float32 PCM into a fixed
/// number of waveform columns. Retained memory depends on width and channel
/// count, never on the decoded media duration.
final class StreamingWaveformAccumulator: Sendable {
    private let lock = NSLock()
    private let width: Int
    private let channelCount: Int
    private let expectedFrameCount: Int
    private nonisolated(unsafe) var positiveSums: [Float]
    private nonisolated(unsafe) var negativeSums: [Float]
    private nonisolated(unsafe) var positiveCounts: [UInt32]
    private nonisolated(unsafe) var negativeCounts: [UInt32]
    private nonisolated(unsafe) var pendingBytes = Data()
    private nonisolated(unsafe) var sampleIndex = 0

    nonisolated init(width: Int, channelCount: Int, expectedFrameCount: Int) {
        self.width = max(1, width)
        self.channelCount = max(1, channelCount)
        self.expectedFrameCount = max(1, expectedFrameCount)
        let binCount = self.width * self.channelCount
        positiveSums = [Float](repeating: 0, count: binCount)
        negativeSums = [Float](repeating: 0, count: binCount)
        positiveCounts = [UInt32](repeating: 0, count: binCount)
        negativeCounts = [UInt32](repeating: 0, count: binCount)
    }

    /// Number of scalar accumulator values retained for the complete stream.
    /// Exposed for regression tests and profiling of the bounded-memory contract.
    nonisolated var retainedScalarCount: Int {
        width * channelCount * 4
    }

    nonisolated func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            let floatByteCount = MemoryLayout<Float>.size
            var dataOffset = 0

            if !pendingBytes.isEmpty {
                let neededByteCount = floatByteCount - pendingBytes.count
                let copiedByteCount = min(neededByteCount, data.count)
                pendingBytes.append(data.prefix(copiedByteCount))
                dataOffset += copiedByteCount

                if pendingBytes.count == floatByteCount {
                    let bits = pendingBytes.withUnsafeBytes { bytes in
                        UInt32(littleEndian: bytes.loadUnaligned(as: UInt32.self))
                    }
                    pendingBytes = Data()
                    accumulate(Float(bitPattern: bits))
                } else {
                    return
                }
            }

            let remainingByteCount = data.count - dataOffset
            let completeByteCount = remainingByteCount - remainingByteCount % floatByteCount

            if completeByteCount > 0 {
                data.withUnsafeBytes { bytes in
                    let endOffset = dataOffset + completeByteCount
                    while dataOffset < endOffset {
                        let bits = UInt32(littleEndian: bytes.loadUnaligned(
                            fromByteOffset: dataOffset,
                            as: UInt32.self
                        ))
                        accumulate(Float(bitPattern: bits))
                        dataOffset += floatByteCount
                    }
                }
            }

            if dataOffset < data.count {
                pendingBytes = Data(data[dataOffset...])
            }
        }
    }

    nonisolated func finish() throws -> [WaveformAmplitudeData] {
        try lock.withLock {
            guard sampleIndex >= channelCount else {
                throw StreamingWaveformAccumulatorError.outputMissing
            }

            return (0..<channelCount).map { channel in
                var mins = [Float](repeating: 0, count: width)
                var maxs = [Float](repeating: 0, count: width)
                for column in 0..<width {
                    let index = channel * width + column
                    if positiveCounts[index] > 0 {
                        maxs[column] = min(
                            positiveSums[index] / Float(positiveCounts[index]),
                            1
                        )
                    }
                    if negativeCounts[index] > 0 {
                        mins[column] = max(
                            negativeSums[index] / Float(negativeCounts[index]),
                            -1
                        )
                    }
                }
                return WaveformAmplitudeData(mins: mins, maxs: maxs)
            }
        }
    }

    nonisolated private func accumulate(_ sample: Float) {
        let frameIndex = sampleIndex / channelCount
        let channel = sampleIndex % channelCount
        let column = min(frameIndex * width / expectedFrameCount, width - 1)
        let index = channel * width + column

        if sample.isFinite {
            if sample >= 0 {
                positiveSums[index] += sample
                positiveCounts[index] &+= 1
            } else {
                negativeSums[index] += sample
                negativeCounts[index] &+= 1
            }
        }
        sampleIndex += 1
    }
}
