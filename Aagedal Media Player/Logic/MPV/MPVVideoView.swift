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

    // nonisolated(unsafe) because we tear these down from `deinit` which runs
    // outside the main actor — matches the same pattern in WindowConfigurator.
    nonisolated(unsafe) private var willEnterFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var didEnterFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var willExitFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var didExitFullScreenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var didEndLiveResizeObserver: NSObjectProtocol?
    private weak var observedWindow: NSWindow?

    /// Tracks the drawableSize we last observed in a viewDidLayout pass,
    /// for diagnostic correlation in the `scaling` log.
    private var lastNudgedDrawableSize: CGSize = .zero

    /// One-shot guard for the viewDidLayout-based auto Force Reload.
    /// When mpv attaches to a layer whose drawableSize is small (e.g.
    /// the layer hasn't been laid out into its final container yet —
    /// the common case when a file drops into a small/empty window),
    /// mpv's vo locks its dst rect to that small size. A subsequent
    /// viewDidLayout that grows the surface to its real size leaves
    /// mpv rendering 540×304-worth of pixels into a 1920×1080 swapchain
    /// — video collapses to the top-left at the pixelated initial size.
    /// We catch this by Force Reloading on the first ≥1.5× growth in
    /// viewDidLayout, but only once per MPVViewController instance —
    /// otherwise the reload itself (which recreates the view controller
    /// via SwiftUI's preparationID-based .id()) could re-enter and loop.
    private var hasAutoReloadedForLayoutJump = false
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
        if !managesSurfaceReloads { layoutReload.cancel() }
    }

    /// SwiftUI can update a composited comparison surface without delivering
    /// viewDidLayout. Keep the actual native drawable at the proposed picture
    /// size, including when the controller is retained across view modes.
    func setSurfaceSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1 else { return }
        surfaceSize = size
        guard isViewLoaded else { return }
        let oldDrawableSize = metalLayer.drawableSize
        if view.frame.size != size { view.setFrameSize(size) }
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.drawableSize = CGSize(
            width: size.width * metalLayer.contentsScale,
            height: size.height * metalLayer.contentsScale
        )
        handleDrawableGrowth(from: oldDrawableSize, to: metalLayer.drawableSize)
        attachDrawableIfSized()
    }

    private func attachDrawableIfSized() {
        guard !hasAttachedDrawable,
              surfaceSize.width.isFinite, surfaceSize.height.isFinite,
              surfaceSize.width > 1, surfaceSize.height > 1 else { return }
        hasAttachedDrawable = true
        player.attachDrawable(metalLayer)
    }

    deinit {
        for token in [
            willEnterFullScreenObserver,
            didEnterFullScreenObserver,
            willExitFullScreenObserver,
            didExitFullScreenObserver,
            didEndLiveResizeObserver,
        ].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
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
        // viewDidLayout update drawableSize, and MoltenVK recreates the
        // swapchain to match.
        attachDrawableIfSized()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        installWindowObservers(on: view.window)
    }

    override func viewWillDisappear() {
        layoutReload.cancel()
        super.viewWillDisappear()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = view.window else {
            scalingLogger.debug("viewDidLayout: no window yet (bounds=\(String(describing: self.view.bounds)))")
            return
        }
        // Install window observers lazily here too — viewDidLayout
        // is the earliest point we're guaranteed to have a window.
        if observedWindow !== window {
            installWindowObservers(on: window)
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

            lastNudgedDrawableSize = newDrawableSize

            handleDrawableGrowth(from: oldDrawableSize, to: newDrawableSize)
        } else {
            scalingLogger.debug("viewDidLayout: bounds=\(String(describing: self.view.bounds)) skipped (newDrawable=\(String(describing: newDrawableSize)) <=1)")
        }
    }

    /// Both AppKit layout and explicit SwiftUI sizing share the same one-shot
    /// decision. The explicit path must supply the drawable size from before
    /// mutation, otherwise a later layout observes equal sizes and misses it.
    private func handleDrawableGrowth(from old: CGSize, to new: CGSize) {
        guard managesSurfaceReloads, hasAttachedDrawable,
              !hasAutoReloadedForLayoutJump,
              let window = view.window,
              !window.styleMask.contains(.fullScreen),
              shouldAutoReloadForLayoutJump(from: old, to: new) else { return }
        hasAutoReloadedForLayoutJump = true
        // Explicit sizing runs inside updateNSViewController. Post on the next
        // main-actor turn so reload cannot publish state during SwiftUI's update.
        layoutReload.schedule { [weak self, weak window] in
            guard let self, let window, self.view.window === window else { return }
            self.requestReloadForSurfaceChange(
                reason: "drawableSize jumped \(Int(old.width))x\(Int(old.height)) → \(Int(new.width))x\(Int(new.height))"
            )
        }
    }

    // MARK: - Window observers (fullscreen + live resize)

    private func installWindowObservers(on window: NSWindow?) {
        // Tear down any previous observers if the window changed.
        if observedWindow !== window {
            for token in [
                willEnterFullScreenObserver,
                didEnterFullScreenObserver,
                willExitFullScreenObserver,
                didExitFullScreenObserver,
                didEndLiveResizeObserver,
            ].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(token)
            }
            willEnterFullScreenObserver = nil
            didEnterFullScreenObserver = nil
            willExitFullScreenObserver = nil
            didExitFullScreenObserver = nil
            didEndLiveResizeObserver = nil
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
                self.lastNudgedDrawableSize = self.metalLayer.drawableSize
                self.requestReloadForSurfaceChange(reason: "didEnterFullScreen")
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
                self.lastNudgedDrawableSize = self.metalLayer.drawableSize
                self.requestReloadForSurfaceChange(reason: "didExitFullScreen")
            }
        }
        // User-driven window resize: viewDidLayout updates drawableSize on
        // every tick, but the per-tick growth is well under the 1.5×
        // auto-reload threshold, so mpv's vo ends a drag with its dst rect
        // stranded at the pre-drag size — small videos collapse to the
        // top-left, large videos zoom into the upper-left quadrant. Fire
        // a Force Reload once the live-resize session ends; this fires
        // after the user releases the resize handle, not per drag tick.
        didEndLiveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                scalingLogger.info("didEndLiveResize: bounds=\(String(describing: self.view.bounds)) drawable=\(String(describing: self.metalLayer.drawableSize))")
                self.lastNudgedDrawableSize = self.metalLayer.drawableSize
                self.requestReloadForSurfaceChange(reason: "didEndLiveResize")
            }
        }
    }

    /// Trigger a Force Reload via the same `.reloadPlayer` command
    /// the menu uses. ContentView's handler calls
    /// `PlayerController.preparePlayback(startTime:resetAudioSelection:)`,
    /// which destroys+recreates the mpv context — the only thing we've
    /// found that reliably re-inits mpv's vo at the *current* layer
    /// surface size.
    ///
    /// Background on why lighter nudges don't work: with
    /// `wid=metalLayer + gpu-next/vulkan/moltenvk`, mpv's `vo->dwidth`
    /// /`dheight` are supposed to update inside `vk_acquire`, but in
    /// practice, after the layer's drawableSize grows underneath a
    /// paused stream (fullscreen entry), even a frame-forcing seek
    /// renders into the old dst rect. Property nudges (video-zoom=0)
    /// hit short-circuit checks. Only a full mpv-context recreate
    /// observably clears the stale state. Heavier than ideal, but it
    /// matches the user's known-working manual workaround.
    private func requestReloadForSurfaceChange(reason: String) {
        guard managesSurfaceReloads else {
            scalingLogger.info("requestReloadForSurfaceChange: \(reason) — paired surface owns reload")
            return
        }
        scalingLogger.info("requestReloadForSurfaceChange: \(reason) — posting .reloadPlayer to recreate mpv at current surface size")
        NotificationCenter.default.post(.reloadPlayer)
    }

    /// Returns true if the drawableSize grew ≥1.5× in either dimension,
    /// indicating the layer was likely pre-layout when mpv attached and
    /// has now settled to its real size. User-driven window-drag layout
    /// passes are well under this threshold (~2-4% per tick), so this
    /// is safe to act on without spamming reloads during resize.
    /// Shrinkage isn't checked: shrinking the surface doesn't strand
    /// mpv's dst rect — that's a growth-only bug.
    private func shouldAutoReloadForLayoutJump(from old: CGSize, to new: CGSize) -> Bool {
        guard old.width > 0, old.height > 0 else { return false }
        let widthGrowth = new.width / old.width
        let heightGrowth = new.height / old.height
        return widthGrowth >= 1.5 || heightGrowth >= 1.5
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
