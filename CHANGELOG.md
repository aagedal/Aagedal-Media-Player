# Changelog

All notable changes to Aagedal Media Player.

## [1.6.0] — 2026-05-24

### Added
- Sparkle in-app auto-updates.
- HDR support in the video scopes, plus active-track highlighting in the scope overlay.
- Boost slider in the audio waveform view for amplifying quiet audio.
- Show-all-waveforms option for multi-mono audio files.
- Chapter marker picker in the controls bar.
- Pixel Aspect Ratio and Display Aspect Ratio as separate rows in the metadata inspector.
- Space key as a play/pause shortcut.

### Changed
- MPV is now the default playback backend for every supported codec; AVPlayer is reserved for ProRes RAW, where VideoToolbox outperforms MPVKit.
- Reverse → forward (L / Shift+L) now switches direction instantly instead of decelerating through zero.
- Backward playback uses MPV's native reverse mode, with a timer-driven fallback for codecs that can't seek backward.
- Metadata extraction now uses SwiftExif (pure Swift) instead of bundling an `ffprobe` binary — smaller app, faster reads, no subprocess.
- Resolution row in the metadata inspector now reports the displayed dimensions for rotated videos (e.g. iPhone portrait HEVC reads `2160 × 3840` instead of `3840 × 2160`).
- Source repository and MPVKit dependency moved to Codeberg.

### Fixed
- Anamorphic AVC clips (1440×1080 with 4:3 PAR → 16:9 display) were rendering at 4:3 instead of 16:9.
- Rotated iPhone HEVC clips were rendering as small landscape strips inside portrait windows.
- Window and Vulkan swapchain sizes could drift out of sync — on first load, after a live-resize, on fullscreen enter/exit, and during the initial layout-settle. The player now auto-recovers in each case.
- Video was cropped when switching files in the same window.
- Hardened the MPV event loop and `loadfile` command against rare races on file switch.
- Memory leak from NotificationCenter observers in the scope and waveform panels.
- ffmpeg stderr pipe-buffer deadlock in long-running operations.
- Screenshots captured from interlaced sources are now deinterlaced before saving.
