# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS SwiftUI app (deployment target macOS 15.0) built with Xcode. The project file is at `Aagedal Media Player.xcodeproj`.

```bash
# Build from command line
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" build

# Clean build
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" clean build
```

There are no test targets, no linting tools, and no CI/CD configured.

**Important:** Metal API Validation must be OFF in the Xcode scheme's Run diagnostics. MoltenVK has a known race condition that causes crashes with validation enabled (KhronosGroup/MoltenVK#2226).

## Dependency: MPVKit

The sole external dependency is **MPVKit-GPL**, referenced as a local Swift package from `../../Aagedal-Media-Converter/MPVKit`. It bundles mpv 0.41.0, MoltenVK 1.4.0, and Libplacebo 7.351.0. The app also ships a bundled `ffmpeg` binary at `Aagedal Media Player/Aagedal Media Player/Binaries/ffmpeg` used for screenshot capture and trim export.

## Architecture

### Dual Playback Backend

The core architectural decision is a **dual-backend player**: AVPlayer (primary) with MPV as fallback.

- `PlayerController` (`Logic/PlayerController.swift`) is the central `@MainActor ObservableObject` managing both backends. It exposes published state (volume, playback time, speed, trim points, etc.) consumed by all views.
- **Backend selection** happens in `preparePlayback()`: AVPlayer is tried first. If AVPlayer fails (observed via `playerItem.status == .failed`), it falls back to MPV. Surround audio with non-ProRes video forces MPV immediately.
- MPV handles formats AVPlayer can't: MKV containers, VVC (H.266), APV, ProRes RAW, and certain surround audio configurations.
- The `useMPV` boolean on `PlayerController` controls which rendering path `PlayerView` shows.

### MPV Integration (`Logic/MPV/`)

MPV renders through Vulkan via MoltenVK onto a `CAMetalLayer`:

- `MPVPlayer` — Core wrapper around `mpv_handle`. Manages the mpv context, property observation, and event loop. Marked `@unchecked Sendable` for manual thread safety since mpv callbacks arrive on background threads.
- `MPVMetalLayer` — `CAMetalLayer` subclass handling HDR and drawable size management. Connected to mpv via the `wid` option (not the render API).
- `MPVVideoView` — `NSViewControllerRepresentable` embedding the Metal rendering surface into SwiftUI.
- `MPVProperty` — Typed property accessors for mpv options.

**Critical layer setup order:** `view.layer = metalLayer` must be set before `view.wantsLayer = true`.

### View Layer

- `ContentView` — Main window: shows `DropZoneView` when empty, `PlayerView` when a file is loaded. Manages overlay auto-hide, drag-drop, and window configuration.
- `PlayerView` — Renders either AVPlayer or MPV backend based on `controller.useMPV`. Handles JKL keyboard controls.
- `ControlsView` — Playback controls bar with play/pause, seek slider, speed controls, timecode display, trim in/out buttons.

### Supporting Services

- `MetadataService` — Async metadata extraction using FFmpeg, parses stream info (codecs, resolution, frame rates, color space).
- `FFmpegService` — Wraps the bundled ffmpeg binary for screenshots and lossless trim exports.
- `WindowManager` — Singleton managing multi-window state, coordinating synchronized playback across windows.

### Communication Pattern

Menu commands and global shortcuts route through `NotificationCenter` notifications (e.g., `.openFile`, `.togglePlayback`, `.captureScreenshot`), dispatched from `Aagedal_Media_PlayerApp.swift` Commands and handled in `ContentView`.

## Code Conventions

- All source files have `SPDX-License-Identifier: GPL-3.0-or-later` headers.
- Logging uses `OSLog` with subsystem `com.aagedal.MediaPlayer`.
- MARK comments (`// MARK: -`) used to organize sections within files.
