// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum ScreenshotOperationState: Equatable {
    case idle
    case saving
    case succeeded(URL)
    case failed(String)

    var isVisible: Bool {
        self != .idle
    }

    var isInFlight: Bool {
        self == .saving
    }
}

enum TrimExportOperationState: Equatable {
    case idle
    case warning(String)
    case preparing
    case exporting(progress: Double)
    case cancelling
    case cancelled
    case succeeded(URL)
    case failed(String)

    var isVisible: Bool {
        self != .idle
    }

    var isInFlight: Bool {
        switch self {
        case .preparing, .exporting, .cancelling:
            true
        case .idle, .warning, .cancelled, .succeeded, .failed:
            false
        }
    }

    var acceptsProgress: Bool {
        switch self {
        case .preparing, .exporting:
            true
        case .idle, .warning, .cancelling, .cancelled, .succeeded, .failed:
            false
        }
    }
}
