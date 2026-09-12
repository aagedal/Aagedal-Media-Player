// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

final class LiveAudioMeterPresentationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LiveAudioMeterPresentationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferenceDefaultsAndRoundTripPreserveOptionalCeiling() {
        AppSettings.registerDefaults(in: defaults)
        XCTAssertEqual(LiveAudioMeterPreferences(defaults: defaults), .defaults)

        let stored = LiveAudioMeterPreferences(
            preset: .custom,
            customLoudnessTarget: -16.25,
            customTruePeakCeiling: -0.75
        )
        stored.save(to: defaults)
        XCTAssertEqual(LiveAudioMeterPreferences(defaults: defaults), stored)

        var withoutCeiling = stored
        withoutCeiling.customTruePeakCeiling = nil
        withoutCeiling.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: AppSettings.liveAudioMeterCustomTruePeakCeiling.key))
        XCTAssertEqual(LiveAudioMeterPreferences(defaults: defaults), withoutCeiling)
    }

    func testMalformedPersistedReferenceFallsBackToFiniteCanonicalValues() {
        defaults.set("futurePreset", forKey: AppSettings.liveAudioMeterPreset.key)
        defaults.set(Double.nan, forKey: AppSettings.liveAudioMeterCustomLoudnessTarget.key)
        defaults.set(Double.infinity, forKey: AppSettings.liveAudioMeterCustomTruePeakCeiling.key)

        let preferences = LiveAudioMeterPreferences(defaults: defaults)
        XCTAssertEqual(preferences.preset, .ebuProduction)
        XCTAssertEqual(preferences.customLoudnessTarget, -23)
        XCTAssertNil(preferences.customTruePeakCeiling)
        XCTAssertEqual(preferences.reference, .ebuProduction)
    }

    func testEBUBoundaryUsesStrictComparisonAndExactExceedanceWording() {
        let atBoundary = makeState(reference: .ebuProduction, maximumTruePeaks: [-4, -1])
        XCTAssertEqual(
            atBoundary.truePeakAssessment.text,
            "No true-peak guide exceedance: −1.0 dBTP does not meet > −1.0 dBTP."
        )
        XCTAssertFalse(atBoundary.truePeakAssessment.isExceeded)

        let aboveBoundary = makeState(reference: .ebuProduction, maximumTruePeaks: [-4, -0.999_999])
        XCTAssertEqual(
            aboveBoundary.truePeakAssessment.text,
            "True-peak guide exceeded: −1.0 dBTP meets > −1.0 dBTP."
        )
        XCTAssertTrue(aboveBoundary.truePeakAssessment.isExceeded)
        XCTAssertTrue(aboveBoundary.truePeakAssessment.diagnosticText.contains("maximum=-0.999"))
        XCTAssertTrue(aboveBoundary.truePeakAssessment.diagnosticText.contains("comparison=>"))
    }

    func testATSCBoundaryUsesInclusiveComparisonAndExactExceedanceWording() {
        let state = makeState(reference: .atscExchange, maximumTruePeaks: [-12, -2])
        XCTAssertEqual(
            state.truePeakAssessment.text,
            "True-peak guide exceeded: −2.0 dBTP meets ≥ −2.0 dBTP."
        )
        XCTAssertTrue(state.truePeakAssessment.isExceeded)
        XCTAssertEqual(
            state.truePeakAssessment.diagnosticText,
            "maximum=-2 dBTP; comparison=≥; ceiling=-2 dBTP"
        )
    }

    func testMissingMeasurementsAndOptionalCustomCeilingRemainExplicit() throws {
        let unavailable = makeState(reference: .ebuProduction, maximumTruePeaks: [nil, nil])
        XCTAssertEqual(
            unavailable.truePeakAssessment.text,
            "True-peak guide: > −1.0 dBTP; maximum unavailable."
        )

        let custom = try LiveAudioMeterReference.custom(loudnessTarget: -18, truePeakCeiling: nil)
        let noCeiling = makeState(reference: custom, maximumTruePeaks: [3])
        XCTAssertEqual(noCeiling.truePeakAssessment, .noCeiling)
        XCTAssertEqual(noCeiling.truePeakAssessment.text, "No true-peak ceiling set.")
    }

    func testPresentationStateIsEquatableAndSendableAcrossEveryLifecycleStatus() {
        assertSendable(LiveAudioMeterViewState.self)
        let statuses: [LiveAudioMeterPresentationStatus] = [
            .unavailable(reason: "Malformed PCM", diagnostic: "decoder exit 1"),
            .warmingUp(position: "00:10.000", momentaryReady: true, shortTermReady: false),
            .active(position: "00:10.100"),
            .paused(position: "00:10.100"),
            .buffering(position: "00:10.100"),
            .ended(position: "00:12.000")
        ]
        XCTAssertEqual(statuses.map(\.title), ["Unavailable", "Warming up", "Active", "Paused", "Buffering", "Ended"])
        XCTAssertNil(statuses[0].position)
        XCTAssertEqual(statuses.dropFirst().compactMap(\.position).count, 5)
        XCTAssertEqual(statuses, statuses)
    }

    private func makeState(
        reference: LiveAudioMeterReference,
        maximumTruePeaks: [Double?]
    ) -> LiveAudioMeterViewState {
        let empty = LiveAudioMeterLevelState(current: nil, bar: nil, marker: nil, maximum: nil)
        return LiveAudioMeterViewState(
            status: .active(position: "00:01.000"),
            sourceOptions: [
                LiveAudioMeterSourceOption(id: "A", label: "A", detail: "Track 1"),
                LiveAudioMeterSourceOption(id: "B", label: "B", detail: "Track 2")
            ],
            selectedSourceID: "A",
            measuredSourceLabel: "A · Track 1",
            channels: maximumTruePeaks.enumerated().map { index, maximum in
                LiveAudioMeterChannelState(
                    id: index,
                    label: "Channel \(index + 1)",
                    samplePeak: empty,
                    truePeak: LiveAudioMeterLevelState(
                        current: maximum, bar: maximum, marker: maximum, maximum: maximum
                    )
                )
            },
            loudness: LiveAudioMeterLoudnessState(
                momentary: nil, maximumMomentary: nil, shortTerm: nil, maximumShortTerm: nil
            ),
            reference: reference,
            provenance: nil,
            diagnostics: []
        )
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
