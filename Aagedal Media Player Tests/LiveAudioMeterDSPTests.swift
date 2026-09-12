// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class LiveAudioMeterDSPTests: XCTestCase {
    private func feed(_ meter: inout LiveAudioMeterDSP, frames: Int, chunk: Int = 4_096,
                      signal: (Int, Int) -> Float) throws -> [LiveAudioMeterSnapshot] {
        var output: [LiveAudioMeterSnapshot] = []
        var offset = 0
        while offset < frames {
            let count = min(chunk, frames - offset)
            var pcm: [Float] = []
            pcm.reserveCapacity(count * meter.format.channelCount)
            for frame in offset..<(offset + count) {
                for channel in 0..<meter.format.channelCount { pcm.append(signal(frame, channel)) }
            }
            output += try meter.process(pcm, startFrame: meter.nextFrame)
            offset += count
        }
        return output
    }

    func testCalibrationAndWarmupAtEverySupportedRate() throws {
        for rate in [44_100, 48_000, 96_000] {
            var meter = try LiveAudioMeterDSP(format: .init(sampleRate: rate, layout: .stereo), startFrame: 123)
            let readings = try feed(&meter, frames: rate * 4) { frame, channel in
                Float(pow(10, -23.0 / 20) * sin(2 * .pi * 1_000 * Double(frame) / Double(rate)))
                    * (channel == 0 ? 1 : -1)
            }
            XCTAssertEqual(readings.count, 80)
            XCTAssertEqual(readings[0].endFrame, Int64(123 + rate / 20))
            XCTAssertNil(readings[6].momentaryLUFS)
            XCTAssertNotNil(readings[7].momentaryLUFS)
            XCTAssertEqual(readings[8].loudnessEndFrame, readings[7].endFrame)
            XCTAssertEqual(readings[8].momentaryLUFS, readings[7].momentaryLUFS)
            XCTAssertNil(readings[6].loudnessEndFrame)
            XCTAssertNil(readings[58].shortTermLUFS)
            XCTAssertNotNil(readings[59].shortTermLUFS)
            let last = try XCTUnwrap(readings.last)
            XCTAssertEqual(try XCTUnwrap(last.momentaryLUFS), -23, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(last.shortTermLUFS), -23, accuracy: 0.1)
            XCTAssertEqual(last.maximumSamplePeakDBFS[0], -23, accuracy: 0.01)
            XCTAssertEqual(last.maximumTruePeakDBTP[0], -23, accuracy: 0.2)
            XCTAssertEqual(last.maximumTruePeakDBTP[0], last.maximumTruePeakDBTP[1])
        }
    }

    func testUngatedWindowsTrackLevelChangeWithoutWallClockDecay() throws {
        let rate = 48_000
        var meter = try LiveAudioMeterDSP(format: .init(sampleRate: rate, layout: .stereo))
        let values = try feed(&meter, frames: rate * 7) { frame, _ in
            let gain = pow(10, (frame < rate * 3 ? -23.0 : -43.0) / 20)
            return Float(gain * sin(2 * .pi * 1_000 * Double(frame) / Double(rate)))
        }
        XCTAssertEqual(try XCTUnwrap(values[59].shortTermLUFS), -23, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(values[67].momentaryLUFS), -43, accuracy: 0.1)
        // One second into the level step: two seconds loud plus one second quiet.
        let expected = -23 + 10 * log10((2 + 0.01) / 3)
        XCTAssertEqual(try XCTUnwrap(values[79].shortTermLUFS), expected, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(values.last?.shortTermLUFS), -43, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(values.last?.maximumShortTermLUFS), -23, accuracy: 0.1)
        let position = meter.nextFrame
        XCTAssertTrue(try meter.process([], startFrame: position).isEmpty)
        XCTAssertEqual(meter.nextFrame, position, "Pause supplies no artificial silence or elapsed samples")
    }

    func testTimeVaryingWindowsAgreeWithIndependentFFmpegMeasurement() async throws {
        for rate in [44_100, 48_000, 96_000] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("meter-reference-\(UUID().uuidString).f32")
            defer { try? FileManager.default.removeItem(at: url) }
            var pcm = [Float]()
            pcm.reserveCapacity(rate * 4 * 2)
            for frame in 0..<(rate * 4) {
                let time = Double(frame) / Double(rate)
                let gain = time < 1.2 ? 0.1 : (time < 2.5 ? 0.01 : 0.04)
                let value = Float(gain * (sin(2 * .pi * 997 * time) + 0.3 * sin(2 * .pi * 83 * time)))
                pcm.append(value)
                pcm.append(-value)
            }
            var bytes = Data(capacity: pcm.count * 4)
            for value in pcm {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
            }
            try bytes.write(to: url)
            let executable = try XCTUnwrap(Bundle.main.url(forResource: "ffmpeg", withExtension: nil))
            let reference = try await SubprocessService.run(executableURL: executable, arguments: [
                "-hide_banner", "-nostdin", "-f", "f32le", "-ar", String(rate), "-ac", "2",
                "-i", url.path, "-af", "ebur128=metadata=1,ametadata=print:file=-", "-f", "null", "-"
            ])
            XCTAssertEqual(reference.terminationStatus, 0, String(decoding: reference.standardError, as: UTF8.self))
            let lines = String(decoding: reference.standardOutput, as: UTF8.self).split(separator: "\n")
            func levels(_ key: String) -> [Double] {
                lines.filter { $0.hasPrefix(key + "=") }.compactMap { Double($0.dropFirst(key.count + 1)) }
            }
            let m = levels("lavfi.r128.M")
            let short = levels("lavfi.r128.S")
            XCTAssertEqual(m.count, 40)
            XCTAssertEqual(short.count, 40)
            guard m.count == 40, short.count == 40 else { continue }
            var meter = try LiveAudioMeterDSP(format: .init(sampleRate: rate, layout: .stereo))
            let actual = try feed(&meter, frames: rate * 4) { frame, channel in pcm[frame * 2 + channel] }
            for index in 3..<40 {
                XCTAssertEqual(try XCTUnwrap(actual[index * 2 + 1].momentaryLUFS), m[index], accuracy: 0.02,
                    "M at \(rate) Hz / \(index + 1)00 ms")
            }
            for index in 29..<40 {
                XCTAssertEqual(try XCTUnwrap(actual[index * 2 + 1].shortTermLUFS), short[index], accuracy: 0.02,
                    "S at \(rate) Hz / \(index + 1)00 ms")
            }
        }
    }

    func testLFEExcludedAndEveryConventionalSurroundWeighted() throws {
        // BS.1770-5 Annex 1 Table 3 and Annex 3 Tables 4–5: in
        // conventional 7.1, rear ±135° channels have unit weight, distinct
        // from the 1.41 side ±90° weight. Do not copy FFmpeg's default 7.1 map.
        let references: [(LiveAudioMeterFormat.Layout, [Double])] = [
            (.surround5Point1, [1, 1, 1, 0, 1.41, 1.41]),
            (.surround7Point1, [1, 1, 1, 0, 1, 1, 1.41, 1.41])
        ]
        for rate in [44_100, 48_000, 96_000] {
          for (layout, weights) in references {
            for selected in 0..<layout.channelCount {
                var meter = try LiveAudioMeterDSP(format: .init(sampleRate: rate, layout: layout))
                let readings = try feed(&meter, frames: rate / 2) { frame, channel in
                    channel == selected ? Float(pow(10, -23.0 / 20) * sin(2 * .pi * 1_000 * Double(frame) / Double(rate))) : 0
                }
                let last = try XCTUnwrap(readings.last)
                XCTAssertEqual(last.maximumSamplePeakDBFS[selected], -23, accuracy: 0.01)
                XCTAssertEqual(last.maximumTruePeakDBTP[selected], -23, accuracy: 0.2)
                if selected == 3 {
                    XCTAssertEqual(last.momentaryLUFS, -.infinity)
                } else {
                    let expected = -23 + 10 * log10(weights[selected] / 2)
                    XCTAssertEqual(try XCTUnwrap(last.momentaryLUFS), expected, accuracy: 0.1)
                }
            }
          }
        }
    }

    func testSilenceUnknownLayoutAndShortFileAreDistinct() throws {
        for layout in [LiveAudioMeterFormat.Layout.mono, .unknown(channels: 3)] {
            var meter = try LiveAudioMeterDSP(format: .init(sampleRate: 48_000, layout: layout))
            let values = try feed(&meter, frames: 48_000) { _, _ in 0 }
            XCTAssertEqual(values.last?.maximumTruePeakDBTP, .init(repeating: -.infinity, count: layout.channelCount))
            if layout == .mono { XCTAssertEqual(values.last?.momentaryLUFS, -.infinity) }
            else { XCTAssertNil(values.last?.momentaryLUFS) }
            let final = try XCTUnwrap(meter.finish())
            XCTAssertEqual(final.endFrame, 48_000)
            XCTAssertNil(final.shortTermLUFS)
        }
        var empty = try LiveAudioMeterDSP(format: .init(sampleRate: 48_000, layout: .mono))
        XCTAssertNil(try empty.finish())
    }

    func testBlockBoundariesAndPolarityPreserveReconstructionIncludingEOFTail() throws {
        for rate in [44_100, 48_000, 96_000] {
            // A shifted quarter-rate sinusoid has -3.01 dBFS samples and a
            // reconstructed 0 dBTP crest, unlike a sample-peak approximation.
            func signal(_ frame: Int, _ channel: Int) -> Float {
                Float(sin(.pi / 2 * Double(frame) + .pi / 4)) * (channel == 0 ? 1 : -1)
            }
            let format = try LiveAudioMeterFormat(sampleRate: rate, layout: .stereo)
            var bulk = try LiveAudioMeterDSP(format: format)
            var split = try LiveAudioMeterDSP(format: format)
            let a = try feed(&bulk, frames: 5_003, signal: signal)
            let b = try feed(&split, frames: 5_003, chunk: 7, signal: signal)
            XCTAssertEqual(a, b)
            let endA = try XCTUnwrap(bulk.finish())
            XCTAssertEqual(endA, try split.finish())
            XCTAssertEqual(endA.endFrame, 5_003)
            XCTAssertEqual(endA.maximumSamplePeakDBFS[0], -3.0103, accuracy: 0.001)
            // Finite tone onset/offset may overshoot; evaluate the interior bucket.
            XCTAssertEqual(try XCTUnwrap(a.last).truePeakDBTP[0], 0, accuracy: 0.4)
            XCTAssertEqual(endA.maximumTruePeakDBTP[0], endA.maximumTruePeakDBTP[1])
            XCTAssertNil(endA.momentaryLUFS)
        }
        var impulse = try LiveAudioMeterDSP(format: .init(sampleRate: 48_000, layout: .mono), startFrame: 10)
        _ = try impulse.process([1], startFrame: 10)
        let final = try XCTUnwrap(impulse.finish())
        XCTAssertEqual(final.endFrame, 11)
        XCTAssertEqual(final.maximumTruePeakDBTP[0], 20 * log10(7964.0 / 8192), accuracy: 1e-10)
        XCTAssertNil(final.momentaryLUFS, "Filter drain must not create loudness samples")
        XCTAssertThrowsError(try impulse.finish())
        XCTAssertThrowsError(try impulse.process([0], startFrame: 11))
    }

    func testBandLimitedTransientsReconstructSignedAndAboveFullScalePeaks() throws {
        // Independent analytic signal A*sinc(t/8)^2*cos(pi*t/2) has exact
        // continuous peak |A| and spectral support below Nyquist. Its center
        // falls between source samples and across a 50-ms publication boundary.
        for rate in [44_100, 48_000, 96_000] {
            for amplitude in [0.5, -0.5, 1.2, -1.2] {
                var meter = try LiveAudioMeterDSP(format: .init(sampleRate: rate, layout: .stereo))
                let center = Double(rate) / 2 - 0.5
                _ = try feed(&meter, frames: rate, chunk: 113) { frame, channel in
                    let t = Double(frame) - center
                    let argument = Double.pi * t / 8
                    let sinc = argument == 0 ? 1 : sin(argument) / argument
                    return Float(amplitude * sinc * sinc * cos(.pi * t / 2)) * (channel == 0 ? 1 : -1)
                }
                let final = try XCTUnwrap(meter.finish())
                let expected = 20 * log10(abs(amplitude))
                XCTAssertLessThan(final.maximumSamplePeakDBFS[0], expected - 3)
                XCTAssertGreaterThanOrEqual(final.maximumTruePeakDBTP[0], expected - 0.4)
                XCTAssertLessThanOrEqual(final.maximumTruePeakDBTP[0], expected + 0.2)
                XCTAssertEqual(final.maximumTruePeakDBTP[0], final.maximumTruePeakDBTP[1])
            }
        }
    }

    func testExactBucketEOFPreservesLastValidReadingWithoutInventingSilence() throws {
        for frames in [2_400, 4_800, 4_801] {
            var meter = try LiveAudioMeterDSP(format: .init(sampleRate: 48_000, layout: .mono))
            let values = try feed(&meter, frames: frames) { _, _ in 0.5 }
            let final = try XCTUnwrap(meter.finish())
            XCTAssertEqual(final.endFrame, Int64(frames))
            XCTAssertEqual(final.samplePeakDBFS[0], 20 * log10(0.5), accuracy: 1e-10)
            XCTAssertGreaterThanOrEqual(final.truePeakDBTP[0], try XCTUnwrap(values.last).truePeakDBTP[0])
            XCTAssertTrue(final.isFinal)
            XCTAssertNil(final.momentaryLUFS)
        }
    }

    func testClearMaximaKeepsWindowsAndDoesNotRelatchOldBucketPeak() throws {
        var meter = try LiveAudioMeterDSP(format: .init(sampleRate: 48_000, layout: .mono))
        _ = try feed(&meter, frames: 48_100) { frame, _ in frame == 48_000 ? 2 : 0 }
        meter.clearMaxima()
        let results = try feed(&meter, frames: 2_300) { _, _ in 0 }
        let last = try XCTUnwrap(results.last)
        XCTAssertEqual(last.samplePeakDBFS[0], 20 * log10(2), accuracy: 1e-10)
        XCTAssertEqual(last.maximumSamplePeakDBFS[0], -.infinity)
        XCTAssertEqual(last.maximumTruePeakDBTP[0], -.infinity)
        XCTAssertNotNil(last.momentaryLUFS)
        var reset = try LiveAudioMeterDSP(format: meter.format, startFrame: meter.nextFrame)
        let fresh = try feed(&reset, frames: 2_400) { _, _ in 0 }
        XCTAssertNil(fresh.last?.momentaryLUFS)
        XCTAssertEqual(fresh.last?.maximumSamplePeakDBFS[0], -.infinity)
    }

    func testRejectsInvalidInputAndPermanentlyInvalidatesSegment() throws {
        for (pcm, position, expected) in [
            ([Float(0)], Int64(0), LiveAudioMeterDSP.Failure.incompleteFrame),
            ([Float.nan, 0], 0, .nonFinitePCM),
            ([Float.infinity, 0], 0, .nonFinitePCM),
            ([Float(0), 0], 1, .discontinuity(expected: 0, actual: 1)),
            ([Float](repeating: 0, count: 24_002), 0, .oversizedBlock)
        ] {
            var meter = try LiveAudioMeterDSP(format: .init(sampleRate: 48_000, layout: .stereo))
            XCTAssertThrowsError(try meter.process(pcm, startFrame: position)) { error in
                XCTAssertEqual(error as? LiveAudioMeterDSP.Failure, expected)
            }
            XCTAssertEqual(meter.nextFrame, 0)
            XCTAssertThrowsError(try meter.process([0, 0], startFrame: 0))
            XCTAssertThrowsError(try meter.finish())
        }
        XCTAssertThrowsError(try LiveAudioMeterFormat(sampleRate: 192_000, layout: .stereo))
        XCTAssertThrowsError(try LiveAudioMeterFormat(sampleRate: 48_000, layout: .unknown(channels: 9)))
        let format = try LiveAudioMeterFormat(sampleRate: 48_000, layout: .mono)
        XCTAssertThrowsError(try LiveAudioMeterDSP(format: format, startFrame: -1))
        var overflow = try LiveAudioMeterDSP(format: format, startFrame: Int64.max)
        XCTAssertThrowsError(try overflow.process([0], startFrame: Int64.max))
    }
}
