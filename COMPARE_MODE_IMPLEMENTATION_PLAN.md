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

Status: Foundation implemented on 2026-09-02. Backend-clock drift sampling, a
one-primary-frame correction policy, backend-aware bounded rate correction
with a hard-seek fallback, full MPV audio-track suppression for inactive B
audio, and Instruments signposts for secondary load/drift profiling were added
through 2026-09-04.
Deterministic coverage now verifies rapid B replacement, stopping during
metadata loading, and preservation of specific decoder failures. Real-decoder
integration coverage now verifies source-timecode alignment, paired
seek/play/pause, one-frame drift convergence, and audio suppression for
MPV/MPV, AVFoundation/AVFoundation, and both mixed-backend directions using
generated fixtures. Eight-second sustained playback coverage now verifies that
all four backend pairings keep advancing and reconverge within one second of a
transient out-of-frame excursion. Longer production-resolution validation
remains before Phase 1 acceptance is complete. A repeatable opt-in profiler now
generates UHD 10-bit HDR pairs and runs the same drift assertions for an
extended duration across all four backend pairings, while reporting wall time,
CPU time, and peak resident memory. The profiler now runs only those four
pairings, serially and with Release optimization, injects configuration into a
disposable test run, derives tolerances from the fixture frame rate, and lets
an excursion already active at the cutoff use only its remaining one-second
recovery window. An eight-second UHD HDR smoke run passed on an M5 Pro with a
0.647-second worst recovery and about 840 MiB peak resident memory. It still
needs to be run for the full duration on the oldest supported Apple Silicon Mac
with a complementary Instruments GPU/thermal pass.

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

Status: Scope routing, the compact mismatch summary, explicit A/B and matching
channel audio monitoring, annotated comparison-still export, and shared
safe-area/aspect-ratio guides are implemented through 2026-09-04.
Timestamp-aware scope-difference frame pairing is also implemented with bounded
A/B capture histories. Live mixed-backend visual validation remains.

- [x] Let scopes inspect A, B, or their display-space difference.
- [x] Add explicit A/B audio switching.
- [x] Add optional channel-by-channel audio comparison after the cross-backend
  per-channel mute/solo architecture planned for Audio QC.
- [x] Export a comparison still containing both filenames, timecode, alignment,
  and selected technical metadata.
- [x] Add a compact mismatch summary for codec, raster, frame rate, color,
  audio layout, and duration.
- [x] Add safe-area and aspect-ratio overlays shared across both sources.

## Phase 4 — Review workflow

Status: Frame-accurate comparison notes, pair-specific non-destructive JSON
sidecars, CSV/PDF review reports with annotated A/B stills, and source-A marker
interchange for DaVinci Resolve, Final Cut Pro, and Avid Media Composer are
implemented through 2026-09-04. Editor round-trip validation remains.

- [x] Add frame-accurate markers and notes on the comparison timeline.
- [x] Store notes in a non-destructive sidecar file.
- [x] Export CSV reports.
- [x] Export PDF reports.
- [x] Export common NLE marker formats.
- [x] Include annotated comparison stills in reports.

## Technical risks

### Playback drift

Starting two independent decoders together is not frame lock. The session needs
one master clock, measured drift, and conservative correction. Phase 1 now uses
bounded backend-aware rate correction for ordinary drift and reserves a seek
for gross errors. Production-resolution profiling still needs to confirm the
chosen bounds under sustained decoder load.

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
- MPV/MPV, AVFoundation/AVFoundation, and mixed MPV/AVFoundation playback.
- Rapidly replace B, remove B during preparation, and close the window while B
  is loading.

The metadata-loading portion of rapid replacement and removal is covered by
automated lifecycle tests. Decoder teardown during backend preparation and
window close remains part of live mixed-backend validation. Small real-decoder
fixtures now cover MPV/MPV, AVFoundation/AVFoundation, and both mixed-backend
directions for timecode alignment, shared transport, and eight seconds of
sustained playback without a decoder stall or an out-of-frame excursion that
persists longer than one second. The full raster/color matrix and longer
production-resolution runs still require hands-on validation.

## Release and marketing work

- [x] Add a first-run callout for Compare Mode without interrupting playback.
- [x] Replace the README's “just checking playback” positioning with a professional
  inspection message.
- [ ] Record a short demo: source vs encode, timecode alignment, wipe, difference,
  and comparison-still export.
- [ ] Benchmark sustained drift and CPU/GPU load on the oldest supported Mac.

Run `scripts/profile-compare-mode.sh` for the automated decoder/drift baseline,
then follow `docs/COMPARE_MODE_PERFORMANCE.md` for the Instruments visual-mode
and GPU validation.
