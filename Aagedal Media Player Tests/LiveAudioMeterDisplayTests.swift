// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class LiveAudioMeterDisplayTests: XCTestCase {
    func testImmediateAttackAndTwentyDecibelsPerSourceSecondRelease() throws {
        var display = try LiveAudioPeakDisplay(sampleRate: 48_000)
        try display.consume(level: -30, sourceSamplePosition: 0)
        try display.consume(level: 2, sourceSamplePosition: 2_400)
        XCTAssertEqual(display.bar, 2)
        try display.consume(level: -.infinity, sourceSamplePosition: 26_400)
        XCTAssertEqual(display.bar, -8)
        XCTAssertEqual(display.marker, 2)
    }

    func testMarkerHoldsTwoSecondsThenDecaysOnlyBeyondHoldBoundary() throws {
        var display = try LiveAudioPeakDisplay(sampleRate: 48_000)
        try display.consume(level: -1, sourceSamplePosition: 0)
        try display.consume(level: -80, sourceSamplePosition: 72_000)
        XCTAssertEqual(display.marker, -1)
        try display.consume(level: -80, sourceSamplePosition: 108_000)
        XCTAssertEqual(display.marker, -6)
        XCTAssertEqual(display.bar, -46)
    }

    func testEqualSustainedPeakRefreshesHold() throws {
        var display = try LiveAudioPeakDisplay(sampleRate: 100)
        try display.consume(level: -5, sourceSamplePosition: 0)
        try display.consume(level: -5, sourceSamplePosition: 150)
        try display.consume(level: -80, sourceSamplePosition: 300)
        XCTAssertEqual(display.marker, -5)
        try display.consume(level: -80, sourceSamplePosition: 400)
        XCTAssertEqual(display.marker, -15)
    }

    func testUnavailableAndSilenceRemainDistinctAndResetStartsFresh() throws {
        var display = try LiveAudioPeakDisplay(sampleRate: 48_000)
        XCTAssertNil(display.bar)
        try display.consume(level: -.infinity, sourceSamplePosition: 0)
        XCTAssertEqual(display.bar, -.infinity)
        try display.consume(level: nil, sourceSamplePosition: 2_400)
        XCTAssertNil(display.bar)
        XCTAssertNil(display.marker)
        display.reset()
        XCTAssertNil(display.sourceSamplePosition)
        try display.consume(level: 3, sourceSamplePosition: 0)
        XCTAssertEqual(display.bar, 3)
        XCTAssertEqual(display.marker, 3)
    }

    func testInvalidUpdatesAreAtomicAndRepeatedOrBackwardSamplesAreRejected() throws {
        var display = try LiveAudioPeakDisplay(sampleRate: 48_000)
        try display.consume(level: -10, sourceSamplePosition: 10)
        for position: Int64 in [-1, 0, 10] {
            XCTAssertThrowsError(try display.consume(level: 0, sourceSamplePosition: position))
        }
        for level in [Double.nan, Double.infinity] {
            XCTAssertThrowsError(try display.consume(level: level, sourceSamplePosition: 20))
        }
        XCTAssertEqual(display.bar, -10)
        XCTAssertEqual(display.sourceSamplePosition, 10)
        for rate in [0, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try LiveAudioPeakDisplay(sampleRate: rate))
        }
    }

    func testSourceRateControlsElapsedTime() throws {
        for rate in [44_100.0, 48_000, 96_000] {
            var display = try LiveAudioPeakDisplay(sampleRate: rate)
            try display.consume(level: 0, sourceSamplePosition: 1_000_000)
            try display.consume(level: -90, sourceSamplePosition: 1_000_000 + Int64(rate / 2))
            XCTAssertEqual(try XCTUnwrap(display.bar), -10, accuracy: 1e-10)
        }
    }

    func testGuidesCompareUnroundedValuesAndPreserveDistinctBoundaryRules() {
        let ebu = LiveAudioMeterReference.ebuProduction
        XCTAssertEqual(ebu.exceedsTruePeakGuide(-1.00001), false)
        XCTAssertEqual(ebu.exceedsTruePeakGuide(-1), false)
        XCTAssertEqual(ebu.exceedsTruePeakGuide(-0.99999), true)
        let atsc = LiveAudioMeterReference.atscExchange
        XCTAssertEqual(atsc.exceedsTruePeakGuide(-2.00001), false)
        XCTAssertEqual(atsc.exceedsTruePeakGuide(-2), true)
        XCTAssertEqual(atsc.exceedsTruePeakGuide(-1.99999), true)
        XCTAssertEqual(atsc.loudnessUnit, "LKFS")
        XCTAssertTrue(atsc.dialogueAssessmentUnavailable)
        XCTAssertNil(ebu.exceedsTruePeakGuide(nil))
        XCTAssertNil(ebu.exceedsTruePeakGuide(.nan))
        XCTAssertEqual(ebu.exceedsTruePeakGuide(-.infinity), false)
    }

    func testCustomReferenceRequiresFiniteValuesAndAllowsNoCeiling() throws {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try LiveAudioMeterReference.custom(loudnessTarget: invalid, truePeakCeiling: nil))
            XCTAssertThrowsError(try LiveAudioMeterReference.custom(loudnessTarget: -16, truePeakCeiling: invalid))
        }
        let reference = try LiveAudioMeterReference.custom(loudnessTarget: -16, truePeakCeiling: nil)
        XCTAssertNil(reference.exceedsTruePeakGuide(4))
        let ceiling = try LiveAudioMeterReference.custom(loudnessTarget: -16, truePeakCeiling: 1)
        XCTAssertEqual(ceiling.exceedsTruePeakGuide(1), false)
        XCTAssertEqual(ceiling.exceedsTruePeakGuide(1.00001), true)
    }

    func testIndependentMaximaClearAndPresetReevaluation() throws {
        var maxima = LiveAudioMeterMaxima()
        try maxima.consume(samplePeak: -5, truePeak: -1.5, momentary: -23, shortTerm: nil)
        try maxima.consume(samplePeak: -6, truePeak: -4, momentary: -25, shortTerm: -26)
        XCTAssertEqual(maxima.samplePeak, -5)
        XCTAssertEqual(maxima.truePeak, -1.5)
        XCTAssertEqual(maxima.momentary, -23)
        XCTAssertEqual(maxima.shortTerm, -26)
        XCTAssertFalse(maxima.truePeakGuideExceeded)
        maxima.setReference(.atscExchange)
        XCTAssertTrue(maxima.truePeakGuideExceeded)
        maxima.setReference(.ebuProduction)
        XCTAssertFalse(maxima.truePeakGuideExceeded)
        maxima.clearMaxima()
        XCTAssertNil(maxima.samplePeak)
        XCTAssertNil(maxima.truePeak)
        XCTAssertNil(maxima.momentary)
        XCTAssertNil(maxima.shortTerm)
        XCTAssertFalse(maxima.truePeakGuideExceeded)
        XCTAssertEqual(maxima.reference, .ebuProduction)
        try maxima.consume(samplePeak: -.infinity, truePeak: -.infinity, momentary: nil, shortTerm: nil)
        XCTAssertEqual(maxima.samplePeak, -.infinity)
        XCTAssertNil(maxima.momentary)
    }

    func testInvalidMaximaBatchDoesNotPartiallyApplyAndExceedanceLatches() throws {
        var maxima = LiveAudioMeterMaxima()
        try maxima.consume(samplePeak: -2, truePeak: 0, momentary: -23, shortTerm: -24)
        XCTAssertThrowsError(try maxima.consume(samplePeak: 8, truePeak: 9, momentary: .nan, shortTerm: 1))
        XCTAssertEqual(maxima.samplePeak, -2)
        XCTAssertEqual(maxima.truePeak, 0)
        try maxima.consume(samplePeak: nil, truePeak: -40, momentary: nil, shortTerm: nil)
        XCTAssertTrue(maxima.truePeakGuideExceeded)
        maxima.clearMaxima()
        XCTAssertFalse(maxima.truePeakGuideExceeded)
    }
}
