# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS SwiftUI app (deployment target macOS 15.0) built with Xcode. The project file is at `Aagedal Media Player.xcodeproj`.

```bash
# Build from command line
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" build

# Clean build
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" clean build

# Resolve only the dependency revisions recorded in Package.resolved
xcodebuild -resolvePackageDependencies -project "Aagedal Media Player.xcodeproj" -onlyUsePackageVersionsFromResolvedFile

# Run unit tests
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS"

# Run Xcode static analysis
xcodebuild analyze -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS"
```

The shared scheme includes the `Aagedal Media Player Tests` XCTest target. No GitHub Actions workflows or separate linting tool are configured; build, test, and analysis verification is run locally.

**Important:** Metal API Validation must be OFF in the Xcode scheme's Run diagnostics. MoltenVK has a known race condition that causes crashes with validation enabled (KhronosGroup/MoltenVK#2226).

## Dependencies

Swift Package dependencies (all remote, resolved via SPM):

- **MPVKit-GPL** — `https://github.com/aagedal/MPVKit`, branch `main`. Truls's fork of MPVKit. Bundles mpv 0.41.0, FFmpeg n8.1.2, MoltenVK 1.4.2, Libplacebo 7.360.1.
- **SwiftExif** — `https://github.com/aagedal/SwiftExif`, semver `>= 1.8.0`. Pure-Swift metadata library (Truls's own), replaces the earlier ffprobe shell-out for stream metadata.
- **Sparkle** — `https://github.com/sparkle-project/Sparkle`, semver `>= 2.9.1`. Auto-update infrastructure.

The app also ships a bundled `ffmpeg` binary at `Aagedal Media Player/Binaries/ffmpeg`, used for screenshot capture and lossless trim export (not for metadata).

## Architecture

### Playback Backend

**MPV is the default backend** for every codec the app supports. AVPlayer is reserved for ProRes RAW — MPVKit-GPL can technically decode it but the colors are wrong and performance is significantly worse than VideoToolbox.

- `PlayerController` (`Logic/PlayerController.swift`) is the central `@MainActor ObservableObject` managing both backends. It exposes published state (volume, playback time, speed, trim points, etc.) consumed by all views.
- **Backend selection** happens in `preparePlayback()`: an async `isProResRAWFile(url:metadata:)` check decides between `setupMPV` and `setupAVPlayer`. The check uses cached SwiftExif metadata as the fast path and falls back to AVAsset's `CMFormatDescription` codec FourCC (`aprn`, `aprh`) when metadata isn't loaded yet.
- The `useMPV` boolean on `PlayerController` controls which rendering path `PlayerView` shows.
- `ContentView.openFile` calls a fast AVAsset preload (`loadQuickDescriptor`) that reads only the moov atom for display dimensions, then seeds `videoAspectRatio` / `videoSourceSize` on the controller via `loadMedia(_:initialAspectRatio:initialSourceSize:)` before `preparePlayback` runs. This ensures the SwiftUI tree and mpv's Vulkan swapchain initialize at the correct size on frame 1.

### MPV Integration (`Logic/MPV/`)

MPV renders through Vulkan via MoltenVK onto a `CAMetalLayer`:

- `MPVPlayer` — Core wrapper around `mpv_handle`. Manages the mpv context, property observation, and event loop. Marked `@unchecked Sendable` for manual thread safety since mpv callbacks arrive on background threads.
- `MPVMetalLayer` — `CAMetalLayer` subclass handling HDR and drawable size management. Connected to mpv via the `wid` option (not the render API).
- `MPVVideoView` — `NSViewControllerRepresentable` embedding the Metal rendering surface into SwiftUI.
- `MPVProperty` — Typed property accessors for mpv options.

**Critical layer setup order:** `view.layer = metalLayer` must be set before `view.wantsLayer = true`.

### View Layer

- `ContentView` — Main window: shows `DropZoneView` when empty, `PlayerView` when a file is loaded. Manages overlay auto-hide, drag-drop, and window configuration. `openFile` does the AVAsset descriptor preload before calling `controller.loadMedia`.
- `PlayerView` — Renders either AVPlayer or MPV backend based on `controller.useMPV`. Handles JKL keyboard controls. `playerAspectRatio` falls back to `MediaItem.videoDisplayAspectRatio` before the 16:9 default so the view survives teardown without snapping to a stale aspect.
- `ControlsView` — Playback controls bar with play/pause, seek slider, speed controls, timecode display, trim in/out buttons.
- `WindowConfigurator` — `NSViewRepresentable` that drives `contentAspectRatio` and content size from `controller.videoAspectRatio` / `videoSourceSize`.

### Supporting Services

- `MetadataService` — Async metadata extraction using **SwiftExif** (no ffmpeg shell-out). Actor with NSCache keyed on URL. Applies `AVAsset.preferredTransform` as the authoritative rotation source for QuickTime/MP4-family containers, then walks `MetadataMapper` to produce a `MediaMetadata` with resolved display dimensions, DAR, PAR, HDR side-data, etc.
- `FFmpegService` — Wraps the bundled ffmpeg binary for screenshots and lossless trim exports (not metadata).
- `WindowManager` — Singleton managing multi-window state, coordinating synchronized playback across windows.

### Communication Pattern

Menu commands and global shortcuts route through the typed `AppCommand` enum over one private `NotificationCenter` channel. Commands are dispatched from `Aagedal_Media_PlayerApp.swift` and `PlayerView`, then handled in `ContentView`; this retains synchronous multi-window broadcasts without untyped objects or `userInfo` dictionaries.

## Code Conventions

- All source files have `SPDX-License-Identifier: GPL-3.0-or-later` headers.
- Logging uses `OSLog` with subsystem `com.aagedal.MediaPlayer`.
- MARK comments (`// MARK: -`) used to organize sections within files.
