// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit
import OSLog

// Scaling-diagnostic logger. Used by MPVViewController, MPVPlayer's
// video-params observer (which fires on a nonisolated mpv event loop),
// and PlayerController's playback-state changes so we can correlate
// Metal-layer drawableSize, mpv's reported source dims, fullscreen
// transitions, and play/pause in a single timeline. Logger is Sendable
// so a global non-isolated binding is safe.
nonisolated let scalingLogger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "scaling")

// MARK: - View Controller (matches MPVKit demo pattern)

final class MPVViewController: NSViewController {
    let player: MPVPlayer
    private var metalLayer: MPVMetalLayer!

    // nonisolated(unsafe) because we tear these down from `deinit` which runs
    // outside the main actor — matches the same pattern in WindowConfigurator.
    nonisolated(unsafe) private var willEnterFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var didEnterFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var willExitFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var didExitFullScreenObserver: NSObjectProtocol?
    private weak var observedWindow: NSWindow?

    init(player: MPVPlayer) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for token in [
            willEnterFullScreenObserver,
            didEnterFullScreenObserver,
            willExitFullScreenObserver,
            didExitFullScreenObserver,
        ].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func loadView() {
        let view = NSView(frame: .init(x: 0, y: 0, width: 640, height: 480))
        view.autoresizingMask = [.width, .height]
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        metalLayer = MPVMetalLayer()
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = NSColor.black.cgColor

        // Layer-hosting: set layer before wantsLayer
        view.layer = metalLayer
        view.wantsLayer = true

        scalingLogger.info("viewDidLoad: bounds=\(String(describing: self.view.bounds)) initial drawableSize=\(String(describing: self.metalLayer.drawableSize))")

        // Attach immediately. viewDidLayout is *not* a reliable trigger
        // because SwiftUI's NSViewControllerRepresentable can recreate the
        // view at bounds matching the previous instance (same-aspect swap,
        // rapid Force Reloads), in which case viewDidLayout never fires
        // and mpv's drawable would never get attached — leaving the pending
        // loadfile stuck forever. Subsequent bounds changes from
        // viewDidLayout update drawableSize, and MoltenVK recreates the
        // swapchain to match.
        player.attachDrawable(metalLayer)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        installFullScreenObservers(on: view.window)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = view.window else {
            scalingLogger.debug("viewDidLayout: no window yet (bounds=\(String(describing: self.view.bounds)))")
            return
        }
        // Install fullscreen observers lazily here too — viewDidLayout
        // is the earliest point we're guaranteed to have a window.
        if observedWindow !== window {
            installFullScreenObservers(on: window)
        }

        let scale = window.screen?.backingScaleFactor ?? 2.0
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = scale

        // Update drawableSize so MoltenVK detects the surface change and
        // recreates its Vulkan swapchain. Do NOT call setNeedsDisplay() —
        // that triggers a Core Animation display cycle that races with
        // MoltenVK's background rendering and causes Metal validation errors.
        let newDrawableSize = CGSize(
            width: view.bounds.width * scale,
            height: view.bounds.height * scale
        )
        let oldDrawableSize = metalLayer.drawableSize
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if newDrawableSize.width > 1 && newDrawableSize.height > 1 {
            metalLayer.drawableSize = newDrawableSize
            scalingLogger.info("viewDidLayout: bounds=\(String(describing: self.view.bounds)) scale=\(scale) oldDrawable=\(String(describing: oldDrawableSize)) newDrawable=\(String(describing: newDrawableSize)) fullscreen=\(isFullScreen)")
        } else {
            scalingLogger.debug("viewDidLayout: bounds=\(String(describing: self.view.bounds)) skipped (newDrawable=\(String(describing: newDrawableSize)) <=1)")
        }
    }

    // MARK: - Fullscreen observers (diagnostic)

    private func installFullScreenObservers(on window: NSWindow?) {
        // Tear down any previous observers if the window changed.
        if observedWindow !== window {
            for token in [
                willEnterFullScreenObserver,
                didEnterFullScreenObserver,
                willExitFullScreenObserver,
                didExitFullScreenObserver,
            ].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(token)
            }
            willEnterFullScreenObserver = nil
            didEnterFullScreenObserver = nil
            willExitFullScreenObserver = nil
            didExitFullScreenObserver = nil
            observedWindow = window
        }
        guard let window else { return }

        willEnterFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                scalingLogger.info("willEnterFullScreen: bounds=\(String(describing: self.view.bounds)) drawable=\(String(describing: self.metalLayer.drawableSize))")
            }
        }
        didEnterFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                scalingLogger.info("didEnterFullScreen: bounds=\(String(describing: self.view.bounds)) drawable=\(String(describing: self.metalLayer.drawableSize))")
            }
        }
        willExitFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                scalingLogger.info("willExitFullScreen: bounds=\(String(describing: self.view.bounds)) drawable=\(String(describing: self.metalLayer.drawableSize))")
            }
        }
        didExitFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                scalingLogger.info("didExitFullScreen: bounds=\(String(describing: self.view.bounds)) drawable=\(String(describing: self.metalLayer.drawableSize))")
            }
        }
    }
}

// MARK: - SwiftUI Wrapper

struct MPVVideoView: NSViewControllerRepresentable {
    let player: MPVPlayer
    let keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool

    func makeNSViewController(context: Context) -> MPVViewController {
        let viewController = MPVViewController(player: player)
        context.coordinator.viewController = viewController
        return viewController
    }

    func updateNSViewController(_ nsViewController: MPVViewController, context: Context) {
        context.coordinator.viewController = nsViewController
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(keyHandler: keyHandler)
    }

    final class Coordinator: NSObject, @unchecked Sendable {
        private nonisolated(unsafe) var monitor: Any?
        private let keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool
        weak var viewController: MPVViewController?

        init(keyHandler: @escaping (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool) {
            self.keyHandler = keyHandler
            super.init()

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                let isKeyWindow = MainActor.assumeIsolated {
                    self.viewController?.view.window?.isKeyWindow ?? false
                }
                guard isKeyWindow else {
                    return event
                }

                guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return event }

                let handled = self.keyHandler(characters, event.modifierFlags, event.specialKey)
                return handled ? nil : event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
