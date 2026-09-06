// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import XCTest

final class TimelineViewportTests: XCTestCase {
    func testFitAndZoomAroundPlayhead() {
        let fit = TimelineViewport(duration: 7200, center: 5000)
        XCTAssertEqual(fit.start, 0)
        XCTAssertEqual(fit.end, 7200)
        let zoom = TimelineViewport(duration: 7200, zoom: 8, center: 5000)
        XCTAssertEqual(zoom.start, 4550)
        XCTAssertEqual(zoom.end, 5450)
        XCTAssertEqual(zoom.time(at: 0.5), 5000)
    }

    func testPanClampsAtBothMediaBoundariesWithoutChangingSpan() {
        for (center, start) in [(-100.0, 0.0), (0, 0), (100, 75), (1000, 75)] {
            let viewport = TimelineViewport(duration: 100, zoom: 4, center: center)
            XCTAssertEqual(viewport.start, start)
            XCTAssertEqual(viewport.span, 25)
        }
    }

    func testFractionalRateFramePositionsRoundTripInLongRecording() {
        for rate in [24.0, 24000.0 / 1001, 30000.0 / 1001, 60000.0 / 1001] {
            let time = 1_000_001.0 / rate
            let viewport = TimelineViewport(duration: 86400, zoom: 64, center: time)
            for frame in [-1.0, 0, 1] {
                let target = time + frame / rate
                XCTAssertEqual(viewport.time(at: viewport.fraction(for: target)), target, accuracy: 0.000000001)
            }
        }
    }

    func testClipsSpanningRangesAndRejectsOffscreenMarkers() {
        let viewport = TimelineViewport(duration: 100, zoom: 4, center: 50)
        XCTAssertEqual(viewport.clipped(0...100), 37.5...62.5)
        XCTAssertEqual(viewport.clipped(40...45), 40...45)
        XCTAssertEqual(viewport.clipped(20...40), 37.5...40)
        XCTAssertNil(viewport.clipped(0...30))
        XCTAssertNil(viewport.clipped(70...80))
        XCTAssertFalse(viewport.contains(30))
        XCTAssertFalse(viewport.contains(.nan))
        XCTAssertTrue(viewport.contains(37.5))
    }

    func testInvalidGeometryAndOutOfBoundsGesturesStayFinite() {
        for duration in [0.0, -1, .nan, .infinity] {
            let viewport = TimelineViewport(duration: duration, zoom: .nan, center: .infinity)
            XCTAssertEqual(viewport.start, 0)
            XCTAssertEqual(viewport.end, 0)
            XCTAssertEqual(viewport.time(at: .nan), 0)
            XCTAssertEqual(viewport.fraction(for: .infinity), 0)
        }
        let viewport = TimelineViewport(duration: 100, zoom: 4, center: 50)
        XCTAssertEqual(viewport.time(at: -1), viewport.start)
        XCTAssertEqual(viewport.time(at: 2), viewport.end)
        XCTAssertEqual(TimelineViewport(duration: 100, zoom: 1000).zoom, 64)
        XCTAssertEqual(TimelineViewport(duration: 100, zoom: -1).zoom, 1)
    }
}
