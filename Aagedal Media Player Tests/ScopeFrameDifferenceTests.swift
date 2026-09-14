// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class ScopeFrameDifferenceTests: XCTestCase {
    func testRGBYParadePlotsEachChannelAndLumaInItsOwnPanel() throws {
        let source = try makeImage(width: 2, height: 1, red: 255, green: 0, blue: 0)

        let parade = try XCTUnwrap(ScopeComputer.computeParade(
            from: source,
            outputSize: CGSize(width: 46, height: 11)
        ))

        XCTAssertEqual(parade.width, 46)
        XCTAssertEqual(parade.height, 11)
        XCTAssertEqual(try storedPixel(in: parade, x: 0, y: 0), Pixel(red: 255, green: 51, blue: 51))
        XCTAssertEqual(try storedPixel(in: parade, x: 12, y: 10), Pixel(red: 51, green: 255, blue: 51))
        XCTAssertEqual(try storedPixel(in: parade, x: 24, y: 10), Pixel(red: 76, green: 102, blue: 255))
        XCTAssertEqual(try storedPixel(in: parade, x: 36, y: 8), Pixel(red: 216, green: 216, blue: 216))
        XCTAssertEqual(try storedAlpha(in: parade, x: 10, y: 0), 0, "Panel gaps must remain clear")
        XCTAssertEqual(try storedAlpha(in: parade, x: 11, y: 10), 0, "Panel gaps must remain clear")
    }

    func testRGBYParadeRejectsOutputTooNarrowForFourPanels() throws {
        let source = try makeImage(width: 1, height: 1, red: 0, green: 0, blue: 0)

        XCTAssertNil(ScopeComputer.computeParade(
            from: source,
            outputSize: CGSize(width: 13, height: 10)
        ))
    }

    func testScopeRenderersRejectInvalidOrUnboundedOutputDimensions() throws {
        let source = try makeImage(width: 1, height: 1, red: 0, green: 0, blue: 0)
        let hdr = HDRFrameData(
            pixels: [0, 0, 0], width: 1, height: 1,
            transferFunction: .pq, isLinearLight: false, contentPeakNits: 1_000
        )
        let sizes = [
            CGSize(width: CGFloat.nan, height: 10),
            CGSize(width: 10, height: CGFloat.infinity),
            CGSize(width: -1, height: 10),
            CGSize(width: 2_049, height: 10),
        ]

        for size in sizes {
            XCTAssertNil(ScopeComputer.computeWaveform(from: source, outputSize: size))
            XCTAssertNil(ScopeComputer.computeParade(from: source, outputSize: size))
            XCTAssertNil(ScopeComputer.computeVectorscope(from: source, outputSize: size))
            XCTAssertNil(ScopeComputer.computeHDRWaveform(from: hdr, outputSize: size))
            XCTAssertNil(ScopeComputer.computeHDRParade(from: hdr, outputSize: size))
        }
    }

    func testHDRTransferFunctionsMatchReferenceEndpoints() {
        XCTAssertEqual(ScopeComputer.pqToNits(0), 0)
        XCTAssertEqual(ScopeComputer.pqToNits(1), 10_000, accuracy: 0.5)
        XCTAssertEqual(ScopeComputer.pqToNits(0.508_078_4), 100, accuracy: 0.1)

        XCTAssertEqual(ScopeComputer.hlgToNits(0, peakNits: 1_000), 0)
        XCTAssertEqual(ScopeComputer.hlgToNits(1, peakNits: 1_000), 1_000, accuracy: 0.1)
        XCTAssertEqual(ScopeComputer.hlgToNits(0.5, peakNits: 1_000), 50.7, accuracy: 0.2)

        XCTAssertEqual(ScopeComputer.linearToNits(-1), 0)
        XCTAssertEqual(ScopeComputer.linearToNits(1), 203, accuracy: 0.001)
    }

    func testHDRWaveformUsesLogarithmicNitPlacementForPQ() throws {
        let frame = HDRFrameData(
            pixels: [0.508_078_4, 0.508_078_4, 0.508_078_4],
            width: 1,
            height: 1,
            transferFunction: .pq,
            isLinearLight: false,
            contentPeakNits: 10_000
        )

        let waveform = try XCTUnwrap(ScopeComputer.computeHDRWaveform(
            from: frame,
            outputSize: CGSize(width: 1, height: 101)
        ))
        let rows = try opaqueRows(in: waveform, x: 0)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try XCTUnwrap(rows.first), 40, accuracy: 1)
    }

    func testHDRWaveformPlacesHLGBlackAndPeakAtScaleEndpoints() throws {
        let frame = HDRFrameData(
            pixels: [0, 0, 0, 1, 1, 1],
            width: 2,
            height: 1,
            transferFunction: .hlg,
            isLinearLight: false,
            contentPeakNits: 1_000
        )

        let waveform = try XCTUnwrap(ScopeComputer.computeHDRWaveform(
            from: frame,
            outputSize: CGSize(width: 2, height: 101)
        ))

        XCTAssertEqual(try opaqueRows(in: waveform, x: 0), [100])
        XCTAssertEqual(try opaqueRows(in: waveform, x: 1), [0])
    }

    func testHDRParadeUsesIndependentLinearLightChannelLevels() throws {
        let frame = HDRFrameData(
            pixels: [1, 0.5, 0.25],
            width: 1,
            height: 1,
            transferFunction: .pq,
            isLinearLight: true,
            contentPeakNits: 1_000
        )

        let parade = try XCTUnwrap(ScopeComputer.computeHDRParade(
            from: frame,
            outputSize: CGSize(width: 46, height: 101)
        ))

        XCTAssertEqual(try opaqueRows(in: parade, x: 0), [18])
        XCTAssertEqual(try opaqueRows(in: parade, x: 12), [25])
        XCTAssertEqual(try opaqueRows(in: parade, x: 24), [33])
        XCTAssertEqual(try opaqueRows(in: parade, x: 36), [23])
    }

    func testHDRRenderersRejectMalformedStorageNonFinitePixelsAndInvalidPeak() {
        let malformed = HDRFrameData(
            pixels: [1, 1],
            width: 1,
            height: 1,
            transferFunction: .pq,
            isLinearLight: false,
            contentPeakNits: 1_000
        )
        let nonFinite = HDRFrameData(
            pixels: [Float.nan, 0, 0],
            width: 1,
            height: 1,
            transferFunction: .hlg,
            isLinearLight: false,
            contentPeakNits: 1_000
        )
        let invalidPeak = HDRFrameData(
            pixels: [0, 0, 0],
            width: 1,
            height: 1,
            transferFunction: .pq,
            isLinearLight: false,
            contentPeakNits: Float.nan
        )
        let excessivePeak = HDRFrameData(
            pixels: [0, 0, 0],
            width: 1,
            height: 1,
            transferFunction: .pq,
            isLinearLight: false,
            contentPeakNits: 10_001
        )
        let size = CGSize(width: 46, height: 101)

        for frame in [malformed, nonFinite, invalidPeak, excessivePeak] {
            XCTAssertNil(ScopeComputer.computeHDRWaveform(from: frame, outputSize: size))
            XCTAssertNil(ScopeComputer.computeHDRParade(from: frame, outputSize: size))
        }
    }

    @MainActor
    func testScopeWorkerDoesNotPublishRejectedHDRPeakScale() async {
        let worker = ScopeRenderWorker()
        let invalidFrame = HDRFrameData(
            pixels: [0, 0, 0],
            width: 1,
            height: 1,
            transferFunction: .pq,
            isLinearLight: false,
            contentPeakNits: Float.infinity
        )

        worker.submit(
            primary: ScopeFrameInput(
                sdrFrame: nil,
                hdrFrame: invalidFrame,
                transferFunction: .pq,
                displayAspectRatio: 1
            ),
            secondary: nil,
            source: .primary,
            differenceGain: 1,
            mode: .luma,
            resolution: 64
        )
        for _ in 0..<100 where worker.renderSequence == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(worker.renderSequence, 1)
        XCTAssertNil(worker.waveformImage)
        XCTAssertTrue(worker.hdrPeakNits.isFinite)
        XCTAssertEqual(worker.hdrPeakNits, 10_000)
        worker.cancel(clearImages: true)
    }

    func testRelativeTimelinePairingChoosesNearestSecondaryTimestamp() throws {
        let primary = sample(sequence: 1, time: 2)
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: nil,
            secondaryStartSeconds: nil,
            secondaryDuration: 20
        )
        let secondary = [
            sample(sequence: 1, time: 1.9),
            sample(sequence: 2, time: 2.01),
            sample(sequence: 3, time: 2.03),
        ]

        let match = try XCTUnwrap(ScopeFramePairer.closestSecondary(
            to: primary,
            mapping: mapping,
            secondaryDuration: 20,
            candidates: secondary,
            tolerance: 1.0 / 24.0
        ))

        XCTAssertEqual(match.sequence, 2)
    }

    func testSourceTimecodeOffsetIsAppliedBeforePairing() throws {
        let primary = sample(sequence: 1, time: 2)
        let mapping = CompareTimelineMapping(
            primaryStartSeconds: 100,
            secondaryStartSeconds: 90,
            secondaryDuration: 20
        )
        let secondary = [
            sample(sequence: 1, time: 2),
            sample(sequence: 2, time: 11.99),
        ]

        let match = try XCTUnwrap(ScopeFramePairer.closestSecondary(
            to: primary,
            mapping: mapping,
            secondaryDuration: 20,
            candidates: secondary,
            tolerance: 1.0 / 24.0
        ))

        XCTAssertEqual(match.sequence, 2)
    }

    func testPairingRejectsFramesOutsideToleranceAndUnavailableTimestamps() {
        let candidates = [
            sample(sequence: 1, time: 1.9),
            sample(sequence: 2, time: 2, quality: .unavailable),
        ]

        XCTAssertNil(ScopeFramePairer.closest(
            to: 2,
            candidates: candidates,
            tolerance: 1.0 / 60.0
        ))
    }

    func testPairingRejectsEstimatedCaptureWhoseClockBracketExceedsTolerance() {
        let candidates = [
            sample(
                sequence: 1,
                time: 2,
                uncertainty: 0.02,
                quality: .estimated
            ),
        ]

        XCTAssertNil(ScopeFramePairer.closest(
            to: 2,
            targetUncertainty: 0,
            candidates: candidates,
            tolerance: 1.0 / 60.0
        ))
    }

    func testMixedRateToleranceUsesLargerFrameDuration() {
        XCTAssertEqual(
            ScopeFramePairer.tolerance(
                primaryFrameRate: 59.94,
                secondaryFrameRate: 23.976
            ),
            1.0 / 23.976,
            accuracy: 0.000_001
        )
    }

    func testPairingPrefersExactTimestampWhenDeltaTies() throws {
        let candidates = [
            sample(sequence: 2, time: 2.5, quality: .estimated),
            sample(sequence: 1, time: 1.5, quality: .exact),
        ]

        let match = try XCTUnwrap(ScopeFramePairer.closest(
            to: 2,
            candidates: candidates,
            tolerance: 0.5
        ))

        XCTAssertEqual(match.sequence, 1)
    }

    func testFrameHistoryIsBoundedAndClearsAcrossSeekDiscontinuity() {
        var history = ScopeFrameHistory(capacity: 3)
        history.append(sample(sequence: 1, time: 0))
        history.append(sample(sequence: 2, time: 0.1))
        history.append(sample(sequence: 3, time: 0.2))
        history.append(sample(sequence: 4, time: 0.3))
        XCTAssertEqual(history.samples.map(\.sequence), [2, 3, 4])

        history.append(sample(sequence: 5, time: 8))
        XCTAssertEqual(history.samples.map(\.sequence), [5])
    }

    func testIdenticalFramesProduceBlack() throws {
        let frame = try makeImage(width: 4, height: 2, red: 60, green: 120, blue: 180)

        let difference = try XCTUnwrap(ScopeFrameDifference.makeDisplaySpaceDifference(
            primary: frame,
            primaryDisplayAspectRatio: 2,
            secondary: frame,
            secondaryDisplayAspectRatio: 2,
            gain: 1
        ))

        XCTAssertEqual(try pixel(in: difference, x: 2, y: 1), Pixel(red: 0, green: 0, blue: 0))
    }

    func testDifferenceIsAbsoluteSymmetricAndAppliesGain() throws {
        let first = try makeImage(width: 2, height: 1, red: 10, green: 80, blue: 200)
        let second = try makeImage(width: 2, height: 1, red: 50, green: 20, blue: 100)

        let forward = try XCTUnwrap(ScopeFrameDifference.makeDisplaySpaceDifference(
            primary: first,
            primaryDisplayAspectRatio: 2,
            secondary: second,
            secondaryDisplayAspectRatio: 2,
            gain: 2
        ))
        let reverse = try XCTUnwrap(ScopeFrameDifference.makeDisplaySpaceDifference(
            primary: second,
            primaryDisplayAspectRatio: 2,
            secondary: first,
            secondaryDisplayAspectRatio: 2,
            gain: 2
        ))

        let expected = Pixel(red: 80, green: 120, blue: 200)
        XCTAssertEqual(try pixel(in: forward, x: 0, y: 0), expected)
        XCTAssertEqual(try pixel(in: reverse, x: 0, y: 0), expected)
    }

    func testDifferenceGainClampsOutput() throws {
        let first = try makeImage(width: 1, height: 1, red: 0, green: 0, blue: 0)
        let second = try makeImage(width: 1, height: 1, red: 20, green: 30, blue: 40)

        let difference = try XCTUnwrap(ScopeFrameDifference.makeDisplaySpaceDifference(
            primary: first,
            primaryDisplayAspectRatio: 1,
            secondary: second,
            secondaryDisplayAspectRatio: 1,
            gain: 16
        ))

        XCTAssertEqual(try pixel(in: difference, x: 0, y: 0), Pixel(red: 255, green: 255, blue: 255))
    }

    func testMatchingDisplayAspectsNormalizeDifferentRasters() throws {
        let primary = try makeImage(width: 4, height: 2, red: 90, green: 90, blue: 90)
        let secondary = try makeImage(width: 2, height: 1, red: 90, green: 90, blue: 90)

        let difference = try XCTUnwrap(ScopeFrameDifference.makeDisplaySpaceDifference(
            primary: primary,
            primaryDisplayAspectRatio: 2,
            secondary: secondary,
            secondaryDisplayAspectRatio: 2,
            gain: 1
        ))

        XCTAssertEqual(difference.width, 4)
        XCTAssertEqual(difference.height, 2)
        XCTAssertEqual(try pixel(in: difference, x: 1, y: 1), Pixel(red: 0, green: 0, blue: 0))
    }

    func testDifferentDisplayAspectFitsSecondaryWithoutStretching() throws {
        let primary = try makeImage(width: 4, height: 2, red: 255, green: 255, blue: 255)
        let secondary = try makeImage(width: 4, height: 2, red: 255, green: 255, blue: 255)

        let difference = try XCTUnwrap(ScopeFrameDifference.makeDisplaySpaceDifference(
            primary: primary,
            primaryDisplayAspectRatio: 2,
            secondary: secondary,
            secondaryDisplayAspectRatio: 1,
            gain: 1
        ))

        XCTAssertEqual(try pixel(in: difference, x: 0, y: 1), Pixel(red: 255, green: 255, blue: 255))
        XCTAssertEqual(try pixel(in: difference, x: 1, y: 1), Pixel(red: 0, green: 0, blue: 0))
    }

    private struct Pixel: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private func sample(
        sequence: UInt64,
        time: TimeInterval?,
        uncertainty: TimeInterval = 0,
        quality: ScopeFrameTimestampQuality = .exact
    ) -> ScopeFrameSample {
        ScopeFrameSample(
            sequence: sequence,
            playbackTime: time,
            timestampUncertainty: uncertainty,
            timestampQuality: quality,
            sdrFrame: nil,
            hdrFrame: nil
        )
    }

    private func makeImage(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) throws -> CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            bytes.append(contentsOf: [blue, green, red, 255])
        }
        let data = Data(bytes)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func pixel(in image: CGImage, x: Int, y: Int) throws -> Pixel {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return Pixel(red: bytes[offset + 2], green: bytes[offset + 1], blue: bytes[offset])
    }

    /// ScopeComputer creates images directly from BGRA storage. Reading that
    /// provider avoids Core Graphics coordinate transforms in placement tests.
    private func storedPixel(in image: CGImage, x: Int, y: Int) throws -> Pixel {
        let bytes = try storedBytes(in: image)
        let offset = (y * image.width + x) * 4
        return Pixel(red: bytes[offset + 2], green: bytes[offset + 1], blue: bytes[offset])
    }

    private func storedAlpha(in image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let bytes = try storedBytes(in: image)
        return bytes[(y * image.width + x) * 4 + 3]
    }

    private func opaqueRows(in image: CGImage, x: Int) throws -> [Int] {
        let bytes = try storedBytes(in: image)
        return (0..<image.height).filter { y in
            bytes[(y * image.width + x) * 4 + 3] > 0
        }
    }

    private func storedBytes(in image: CGImage) throws -> [UInt8] {
        let provider = try XCTUnwrap(image.dataProvider)
        let data = try XCTUnwrap(provider.data as Data?)
        return [UInt8](data)
    }
}
