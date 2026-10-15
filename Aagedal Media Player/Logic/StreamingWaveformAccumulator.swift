// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated struct WaveformAmplitudeData: Sendable, Equatable {
    let mins: [Float]
    let maxs: [Float]
    // Signed mean magnitudes form the denser body inside the peak envelope.
    var averageMins: [Float] = []
    var averageMaxs: [Float] = []

    /// Reduces to display columns before rasterization, preserving even a single
    /// peak that would disappear when a large image is interpolated down.
    nonisolated func resampled(to width: Int) -> WaveformAmplitudeData {
        let count = min(mins.count, maxs.count)
        guard width > 0, count > 0 else { return WaveformAmplitudeData(mins: [], maxs: []) }
        var low = [Float](repeating: 0, count: width)
        var high = low
        var averageLow = low
        var averageHigh = low
        let hasAverages = averageMins.count == count && averageMaxs.count == count
        for column in 0..<width {
            let start = column * count / width
            let end = min(count, max(start + 1, (column + 1) * count / width))
            for index in start..<end {
                let minValue = mins[index].isFinite ? max(-1, min(0, mins[index])) : 0
                let maxValue = maxs[index].isFinite ? min(1, max(0, maxs[index])) : 0
                low[column] = min(low[column], minValue)
                high[column] = max(high[column], maxValue)
                if hasAverages {
                    let meanMin = averageMins[index].isFinite ? averageMins[index] : 0
                    let meanMax = averageMaxs[index].isFinite ? averageMaxs[index] : 0
                    averageLow[column] += max(minValue, min(0, meanMin))
                    averageHigh[column] += min(maxValue, max(0, meanMax))
                }
            }
            averageLow[column] /= Float(end - start)
            averageHigh[column] /= Float(end - start)
        }
        return WaveformAmplitudeData(
            mins: low, maxs: high,
            averageMins: hasAverages ? averageLow : [],
            averageMaxs: hasAverages ? averageHigh : []
        )
    }
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
    private nonisolated(unsafe) var peaks: [Float]
    private nonisolated(unsafe) var troughs: [Float]
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
        peaks = [Float](repeating: 0, count: binCount)
        troughs = peaks
        positiveSums = [Float](repeating: 0, count: binCount)
        negativeSums = [Float](repeating: 0, count: binCount)
        positiveCounts = [UInt32](repeating: 0, count: binCount)
        negativeCounts = [UInt32](repeating: 0, count: binCount)
    }

    /// Number of scalar accumulator values retained for the complete stream.
    /// Exposed for regression tests and profiling of the bounded-memory contract.
    nonisolated var retainedScalarCount: Int {
        width * channelCount * 6
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
                var averageMins = mins
                var averageMaxs = maxs
                for column in 0..<width {
                    let index = channel * width + column
                    mins[column] = troughs[index]
                    maxs[column] = peaks[index]
                    if positiveCounts[index] > 0 {
                        averageMaxs[column] = min(
                            positiveSums[index] / Float(positiveCounts[index]),
                            1
                        )
                    }
                    if negativeCounts[index] > 0 {
                        averageMins[column] = max(
                            negativeSums[index] / Float(negativeCounts[index]),
                            -1
                        )
                    }
                }
                return WaveformAmplitudeData(
                    mins: mins, maxs: maxs, averageMins: averageMins, averageMaxs: averageMaxs
                )
            }
        }
    }

    nonisolated private func accumulate(_ sample: Float) {
        let frameIndex = sampleIndex / channelCount
        let channel = sampleIndex % channelCount
        let column = min(frameIndex * width / expectedFrameCount, width - 1)
        let index = channel * width + column

        if sample.isFinite {
            let sample = max(-1, min(1, sample))
            peaks[index] = max(peaks[index], sample)
            troughs[index] = min(troughs[index], sample)
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
