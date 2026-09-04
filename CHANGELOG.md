# Changelog

All notable changes to Aagedal Media Player.

## [1.6.1] — Unreleased

### Added
- Drop-frame-correct SMPTE timecode handling and regression coverage for supported frame rates.
- Collision-safe, atomic screenshot and trim output with visible completion and failure actions.
- Cancellation-aware ffmpeg execution, bounded scope scheduling, and generated media fixtures.
- A reproducible optimized scope-performance matrix covering all resolution and update-rate settings.
- Consistent volume, mute, buffering, playback-error, keyboard, and accessibility behavior across playback backends.
- Previous/next keyboard navigation across supported media files in the current folder.
- Release preflight validation for version/build ordering, changelog and appcast metadata, Sparkle signatures and URLs, exported app signing, and bundled ffmpeg provenance.
- Reproducible 1, 8, and 24-hour multichannel audio-waveform performance profiling.
- Real-decoder Compare Mode fixtures for mixed-codec relative alignment and disjoint source-timecode ranges.
- Mixed-backend Compare Mode validation for paired stepping, scrubbing, forward shuttle, supported frame rates, rotated anamorphic geometry, and SDR/HDR metadata.
- Production-resolution Compare Mode profiling for the real hosted compositor,
  including sustained visual-control cadence and main-actor delay measurements.
- Mixed-backend live-scope profiling across A, B, and display-difference sources,
  plus production-size safe-area and aspect-ratio guide sweeps.
- A frame-accurate source-B offset readout and playable A/B overlap interval on
  the comparison timeline.

### Changed
- Split playback backends, track selection, media operations, window opening, overlays, settings, and command routing into focused components.
- Extract the update settings pane and publish typed update-check outcomes with retry guidance.
- Update the bundled ffmpeg executable to 9.0.1 with Developer ID signing, Hardened Runtime, and secure-timestamp preflight validation.
- Update SwiftMediaMetadata to 3.0.0 and use its renamed package product and importable module.
- Keep Main Thread Checker and Thread Performance Checker enabled while retaining the required MoltenVK Metal API Validation exception.
- Document and validate the intentional Apple-Silicon-only release architecture and security entitlements.
- Make Compare Mode performance profiling serial, optimized, frame-rate-aware,
  production-render-sized, and isolated from ordinary test runs.
- Make Compare Mode profiler cleanup non-interactive for read-only package
  checkout files.

### Fixed
- Prevented superseded scope frames and media-operation tasks from publishing stale results, and stopped screenshots or exports from surviving their owning player window.
- Kept sorted AVFoundation audio-track labels and backend selections aligned when display order differs from source stream order.
- Prevented superseded audio/chapter discovery and track-selection work from affecting a replacement file.
- Prevented queued playback observers and asynchronous AVFoundation readiness work from affecting a replacement file.
- Prevented queued MPV publisher updates from changing playback, geometry, HDR, or reverse state after the backend is replaced.
- Forwarded backend preparation, load, and end-file errors into actionable UI states.
- Kept playback controls and their keyboard focus rings visible in narrow player windows.
- Bounded long-recording waveform memory by streaming PCM directly into fixed-size accumulators.
- Restored bundled audio-decoder and EBU R128 capabilities required by waveform and LUFS analysis.
- Kept update status truthful after failures and recorded every successful manual or automatic fallback check.
- Prevented a Compare Mode readiness timeout from replacing a specific source-B decoder failure, and covered stale secondary metadata completions during rapid replacement and teardown.
- Prevented live scopes from starving when frame capture outpaces waveform and
  vectorscope computation.

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
