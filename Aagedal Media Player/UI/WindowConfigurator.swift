// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSViewRepresentable that configures the NSWindow for video playback:
// aspect ratio lock, traffic light visibility, background colour.

import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    static let baseMinWidth: CGFloat = 460
    static let baseMinHeight: CGFloat = 360

    let aspectRatio: CGFloat?
    let videoSourceSize: NSSize?
    let showTrafficLights: Bool
    var onWindowAvailable: ((NSWindow) -> Void)?

    final class Coordinator: NSObject {
        var lastAspectRatio: CGFloat?
        var savedAspectRatio: CGFloat?
        var lastSourceSize: NSSize?
        weak var observedWindow: NSWindow?
        nonisolated(unsafe) var willEnterFullScreen: NSObjectProtocol?
        nonisolated(unsafe) var didExitFullScreen: NSObjectProtocol?
        var lastTrafficLightAlpha: CGFloat = 0

        deinit {
            if let token = willEnterFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didExitFullScreen { NotificationCenter.default.removeObserver(token) }
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

        /// Set contentMinSize based on the aspect ratio (or base values if nil).
        func applyMinSize(_ window: NSWindow, ratio: CGFloat?) {
            if let ratio, ratio > 0 {
                let minW = max(WindowConfigurator.baseMinWidth, WindowConfigurator.baseMinHeight * ratio)
                let minH = max(WindowConfigurator.baseMinHeight, WindowConfigurator.baseMinWidth / ratio)
                window.contentMinSize = NSSize(width: minW, height: minH)
            } else {
                window.contentMinSize = NSSize(width: WindowConfigurator.baseMinWidth,
                                               height: WindowConfigurator.baseMinHeight)
            }
        }

        func observeWindow(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            willEnterFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.savedAspectRatio = self.lastAspectRatio
                    self.lastAspectRatio = nil
                    window.contentResizeIncrements = NSSize(width: 1, height: 1)
                }
            }

            didExitFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let ratio = self.savedAspectRatio, ratio > 0 else { return }
                    window.contentAspectRatio = NSSize(width: ratio, height: 1)
                    self.lastAspectRatio = ratio
                }
            }
        }
    }

    final class ConfiguratorNSView: NSView {
        weak var coordinator: Coordinator?
        var onWindowAvailable: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let coordinator else { return }
            coordinator.observeWindow(window)
            window.isRestorable = false
            window.setFrameAutosaveName("")
            window.backgroundColor = .black
            coordinator.applyTrafficLightAlpha(window, animated: false)
            // Set initial minimum size (base values; updated when video loads).
            coordinator.applyMinSize(window, ratio: nil)

            // Force a consistent default size after SwiftUI finishes its layout pass.
            DispatchQueue.main.async {
                let defaultW: CGFloat = 711
                let defaultH: CGFloat = 400
                let titlebarHeight = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
                let totalHeight = defaultH + titlebarHeight
                let origin = NSPoint(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - totalHeight
                )
                window.setFrame(NSRect(x: origin.x, y: origin.y, width: defaultW, height: totalHeight),
                                display: false)
            }

            onWindowAvailable?(window)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ConfiguratorNSView {
        let view = ConfiguratorNSView()
        view.setFrameSize(.zero)
        view.coordinator = context.coordinator
        view.onWindowAvailable = onWindowAvailable
        return view
    }

    func updateNSView(_ nsView: ConfiguratorNSView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
        guard let window = nsView.window else { return }
        onWindowAvailable?(window)
        let coordinator = context.coordinator

        coordinator.observeWindow(window)

        let ratio = aspectRatio
        let sourceSize = videoSourceSize
        let trafficLightAlpha: CGFloat = showTrafficLights ? 1 : 0
        let isFullScreen = window.styleMask.contains(.fullScreen)

        DispatchQueue.main.async {
            // Aspect ratio and min size — only apply when not in fullscreen,
            // and only when the ratio actually changes.
            if !isFullScreen {
                if let ratio, ratio > 0 {
                    let ratioChanged = coordinator.lastAspectRatio != ratio
                    let sourceSizeChanged = sourceSize != nil && sourceSize != coordinator.lastSourceSize

                    if ratioChanged || sourceSizeChanged {
                        coordinator.lastAspectRatio = ratio
                        coordinator.savedAspectRatio = ratio
                        coordinator.lastSourceSize = sourceSize
                        coordinator.applyMinSize(window, ratio: ratio)
                        window.contentAspectRatio = NSSize(width: ratio, height: 1)

                        if let contentView = window.contentView {
                            let frame = window.frame
                            let titlebarHeight = frame.height - contentView.bounds.height

                            let useSourceResolution = UserDefaults.standard.bool(forKey: "openAtSourceResolution")

                            var newWidth: CGFloat
                            var newHeight: CGFloat

                            if useSourceResolution,
                               let sourceSize,
                               sourceSize.width > 0, sourceSize.height > 0 {
                                // Size to source resolution at 1:1 pixels (divide by backing scale for Retina)
                                let backingScale = window.backingScaleFactor
                                newWidth = sourceSize.width / backingScale
                                newHeight = sourceSize.height / backingScale
                                if UserDefaults.standard.bool(forKey: "clampWindowToScreen"),
                                   let screen = window.screen ?? NSScreen.main {
                                    let maxFrame = screen.visibleFrame
                                    let maxW = maxFrame.width * 0.9
                                    let maxH = (maxFrame.height - titlebarHeight) * 0.9
                                    if newWidth > maxW || newHeight > maxH {
                                        let scale = min(maxW / newWidth, maxH / newHeight)
                                        newWidth *= scale
                                        newHeight *= scale
                                    }
                                }
                            } else {
                                // Default: adjust height from current width
                                newWidth = contentView.bounds.width
                                if ratio < 0.75 {
                                    newWidth = min(newWidth, 380)
                                }
                                newHeight = newWidth / ratio
                            }

                            let totalHeight = newHeight + titlebarHeight
                            let centerAfterResize = UserDefaults.standard.bool(forKey: "centerWindowAfterResize")
                            let origin: NSPoint
                            if centerAfterResize,
                               let screen = window.screen ?? NSScreen.main {
                                let visibleFrame = screen.visibleFrame
                                origin = NSPoint(
                                    x: visibleFrame.midX - newWidth / 2,
                                    y: visibleFrame.midY - totalHeight / 2
                                )
                            } else {
                                origin = NSPoint(
                                    x: frame.origin.x,
                                    y: frame.origin.y + frame.height - totalHeight
                                )
                            }
                            let contentRect = NSRect(
                                x: origin.x,
                                y: origin.y,
                                width: newWidth,
                                height: totalHeight
                            )
                            window.setFrame(contentRect, display: true, animate: false)
                        }
                    }
                } else {
                    if coordinator.lastAspectRatio != nil {
                        coordinator.lastAspectRatio = nil
                        coordinator.savedAspectRatio = nil
                        coordinator.lastSourceSize = nil
                        window.contentResizeIncrements = NSSize(width: 1, height: 1)
                        coordinator.applyMinSize(window, ratio: nil)
                    }
                }
            }

            coordinator.lastTrafficLightAlpha = trafficLightAlpha
            coordinator.applyTrafficLightAlpha(window)
        }
    }
}
