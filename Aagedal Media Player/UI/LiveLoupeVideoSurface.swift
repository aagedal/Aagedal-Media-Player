// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit
import Metal
import os

/// Counts completed presentations without reading pixels or wrapping drawables.
/// Used by the live-viewer acceptance workload to measure actual video output.
final class LiveLoupeMetalLayer: MPVMetalLayer {
    private nonisolated let presentations = OSAllocatedUnfairLock(initialState: UInt64(0))
    nonisolated var presentedFrames: UInt64 { presentations.withLock { $0 } }

    nonisolated override init() { super.init() }
    nonisolated override init(layer: Any) { super.init(layer: layer) }
    nonisolated required init?(coder: NSCoder) { super.init(coder: coder) }

    nonisolated override func nextDrawable() -> (any CAMetalDrawable)? {
        let drawable = super.nextDrawable()
        if let drawable {
            let counter = presentations
            drawable.addPresentedHandler { _ in counter.withLock { $0 &+= 1 } }
        }
        return drawable
    }
}

/// A lens-sized GPU surface. MPV zooms/pans internally, so magnification never
/// creates a huge drawable or downloads frames to CPU memory.
struct LiveLoupeVideoSurface: NSViewRepresentable {
    let session: LiveLoupeSession
    let size: CGSize
    let viewport: LoupeVideoViewport?
    let nearest: Bool

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView(frame: CGRect(origin: .zero, size: size))
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.session = session
        if let viewport { session.configure(viewport: viewport, nearest: nearest) }
        Task { @MainActor [weak view] in
            guard let view else { return }
            session.attachSurface(view.metalLayer)
        }
    }

    static func dismantleNSView(_ view: SurfaceView, coordinator: ()) {
        let session = view.session
        let layer = view.metalLayer
        Task { @MainActor in session?.detachSurface(layer) }
    }

    final class SurfaceView: NSView {
        let metalLayer = LiveLoupeMetalLayer()
        weak var session: LiveLoupeSession?

        override init(frame: NSRect) {
            super.init(frame: frame)
            metalLayer.framebufferOnly = true
            metalLayer.backgroundColor = NSColor.black.cgColor
            layer = metalLayer
            wantsLayer = true
            updateDrawable()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() { super.layout(); updateDrawable() }
        override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawable() }

        private func updateDrawable() {
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard size.width > 1, size.height > 1 else { return }
            let changed = metalLayer.drawableSize != size
            metalLayer.contentsScale = scale
            metalLayer.frame = bounds
            metalLayer.drawableSize = size
            if changed { session?.surfaceSizeChanged() }
        }
    }
}
