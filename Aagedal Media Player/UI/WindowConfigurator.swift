// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSViewRepresentable that configures the NSWindow for borderless video playback:
// transparent titlebar, full-size content, aspect ratio lock, traffic light visibility.

import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    static let baseMinWidth: CGFloat = 480
    static let baseMinHeight: CGFloat = 345

    let aspectRatio: CGFloat?
    let showTrafficLights: Bool

    final class Coordinator: NSObject {
        var lastAspectRatio: CGFloat?
        var savedAspectRatio: CGFloat?
        weak var observedWindow: NSWindow?
        var willEnterFullScreen: NSObjectProtocol?
        var didExitFullScreen: NSObjectProtocol?
        var didBecomeKey: NSObjectProtocol?
        var lastTrafficLightAlpha: CGFloat = 0

        deinit {
            if let token = willEnterFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didExitFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didBecomeKey { NotificationCenter.default.removeObserver(token) }
        }

        /// Re-apply window chrome properties. Cheap to call repeatedly.
        func applyWindowAppearance(_ window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.backgroundColor = .black
        }

        func applyTrafficLightAlpha(_ window: NSWindow, animated: Bool = true) {
            let alpha = lastTrafficLightAlpha
            for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(buttonType),
                   let container = button.superview {
                    if container.alphaValue != alpha {
                        if animated {
                            NSAnimationContext.runAnimationGroup { ctx in
                                ctx.duration = 0.2
                                container.animator().alphaValue = alpha
                            }
                        } else {
                            container.alphaValue = alpha
                        }
                    }
                    break
                }
            }
        }

        func observeWindow(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            willEnterFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.savedAspectRatio = self.lastAspectRatio
                self.lastAspectRatio = nil
                window.contentResizeIncrements = NSSize(width: 1, height: 1)
            }

            didExitFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                guard let self, let ratio = self.savedAspectRatio, ratio > 0 else { return }
                DispatchQueue.main.async {
                    window.contentAspectRatio = NSSize(width: ratio, height: 1)
                    self.lastAspectRatio = ratio
                }
            }

            didBecomeKey = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                // macOS resets titlebar and traffic lights on activation —
                // re-apply after macOS finishes its updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self else { return }
                    self.applyWindowAppearance(window)
                    self.applyTrafficLightAlpha(window, animated: false)
                }
            }
        }
    }

    final class ConfiguratorNSView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let coordinator else { return }
            coordinator.observeWindow(window)
            coordinator.applyWindowAppearance(window)
            coordinator.applyTrafficLightAlpha(window, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ConfiguratorNSView {
        let view = ConfiguratorNSView()
        view.setFrameSize(.zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ConfiguratorNSView, context: Context) {
        guard let window = nsView.window else { return }
        let coordinator = context.coordinator

        coordinator.observeWindow(window)

        let ratio = aspectRatio
        let trafficLightAlpha: CGFloat = showTrafficLights ? 1 : 0
        let isFullScreen = window.styleMask.contains(.fullScreen)

        DispatchQueue.main.async {
            coordinator.applyWindowAppearance(window)

            // Aspect ratio — only apply when not in fullscreen
            if !isFullScreen {
                if let ratio, ratio > 0 {
                    // Enforce minimum size that respects both base minimums and the aspect ratio.
                    let minW = max(Self.baseMinWidth, Self.baseMinHeight * ratio)
                    let minH = max(Self.baseMinHeight, Self.baseMinWidth / ratio)
                    window.contentMinSize = NSSize(width: minW, height: minH)

                    if coordinator.lastAspectRatio != ratio {
                        coordinator.lastAspectRatio = ratio
                        coordinator.savedAspectRatio = ratio
                        window.contentAspectRatio = NSSize(width: ratio, height: 1)

                        if let contentView = window.contentView {
                            let currentWidth = contentView.bounds.width
                            let newHeight = currentWidth / ratio
                            let frame = window.frame
                            let titlebarHeight = frame.height - contentView.bounds.height
                            let contentRect = NSRect(
                                x: frame.origin.x,
                                y: frame.origin.y + frame.height - newHeight - titlebarHeight,
                                width: frame.width,
                                height: newHeight + titlebarHeight
                            )
                            window.setFrame(contentRect, display: true, animate: true)
                        }
                    }
                } else {
                    if coordinator.lastAspectRatio != nil {
                        coordinator.lastAspectRatio = nil
                        coordinator.savedAspectRatio = nil
                        window.contentResizeIncrements = NSSize(width: 1, height: 1)
                    }
                    window.contentMinSize = NSSize(width: Self.baseMinWidth, height: Self.baseMinHeight)
                }
            }

            coordinator.lastTrafficLightAlpha = trafficLightAlpha
            coordinator.applyTrafficLightAlpha(window)
        }
    }
}
