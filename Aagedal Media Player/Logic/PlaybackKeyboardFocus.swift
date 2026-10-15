// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Local playback key monitors run before AppKit dispatches typing to the
/// field editor. Check the actual responder so the first digit is protected,
/// without waiting for a SwiftUI focus update or disabling all inspector keys.
enum PlaybackKeyboardFocus {
    static func isEditingText(_ responder: NSResponder?) -> Bool {
        if let editor = responder as? NSTextView { return editor.isEditable }
        if let field = responder as? NSTextField { return field.isEditable }
        return false
    }
}
