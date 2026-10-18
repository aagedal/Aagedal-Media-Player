// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Decorative only: the waveform underneath continues to own seek/scrub input.
struct WaveformLoudnessOverlay: View, Equatable {
    let result: FFmpegService.LUFSResult
    let duration: Double
    let title: String

    var body: some View {
        let momentary = WaveformLoudnessGeometry.segments(samples: result.samples ?? [],
            duration: duration, range: result.analysisRange, shortTerm: false)
        let shortTerm = WaveformLoudnessGeometry.segments(samples: result.samples ?? [],
            duration: duration, range: result.analysisRange, shortTerm: true)
        Canvas(rendersAsynchronously: true) { context, size in
            // Fixed LUFS scale stays comparable across tracks and analysis ranges.
            for value in [-60.0, -40, -20] {
                let y = size.height * (1 - (value + 70) / 70)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.18)),
                               style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                context.draw(Text("\(Int(value))").font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: 3, y: y - 5), anchor: .leading)
            }
            for (segments, color, dash) in [(momentary, Color.cyan, [CGFloat]()), (shortTerm, Color.yellow, [CGFloat(5), 3])] {
                for segment in segments {
                    var path = Path()
                    for (index, point) in segment.enumerated() {
                        let p = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    if segment.count == 1, let point = segment.first {
                        let rect = CGRect(x: point.x * size.width - 1.5, y: point.y * size.height - 1.5, width: 3, height: 3)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    } else {
                        context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 3.5)
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: dash))
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Text(title)
                Text("M").foregroundStyle(.cyan)
                Text("S ┄").foregroundStyle(.yellow)
                Text("LUFS −70…0")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(3)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
            .padding(4)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
