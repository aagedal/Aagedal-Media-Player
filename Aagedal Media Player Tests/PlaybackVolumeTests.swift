// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import AppKit
import SwiftUI
import XCTest

@MainActor
final class PlaybackVolumeTests: XCTestCase {
    func testMPVCubicGainMatchesLinearAVPlayerAmplitude() {
        for percent in [0.0, 1, 10, 25, 50, 75, 100] {
            let mpv = PlaybackVolume.mpvValue(for: percent)
            XCTAssertEqual(pow(mpv / 100, 3), percent / 100, accuracy: 1e-12)
        }
        XCTAssertEqual(PlaybackVolume.mpvValue(for: -10), 0)
        XCTAssertEqual(PlaybackVolume.mpvValue(for: 200), 100)
        XCTAssertEqual(PlaybackVolume.mpvValue(for: .nan), 100)
    }

    func testNativeSliderPublishesIntermediateTrackingValuesSynchronously() throws {
        var values: [Double] = []
        let host = NSHostingView(rootView: PlaybackVolumeSlider(
            value: Binding(get: { values.last ?? 100 }, set: { values.append($0) }),
            onFocusChange: { _ in }
        ))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        host.layoutSubtreeIfNeeded()
        func findSlider(_ view: NSView) -> NSSlider? {
            if let slider = view as? NSSlider { return slider }
            return view.subviews.lazy.compactMap(findSlider).first
        }
        let slider = try XCTUnwrap(findSlider(host))
        XCTAssertTrue(slider.isContinuous)
        XCTAssertEqual(slider.numberOfTickMarks, 0)
        for volume in [75.5, 50.25, 25.75, 0, 100] {
            slider.doubleValue = volume
            XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
            XCTAssertEqual(values.last, volume, "Must reach playback in the tracking action, without a deferred view update")
        }
        XCTAssertEqual(values.count, 5)
    }
}
