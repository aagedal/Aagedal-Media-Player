// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Small diamonds below the track distinguish chapters from trim and review
/// markers. Seeking stays with the timeline gesture and the Chapters menu.
struct ChapterTimelineMarkers: View {
    let chapters: [TrackSelectionController.ChapterOption]
    let duration: Double
    let width: CGFloat

    var body: some View {
        if duration.isFinite, duration > 0, width.isFinite, width > 0 {
            ForEach(chapters.filter { $0.time.isFinite && $0.time >= 0 && $0.time <= duration }) { chapter in
                Image(systemName: "diamond.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .offset(
                        x: max(0, min(width - 6, width * CGFloat(chapter.time / duration) - 3)),
                        y: 6
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
