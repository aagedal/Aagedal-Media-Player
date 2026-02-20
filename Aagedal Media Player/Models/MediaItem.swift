// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct MediaItem: Identifiable, Equatable, Sendable {
    let id: UUID = UUID()
    var url: URL
    var name: String
    var size: Int64
    var durationSeconds: Double = 0.0
    var hasVideoStream: Bool = true
    var metadata: MediaMetadata?
    var loopPlayback: Bool = false

    var duration: String {
        guard durationSeconds > 0 else { return "--:--" }
        let totalSeconds = Int(durationSeconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    var formattedSize: String {
        let bytes = Double(size)
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024

        if bytes < mb {
            return String(format: "%.0f KB", bytes / kb)
        } else if bytes < 600 * mb {
            return String(format: "%.1f MB", bytes / mb)
        } else {
            return String(format: "%.1f GB", bytes / gb)
        }
    }

    var videoDisplayAspectRatio: Double? {
        if let ratioValue = metadata?.primaryVideoStream?.displayAspectRatio?.doubleValue {
            return ratioValue
        }
        if
            let width = metadata?.primaryVideoStream?.width,
            let height = metadata?.primaryVideoStream?.height,
            width > 0,
            height > 0
        {
            return Double(width) / Double(height)
        }
        return nil
    }

    var videoResolutionDescription: String? {
        guard let width = metadata?.primaryVideoStream?.width, let height = metadata?.primaryVideoStream?.height else {
            return nil
        }
        return "\(width) × \(height)"
    }
}
