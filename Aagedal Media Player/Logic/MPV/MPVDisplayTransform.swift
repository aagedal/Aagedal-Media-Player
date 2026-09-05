// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation

/// The bundled MPV preserves the rotation angle of a QuickTime display matrix
/// but drops its reflection. Restore that reflection before MPV rotates it.
nonisolated enum MPVDisplayTransform {
    static func requiresReflectionCorrection(url: URL) async -> Bool {
        guard ["mov", "mp4", "m4v", "qt"].contains(url.pathExtension.lowercased()) else { return false }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform) else { return false }
        return isReflected(transform)
    }

    static func isReflected(_ transform: CGAffineTransform) -> Bool {
        let determinant = transform.a * transform.d - transform.b * transform.c
        return determinant.isFinite && determinant < 0
    }
}
