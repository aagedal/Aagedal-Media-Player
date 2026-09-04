// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class ScopeFrameDifferenceTests: XCTestCase {
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
}
