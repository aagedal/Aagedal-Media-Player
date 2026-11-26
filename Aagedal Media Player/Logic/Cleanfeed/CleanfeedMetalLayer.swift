// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Offscreen CAMetalLayer subclass for MPV's dedicated cleanfeed follower.
// Forces readable drawables (framebufferOnly = false) and hooks each drawable's
// presentation completion to deliver the rendered GPU texture to the cleanfeed
// converter without needing any MPVKit modifications.

import CoreGraphics
import Foundation
import Metal
import QuartzCore
import os

final class CleanfeedMetalLayer: MPVMetalLayer {
    private let handlerLock = OSAllocatedUnfairLock<(@Sendable (any CAMetalDrawable, Bool) -> Void)?>(
        initialState: nil
    )

    nonisolated var onDrawablePresented: (@Sendable (any CAMetalDrawable, Bool) -> Void)? {
        get { handlerLock.withLock { $0 } }
        set { handlerLock.withLock { $0 = newValue } }
    }

    nonisolated override init() {
        super.init()
        configureForCleanfeed()
    }

    nonisolated override init(layer: Any) {
        super.init(layer: layer)
        configureForCleanfeed()
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForCleanfeed()
    }

    private nonisolated func configureForCleanfeed() {
        super.framebufferOnly = false
        displaySyncEnabled = false
        contentsScale = 1.0
        allowsNextDrawableTimeout = true
    }

    /// Keep drawables readable by Metal compute/blit encoders even if MoltenVK
    /// attempts to flip `framebufferOnly` back to `true` on swapchain creation.
    nonisolated override var framebufferOnly: Bool {
        get { false }
        set { super.framebufferOnly = false }
    }

    nonisolated override func nextDrawable() -> (any CAMetalDrawable)? {
        guard let drawable = super.nextDrawable() else { return nil }
        let isLinearEDR = Self.isLinearColorspace(colorspace)
        let lock = handlerLock
        drawable.addPresentedHandler { presented in
            guard let metalDrawable = presented as? any CAMetalDrawable,
                  let callback = lock.withLock({ $0 }) else { return }
            callback(metalDrawable, isLinearEDR)
        }
        return drawable
    }

    private nonisolated static func isLinearColorspace(_ colorSpace: CGColorSpace?) -> Bool {
        guard let name = colorSpace?.name else { return false }
        return name == CGColorSpace.extendedLinearSRGB
            || name == CGColorSpace.extendedLinearITUR_2020
            || name == CGColorSpace.extendedLinearDisplayP3
            || name == CGColorSpace.linearSRGB
            || name == CGColorSpace.linearITUR_2020
    }
}
