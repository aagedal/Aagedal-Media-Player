# Changelog

All notable changes to Aagedal Media Player.

## [1.6.1] — Unreleased

### Added
- Review-note severity, category, and status with searchable classifications and inclusive frame ranges, timeline bands, and CSV/PDF/editor export support.
- Schema 2 review sidecars that read legacy single-frame notes and protect structured findings from older app versions.
- Comparison stills record the inspection view selected at export time and identify their fixed side-by-side layout.
- Production-resolution paired-loupe profiling with simultaneous scopes, fresh-pixel cadence, capture-gap, responsiveness, and teardown checks.
- Opt-in reflected UHD/HDR comparison profiling with verified source transforms and safe fixture reuse.
- Selected-track A/B audio layout details, numbered channel labels, unmatched speaker roles, and explicit positional matching for unknown layouts.
- A pointer-following 2×/4×/8× inspection loupe with pinning, keyboard-accessible picture positioning, and paired A/B display previews.
- Manual comparison alignment in signed seconds or source-A frames, one-frame nudges, and automatic-alignment reset.
- Chapter markers on the playback timeline with current-chapter accessibility feedback.
- A visible multi-window transport-sync indicator and explicit transport versus one-shot alignment commands.
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
- Deterministic source-derived Compare Mode demo fixtures and a concise release
  recording run sheet.

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
- Make Compare Mode profiling reusable and auditable with validated fixture and
  build caches, retained artifacts, machine/power provenance, and rejection of
  skipped or metric-free runs.
- Keep paired playback synchronized through active timeline scrubbing and
  primary-file loop boundaries across all backend combinations.

### Fixed
- MPV comparison pictures now initialize and resize to their fitted panes instead of retaining a small bootstrap surface after window growth.
- Keep pinned inspection loupes inside the picture canvas when the window shrinks.
- Explicitly nonisolated comparison-guide geometry avoids a Swift `Shape` conformance error under main-actor default isolation.
- Prevent AVFoundation loupe freezes under UHD/HDR load by acquiring the current pixel buffer before asynchronous metadata and image conversion.
- Loupe pointer registration when a comparison overlay shows 100% B with an aspect ratio different from A.
- Preserve reflected QuickTime display transforms in MPV playback and decoder captures, including rotated mirrors, using a reflection-only VideoToolbox copyback/filter path.
- Prevent AVFoundation seeks from truncating a mapped frame boundary to the preceding frame because of floating-point rounding.
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
- Prevented late Compare Mode readiness and review-save completions from
  reviving failed or stopped state, and added a visible cancel action while B
  metadata is loading.
- Kept an AVFoundation secondary within the one-frame recovery budget under
  sustained UHD/HDR load by compensating its exact asynchronous seek latency.

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
