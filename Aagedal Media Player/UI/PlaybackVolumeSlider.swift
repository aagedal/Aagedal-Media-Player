// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Deliver every native tracking action directly to playback, including while
/// AppKit is in its mouse-tracking loop. No discrete tick-mark row is drawn.
struct PlaybackVolumeSlider: NSViewRepresentable {
    @Binding var value: Double
    var onFocusChange: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Control {
        let slider = Control()
        slider.minValue = 0
        slider.maxValue = 100
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.controlSize = .small
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel("Volume")
        return slider
    }

    func updateNSView(_ slider: Control, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        slider.onFocusChange = onFocusChange
        slider.setAccessibilityValueDescription("\(Int(value)) percent")
    }

    final class Coordinator: NSObject {
        var parent: PlaybackVolumeSlider
        init(parent: PlaybackVolumeSlider) { self.parent = parent }

        @objc func changed(_ sender: NSSlider) {
            parent.value = sender.doubleValue
            sender.setAccessibilityValueDescription("\(Int(sender.doubleValue)) percent")
        }
    }

    final class Control: NSSlider {
        var onFocusChange: ((Bool) -> Void)?
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusChange?(true) }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted { onFocusChange?(false) }
            return accepted
        }
    }
}
