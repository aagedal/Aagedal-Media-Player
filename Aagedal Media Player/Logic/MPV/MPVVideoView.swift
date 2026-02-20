// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

// MARK: - View Controller (matches MPVKit demo pattern)

final class MPVViewController: NSViewController {
    let player: MPVPlayer
    private var metalLayer: MPVMetalLayer!

    init(player: MPVPlayer) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = NSView(frame: .init(x: 0, y: 0, width: 640, height: 480))
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        metalLayer = MPVMetalLayer()
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        view.layer = metalLayer

        player.attachDrawable(metalLayer)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        guard let window = view.window else { return }

        let scale = window.screen?.backingScaleFactor ?? 2.0
        let layerSize = view.bounds.size
        let newDrawableSize = CGSize(width: layerSize.width * scale, height: layerSize.height * scale)

        metalLayer.frame = CGRect(x: 0, y: 0, width: layerSize.width, height: layerSize.height)

        let currentSize = metalLayer.drawableSize
        let sizeChanged = abs(currentSize.width - newDrawableSize.width) > 1 ||
                         abs(currentSize.height - newDrawableSize.height) > 1

        if sizeChanged && newDrawableSize.width > 1 && newDrawableSize.height > 1 {
            metalLayer.drawableSize = newDrawableSize
            metalLayer.setNeedsDisplay()
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
        private var monitor: Any?
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
