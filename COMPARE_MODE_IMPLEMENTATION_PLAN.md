# Compare Mode Implementation Plan

## Product goal

Make Aagedal Media Player the fastest private macOS tool for visually checking
one master against another. A user should be able to open a primary file, add a
comparison file, align them by source timecode when possible, and inspect them
with one shared transport.

Release promise:

> Compare any two masters frame-accurately — side by side, with a draggable
> wipe, A/B switching, or a visual difference view — even when their codecs
> differ.

## Product principles

- Keep ordinary single-file playback just as fast and minimal as it is today.
- Keep comparison local and offline. Compare Mode must not require an account
  or upload media.
- Treat the primary file as source A and the comparison file as source B.
- Make alignment and audio ownership explicit. Never play two audio streams by
  accident.
- Prefer a dedicated per-window compare session over the existing global
  multi-window command broadcast.
- Label display-space difference views honestly; they are not objective image
  quality metrics unless color transforms and pixel formats are normalized.

## Architecture

Each player window owns one `CompareSessionController` beside its existing
primary `PlayerController`. The compare session owns:

- a secondary `PlayerController`;
- the selected compare presentation mode;
- source-timecode or relative alignment mapping;
- paired transport operations;
- loading, failure, and teardown state;
- temporary suppression of source B audio.

The existing primary controller remains authoritative for the timeline,
timecode display, trim points, screenshots, scopes, and metadata inspector.
This avoids changing established single-file behavior and gives later phases a
clear place to add source selection for those tools.

## Phase 1 — Usable comparison foundation

Status: Foundation implemented on 2026-09-02. Live backend/drift validation
remains before Phase 1 acceptance is complete.

- [x] Define the implementation plan and release boundaries.
- [x] Add a window-owned compare session with cancellation-safe secondary-file
  loading.
- [x] Align B to A using embedded source timecode when both files provide it;
  otherwise align their relative timelines.
- [x] Add A, B, and side-by-side presentation modes in one window.
- [x] Route play/pause, seeks, scrubbing, frame stepping, and shuttle commands
  through paired transport while Compare Mode is active.
- [x] Suppress B audio without changing the user's persisted mute preference.
- [x] Clearly label A and B, filenames, and alignment mode.
- [x] Exit Compare Mode cleanly when A is replaced or the window closes.
- [x] Add pure tests for alignment, clamping, and overlap calculations.

Acceptance:

- Adding B never opens another app window.
- B starts at the frame matching A's source timecode when possible.
- Shared transport keeps both sources within one primary-frame duration while
  paused, seeking, stepping, and during normal 1x playback correction.
- Only A is audible by default.
- Removing or replacing B tears down its decoder and pending work.
- Single-file playback behavior and shortcuts remain unchanged.

## Phase 2 — Visual comparison tools

Status: Planned Phase 2 implementation completed through 2026-09-03. Live
mixed-backend visual validation remains.

- [x] Add a draggable vertical/horizontal wipe.
- [x] Add opacity overlay with an adjustable blend amount.
- [x] Add a display-space difference view with gain control.
- [x] Normalize geometry for differing resolutions, pixel aspect ratios, and
  rotations.
- [x] Warn when frame rates, duration, transfer function, color primaries, or
  range differ.
- [x] Add keyboard shortcuts for A/B toggle and moving the wipe.

Acceptance:

- Switching modes does not rebuild either decoder.
- The wipe remains interactive during 1x playback.
- Difference rendering is GPU-backed and does not block the main actor.

## Phase 3 — Professional QC integration

- [ ] Let scopes inspect A, B, or their difference.
- [ ] Add explicit A/B audio switching and optional channel comparison.
- [ ] Export a comparison still containing both filenames, timecode, alignment,
  and selected technical metadata.
- [x] Add a compact mismatch summary for codec, raster, frame rate, color,
  audio layout, and duration.
- [ ] Add safe-area and aspect-ratio overlays shared across both sources.

## Phase 4 — Review workflow

- [ ] Add frame-accurate markers and notes on the comparison timeline.
- [ ] Store notes in a non-destructive sidecar file.
- [ ] Export CSV/PDF reports and common NLE marker formats.
- [ ] Include annotated comparison stills in reports.

## Technical risks

### Playback drift

Starting two independent decoders together is not frame lock. The session needs
one master clock, measured drift, and conservative correction. Phase 1 may seek
B when drift exceeds a threshold; later profiling can determine whether rate
nudging produces smoother correction.

### Mixed backends

ProRes RAW uses AVFoundation while other media normally uses MPV. Compare Mode
must work with MPV/MPV, AVFoundation/AVFoundation, and mixed pairs. Tests should
keep alignment and transport independent of backend details.

### Color interpretation

Two backends may tone-map or convert color differently. A display-space
difference view must say so in the UI. Objective PSNR/SSIM/VMAF-style analysis
belongs in a separate offline feature with defined normalization.

### Resource use

Two UHD/HDR decoders plus scopes can be expensive. Add signposts for decoder
load and drift correction, and profile the oldest supported Apple Silicon Mac.
The UI should permit reduced-frame comparison if sustained real-time playback
is not possible.

## Verification matrix

- Same codec, resolution, rate, and source timecode.
- Different codecs with matching raster and rate.
- Different source-timecode starts with an overlapping interval.
- Missing source timecode on one or both files.
- 23.976, 24, 25, 29.97 DF/NDF, 50, 59.94 DF/NDF, and 60 fps.
- Different durations and no-overlap source-timecode ranges.
- Rotated and anamorphic media.
- SDR/HDR and mixed-transfer-function pairs.
- MPV/MPV and mixed MPV/AVFoundation playback.
- Rapidly replace B, remove B during preparation, and close the window while B
  is loading.

## Release and marketing work

- Add a first-run callout for Compare Mode without interrupting playback.
- Replace the README's “just checking playback” positioning with a professional
  inspection message.
- Record a short demo: source vs encode, timecode alignment, wipe, difference,
  and comparison-still export.
- Benchmark sustained drift and CPU/GPU load on the oldest supported Mac.
