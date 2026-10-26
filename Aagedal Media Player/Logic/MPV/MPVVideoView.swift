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
    private var managesSurfaceReloads: Bool
    private var surfaceSize: CGSize
    private var hasAttachedDrawable = false
    private var metalLayer: MPVMetalLayer!

    // A replacement controller can find MPV still bound to the previous layer.
    // That rebind is the only case that recreates playback. Size changes reach
    // MPV in place through `MPVPlayer.updateSurfaceSize`.
    private var requiresReloadForReplacedDrawable = false
    private var hasRequestedSurfaceReload = false
    private var isReplacedDrawableReloadPending = false
    private var isDisappearing = false
    private let layoutReload = DeferredMainActorTask()

    init(player: MPVPlayer, managesSurfaceReloads: Bool, surfaceSize: CGSize) {
        self.player = player
        self.managesSurfaceReloads = managesSurfaceReloads
        self.surfaceSize = surfaceSize
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setManagesSurfaceReloads(_ managesSurfaceReloads: Bool) {
        self.managesSurfaceReloads = managesSurfaceReloads
        if !managesSurfaceReloads {
            layoutReload.cancel()
            isReplacedDrawableReloadPending = false
        }
    }

    /// SwiftUI can update a composited comparison surface without delivering
    /// viewDidLayout. Keep the actual native drawable at the proposed picture
    /// size, including when the controller is retained across view modes.
    func setSurfaceSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1 else { return }
        let proposalChanged = surfaceSize != size
        surfaceSize = size
        guard isViewLoaded else { return }
        // AppKit can align a fractional SwiftUI proposal to different native
        // bounds. Reapplying that same proposal on each playback update would
        // alternate the drawable size with viewDidLayout and rebuild MPV's
        // swapchain continuously. Preserve the settled frame until the actual
        // proposal changes, and size the drawable from the native bounds.
        if proposalChanged, view.frame.size != size { view.setFrameSize(size) }
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        applyDrawableSize(CGSize(
            width: view.bounds.width * metalLayer.contentsScale,
            height: view.bounds.height * metalLayer.contentsScale
        ))
        scheduleReloadForReplacedDrawable()
        attachDrawableIfSized()
    }

    private func attachDrawableIfSized() {
        guard !hasAttachedDrawable,
              surfaceSize.width.isFinite, surfaceSize.height.isFinite,
              surfaceSize.width > 1, surfaceSize.height > 1 else { return }
        hasAttachedDrawable = true
        requiresReloadForReplacedDrawable = player.attachDrawable(metalLayer)
        scheduleReloadForReplacedDrawable()
    }

    /// Sizes the Metal drawable and, once MPV owns the layer, tells it about
    /// the change so the swapchain and picture rectangle follow in place.
    private func applyDrawableSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1, metalLayer.drawableSize != size else { return }
        metalLayer.drawableSize = size
        // A replaced layer is not the one MPV renders into; its rebind reload handles it.
        if !requiresReloadForReplacedDrawable { player.updateSurfaceSize(size) }
    }

    override func loadView() {
        let valid = surfaceSize.width.isFinite && surfaceSize.height.isFinite
            && surfaceSize.width > 1 && surfaceSize.height > 1
        let view = NSView(frame: CGRect(origin: .zero, size: valid ? surfaceSize : .zero))
        view.autoresizingMask = [.width, .height]
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        metalLayer = MPVMetalLayer()
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if view.bounds.width > 1, view.bounds.height > 1 {
            metalLayer.drawableSize = CGSize(
                width: view.bounds.width * metalLayer.contentsScale,
                height: view.bounds.height * metalLayer.contentsScale
            )
        }
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = NSColor.black.cgColor

        // Layer-hosting: set layer before wantsLayer
        view.layer = metalLayer
        view.wantsLayer = true

        scalingLogger.info("viewDidLoad: bounds=\(String(describing: self.view.bounds)) initial drawableSize=\(String(describing: self.metalLayer.drawableSize))")

        // Initialize against the fitted SwiftUI picture size, not a temporary
        // 640×480 view: MPV can retain that initial destination rectangle even
        // after the Metal swapchain grows. Attach immediately. viewDidLayout is
        // *not* a reliable trigger
        // because SwiftUI's NSViewControllerRepresentable can recreate the
        // view at bounds matching the previous instance (same-aspect swap,
        // rapid Force Reloads), in which case viewDidLayout never fires
        // and mpv's drawable would never get attached — leaving the pending
        // loadfile stuck forever. Subsequent bounds changes from
        // viewDidLayout update drawableSize, and MPV follows them in place.
        attachDrawableIfSized()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isDisappearing = false
        scheduleReloadForReplacedDrawable()
    }

    override func viewWillDisappear() {
        isDisappearing = true
        layoutReload.cancel()
        isReplacedDrawableReloadPending = false
        super.viewWillDisappear()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = view.window else {
            scalingLogger.debug("viewDidLayout: no window yet (bounds=\(String(describing: self.view.bounds)))")
            return
        }

        let scale = window.screen?.backingScaleFactor ?? 2.0
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = scale

        // Fullscreen transitions and live resizes arrive here as bounds changes,
        // so no window notifications are needed: MPV's MoltenVK context follows
        // each drawableSize change directly.
        let newDrawableSize = CGSize(
            width: view.bounds.width * scale,
            height: view.bounds.height * scale
        )
        let oldDrawableSize = metalLayer.drawableSize
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if newDrawableSize.width > 1 && newDrawableSize.height > 1 {
            applyDrawableSize(newDrawableSize)
            scalingLogger.info("viewDidLayout: bounds=\(String(describing: self.view.bounds)) scale=\(scale) oldDrawable=\(String(describing: oldDrawableSize)) newDrawable=\(String(describing: newDrawableSize)) fullscreen=\(isFullScreen)")
        } else {
            scalingLogger.debug("viewDidLayout: bounds=\(String(describing: self.view.bounds)) skipped (newDrawable=\(String(describing: newDrawableSize)) <=1)")
        }
        scheduleReloadForReplacedDrawable()
    }

    /// Schedules the single rebind reload for a replacement controller. Playback
    /// updates repeat while SwiftUI settles, so a pending reload is kept rather
    /// than postponed on every update.
    private func scheduleReloadForReplacedDrawable() {
        guard managesSurfaceReloads, requiresReloadForReplacedDrawable, hasAttachedDrawable,
              !hasRequestedSurfaceReload, !isReplacedDrawableReloadPending, !isDisappearing,
              view.window != nil else { return }
        isReplacedDrawableReloadPending = true
        layoutReload.schedule(after: .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.isReplacedDrawableReloadPending = false
            guard let window = self.view.window else { return }
            if self.view.inLiveResize {
                // The rebind still has to happen once the drag ends.
                self.scheduleReloadForReplacedDrawable()
                return
            }
            guard self.managesSurfaceReloads, !self.isDisappearing, !self.hasRequestedSurfaceReload else { return }
            self.hasRequestedSurfaceReload = true
            self.requestReloadForSurfaceChange(window: window, reason: "replaced MPV drawable")
        }
    }

    /// Target the owning window's Force Reload path. Geometry recovery must
    /// work even when another player or an auxiliary panel is key.
    /// ContentView's handler calls
    /// `PlayerController.preparePlayback(startTime:resetAudioSelection:)`,
    /// which destroys+recreates the mpv context. That is required only for a
    /// rebind: `wid` is fixed at context creation, so a context still bound to
    /// a previous layer cannot adopt the replacement.
    private func requestReloadForSurfaceChange(window: NSWindow, reason: String) {
        guard managesSurfaceReloads else {
            scalingLogger.info("requestReloadForSurfaceChange: \(reason) — paired surface owns reload")
            return
        }
        scalingLogger.info("requestReloadForSurfaceChange: \(reason) — posting targeted surface reload to rebind mpv")
        NotificationCenter.default.post(.reloadPlayerSurface(targetWindow: window))
    }
}

// MARK: - SwiftUI Wrapper

struct MPVVideoView: NSViewControllerRepresentable {
    let player: MPVPlayer
    let keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool
    let managesSurfaceReloads: Bool
    let surfaceSize: CGSize

    func makeNSViewController(context: Context) -> MPVViewController {
        let viewController = MPVViewController(
            player: player,
            managesSurfaceReloads: managesSurfaceReloads,
            surfaceSize: surfaceSize
        )
        context.coordinator.viewController = viewController
        return viewController
    }

    func updateNSViewController(_ nsViewController: MPVViewController, context: Context) {
        nsViewController.setManagesSurfaceReloads(managesSurfaceReloads)
        nsViewController.setSurfaceSize(surfaceSize)
        context.coordinator.viewController = nsViewController
        context.coordinator.keyHandler = keyHandler
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(keyHandler: keyHandler)
    }

    final class Coordinator: NSObject, @unchecked Sendable {
        private nonisolated(unsafe) var monitor: Any?
        var keyHandler: (String, NSEvent.ModifierFlags, NSEvent.SpecialKey?) -> Bool
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
