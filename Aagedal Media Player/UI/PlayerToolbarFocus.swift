// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Lets the player retain its overlay and yield Space while a toolbar control
/// owns keyboard focus, including controls inside responsive toolbar layouts.
struct PlayerToolbarFocusPreference: PreferenceKey {
    static let defaultValue: UUID? = nil

    static func reduce(value: inout UUID?, nextValue: () -> UUID?) {
        if let next = nextValue() { value = next }
    }
}

private struct PlayerToolbarFocus: ViewModifier {
    @FocusState private var isFocused: Bool
    @State private var focusID = UUID()

    func body(content: Content) -> some View {
        content
            .id(focusID)
            .focused($isFocused)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .preference(key: PlayerToolbarFocusPreference.self, value: isFocused ? focusID : nil)
    }
}

extension View {
    func playerToolbarFocus() -> some View {
        modifier(PlayerToolbarFocus())
    }
}
