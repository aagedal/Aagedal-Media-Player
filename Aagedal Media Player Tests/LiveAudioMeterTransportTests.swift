// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class LiveAudioMeterTransportTests: XCTestCase {
    func testClockPolicyUsesExactHardDriftBoundary() {
        let policy = LiveAudioMeterClockPolicy(sampleRate: 48_000)

        XCTAssertEqual(
            policy.assess(decodedEndFrame: 60_000, playbackTime: 1, isSuspendedAhead: false),
            .suspendAhead(drift: 0.25)
        )
        XCTAssertEqual(
            policy.assess(decodedEndFrame: 60_001, playbackTime: 1, isSuspendedAhead: false),
            .failed(drift: Double(60_001) / 48_000 - 1)
        )
        XCTAssertEqual(
            policy.assess(decodedEndFrame: 36_000, playbackTime: 1, isSuspendedAhead: false),
            .synchronized(drift: -0.25)
        )
        XCTAssertEqual(
            policy.assess(decodedEndFrame: 35_999, playbackTime: 1, isSuspendedAhead: false),
            .failed(drift: Double(35_999) / 48_000 - 1)
        )
    }

    func testAheadSuspensionUsesHysteresis() {
        let policy = LiveAudioMeterClockPolicy(sampleRate: 48_000)

        XCTAssertEqual(
            policy.assess(decodedEndFrame: 57_600, playbackTime: 1, isSuspendedAhead: false),
            .suspendAhead(drift: 0.2)
        )
        XCTAssertEqual(
            policy.assess(decodedEndFrame: 55_200, playbackTime: 1, isSuspendedAhead: true),
            .suspendAhead(drift: 0.15)
        )
        XCTAssertEqual(
            policy.assess(decodedEndFrame: 52_800, playbackTime: 1, isSuspendedAhead: true),
            .resume(drift: 0.1)
        )
    }

    func testClockPolicyRejectsInvalidInputs() {
        for policy in [LiveAudioMeterClockPolicy(sampleRate: 0), .init(sampleRate: -1)] {
            XCTAssertEqual(
                policy.assess(decodedEndFrame: 0, playbackTime: 0, isSuspendedAhead: false),
                .invalidClock
            )
        }
        let policy = LiveAudioMeterClockPolicy(sampleRate: 48_000)
        for time in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(
                policy.assess(decodedEndFrame: 0, playbackTime: time, isSuspendedAhead: false),
                .invalidClock
            )
        }
        XCTAssertEqual(
            policy.assess(decodedEndFrame: -1, playbackTime: 0, isSuspendedAhead: false),
            .invalidClock
        )
    }

    func testPlaybackSnapshotRequiresForwardOneTimesRate() {
        for rate: Float in [1, 1.000_05, 0.999_95] {
            XCTAssertTrue(snapshot(rate: rate).supportsMeasurement)
        }
        for rate: Float in [0, -1, 0.5, 1.001, .nan, .infinity] {
            XCTAssertFalse(snapshot(rate: rate).supportsMeasurement)
        }
    }

    func testPlayerPublishesAtomicClockSnapshots() {
        let controller = PlayerController()
        var received: [LiveAudioMeterPlaybackEvent] = []
        let subscription = controller.liveAudioMeterPlaybackEvents.sink { received.append($0) }

        controller.currentPlaybackTime = 12.5

        XCTAssertEqual(received, [.clock(.init(
            time: 12.5,
            phase: .idle,
            isPlaying: false,
            rate: 1,
            preparationID: 0
        ))])
        withExtendedLifetime(subscription) {}
    }

    func testReloadPublishesTypedGeometryBoundaryAtCurrentClock() {
        let controller = PlayerController()
        let comparison = CompareSessionController()
        controller.currentPlaybackTime = 12.5
        var boundaries: [(LiveAudioMeterPlaybackDiscontinuity, LiveAudioMeterPlaybackSnapshot)] = []
        let subscription = controller.liveAudioMeterPlaybackEvents.sink { event in
            if case let .discontinuity(cause, snapshot) = event {
                boundaries.append((cause, snapshot))
            }
        }

        comparison.reload(primary: controller)

        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries.first?.0, .geometryReload)
        XCTAssertEqual(boundaries.first?.1.time, 12.5)
        withExtendedLifetime(subscription) {}
    }

    func testPlayerPublishesTypedEndBoundary() {
        let controller = PlayerController()
        var received: LiveAudioMeterPlaybackEvent?
        let subscription = controller.liveAudioMeterPlaybackEvents.sink { received = $0 }

        controller.publishLiveAudioMeterEnded()

        XCTAssertEqual(received, .ended(.init(
            time: 0,
            phase: .idle,
            isPlaying: false,
            rate: 1,
            preparationID: 0
        )))
        withExtendedLifetime(subscription) {}
    }

    private func snapshot(rate: Float) -> LiveAudioMeterPlaybackSnapshot {
        .init(time: 0, phase: .ready, isPlaying: true, rate: rate, preparationID: 1)
    }
}
