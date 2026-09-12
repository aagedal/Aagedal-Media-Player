# Changelog

All notable changes to Aagedal Media Player.

## [1.6.1] — Unreleased

### Added
- Bounded live source-audio decoding through the signed bundled FFmpeg, with explicit stream identity, disabled decoder gain processing, fixed Float32 buffering, actionable failures and versioned provenance. Transport lifecycle wiring remains pending.
- Reusable accessible live-meter presentation and persisted EBU, ATSC and custom reference guides, with exact threshold wording, A/B source choice and expandable provenance diagnostics. The presentation is not yet mounted in the app.
- Production split-mono programme loudness profiling with per-layout/range readings, separate process-memory measurements and rejection of sleep-interrupted timing evidence.
- Internal live-audio-meter calculation/display foundation with bounded source PCM, sample/true peaks, rolling Momentary/Short-term loudness and source-time ballistics. Playback integration and the meter panel remain pending.
- Programme loudness analysis for stereo or 5.1 stored as separate mono tracks, with explicit speaker mapping, whole-file/In–Out scope, cancellation and JSON provenance. Unassigned spare tracks are excluded.
- Bounded Broadcast WAVE metadata in classic RIFX files, with container-endian version/loudness fields and exact low/high-word sample references.
- Bounded iXML recording labels and track metadata in classic big-endian RIFX files, with independent XML encoding validation.
- Optional bounded APFS disk-full integration checks for review save/delete preservation and retry, alongside HFS+ coverage.
- Bounded UTF-32LE/BE iXML recording labels and track metadata, with strict Unicode validation and preserved parsing limits.
- Explicit migration of historical rounded review timebases into a new sidecar, with preview, retained frame coordinates, and deliberate copy reopening.
- Bounded UTF-16 iXML recording metadata and optional recording track names with explicit source-channel and file-interleave indexes.
- Bounded iXML recording labels in WAVE metadata and the inspector, including project, scene, take, sound roll, circled take, note, and file UID.
- Independent BS.1770-5 true-peak comparisons for the original ITU mono, stereo, and 5.1 programme references.
- Bounded classic big-endian RIFX metadata, with verified PCM/float decoding for offline loudness and waveforms.
- Independent PCM programme LRA comparisons alongside the original ITU integrated-loudness checks, with retained algorithm/source provenance.
- Bounded Broadcast WAVE tags in the inspector and copied JSON, including exact sample references, recording identity, coding history, and separately labeled embedded loudness.
- Optional official ITU eight-channel loudness verification with pinned originals and lossless speaker-order preparation for the conventional 7.1 analysis path.
- Reproducible optional loudness checks against original ITU mono, stereo, and 5.1 programme references, with pinned input hashes and retained measurement evidence.
- Bounded RF64/BW64 PCM and floating-point metadata reading for recordings beyond 4 GiB, with validated 64-bit chunk lengths and explicit speaker layouts.
- Reproducible multichannel loudness profiling for whole-file and early/late ranges, with separately sampled app and FFmpeg memory and validated result artifacts.
- Offline integrated loudness, loudness range, and true-peak analysis over selected In–Out points, with per-stream cancellation and measured-range provenance in copied metadata.
- Reproducible production timeline-thumbnail profiling with long-file seek latency, cache bounds, and sampled resident-memory measurements.
- Lazy timeline hover thumbnails with a bounded cache and cancellation on media replacement or dismissal.
- Per-window timeline zoom up to 64×, with a full-duration overview for panning and a one-action return to Fit.
- Deliberate comparison-review relinking after media moves, with an explicit A/B mapping preview, preserved findings, and protection against destination overwrites.
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
- Add explicit Retry Save for failed review-note writes, flush current text drafts before retrying, and prevent reload from discarding unsaved changes.
- Preserve pending review-note edits before switching copies, migrating timebases or exporting, and keep the original review active if source timing changes during migration saving.
- Preserve exact broadcast frame rates from decimal metadata so drop-frame review timecodes and editor-marker exports use the correct rational timebase. Existing reviews retain their stored rates and are never silently retimed.
- Comparison controls collapse into a scrollable popover when the toolbar is too narrow, keeping review, exit, loupe, and inspector actions visible.
- Apply standards-based rear-speaker weighting to explicitly identified conventional 7.1 loudness analysis while preserving source samples and true peaks; retain qualification for unknown or uncorrected layouts.
- Review-note accessibility labels identify seek, classification, inclusive-range, note-text, and deletion controls with source-A frame context; range actions adapt to available width and relink paths expose their full values.
- Timeline zoom starts in the timeline context menu; its extra controls appear only while zoomed and disappear on Fit.
- Volume now uses a continuous slider without tick marks, applies tracking changes directly to playback, and uses matching linear-amplitude percentages on MPV and AVPlayer.
- Preserve AppKit-aligned MPV surface dimensions across unchanged SwiftUI updates, avoiding repeated one-pixel swapchain reallocations during playback.
- Keep source A visible when entering Compare Mode, replacing B, or returning to single-source playback by retaining its native video surface.
- Editor-marker reports preserve full A/B source URLs, stored rational rates, and explicit source/relative B timecodes; oversized Avid notes fail visibly instead of being truncated.
- Timeline thumbnails invalidate cached images when a source URL changes and safely clamp extreme requested timestamps.
- Preserve recorded review timecodes after relinking; omit unavailable annotated stills with an explanation and reject ambiguous midnight-wrapping Resolve EDL markers.
- CSV review reports now append exact stored A/B rational frame rates and full source URLs, preserving existing column positions.
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
- Long-range programme loudness analysis now preserves every assigned channel using independent input contexts, correcting silent channel loss and reducing excessive shared-input buffering.
- Programme loudness analysis now cancels when its owning controller is released, including teardown outside inspector visibility callbacks.
- Header-verified WAVE demuxer selection prevents valid floating-point WAVE inputs being misidentified during offline loudness and waveform processing.
- Comparison reloads honor an explicit pause, reject superseded decoder resumes, and resume both sources after asynchronous backend readiness.
- Overlapping inspector refreshes retain the requested playback position and playing intent instead of restarting from a temporary zero decoder clock.
- A primary-source reload timeout reports the primary failure while preserving a ready comparison source.
- Playback failure messages wrap beside a narrow metadata inspector, with adaptive action layout and scrolling in short windows.
- Playback canvases respect inspector width, and recovery actions remain clear of the measured toolbar and transport controls.
- Inspector transitions refresh MPV's drawing size after layout settles; single-source reloads preserve playing/paused intent and suppress stale resume work.
- Prevent queued comparison-note saves from beginning after comparison mode closes or its source pair changes.
- Focused comparison toolbar controls receive Space and arrow keys without triggering playback; compact settings scroll to keyboard-focused controls and show focus rings.
- RIFX playback and trim export fail with conversion guidance while their decoder paths misinterpret big-endian sample bytes.
- Restore PCM and floating-point RIFF WAVE metadata and loudness access using bounded header reads and explicit surround speaker masks.
- Reject empty loudness selections instead of displaying FFmpeg’s default summary as a measured peak.
- Expose channel solo/mute checked states and stream-specific loudness controls to accessibility clients.
- Reject editor-marker exports with incompatible stored frame rates and keep mixed-rate review findings from reusing the wrong annotated PDF still.
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
