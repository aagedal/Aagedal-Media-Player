# Aagedal Media Player Product Roadmap

Last updated: 2026-09-05

## Product direction

Aagedal Media Player should grow from a fast playback utility into a focused,
private professional media-inspection tool for macOS.

Positioning:

> A fast, private professional media inspection player for macOS.

The product should remain smaller and faster than a full QC suite while making
its professional strengths—broad codec support, precise transport, timecode,
scopes, waveform inspection, metadata, and lossless trim—easy to discover.

## Roadmap principles

- Keep single-file playback immediate and uncluttered.
- Keep inspection local and offline; media should never require an upload.
- Build workflows from the app's existing strengths instead of accumulating
  unrelated tools.
- Make technical state visible: active source, alignment, synchronization,
  color/raster mismatches, and audio ownership should never be ambiguous.
- Require measurable playback correctness and bounded resource use before
  marketing a professional feature.
- Preserve keyboard-first operation and accessibility in every new workflow.

## Priority summary

Scores use 1–5, where 5 is highest. Effort is an implementation estimate, not
a delivery commitment.

| Initiative | Customer value | Differentiation | Release fit | Effort | Target |
| --- | ---: | ---: | ---: | --- | --- |
| Compare Mode | 5 | 5 | 5 | XL | 1.7 |
| Loupe and viewport zoom | 4 | 4 | 5 | M | 1.7 |
| Visible QC toolbar | 4 | 4 | 5 | S | 1.7 |
| Product positioning and onboarding | 4 | 4 | 5 | S | 1.7 |
| Inspection timeline | 4 | 3 | 4 | M–L | 1.7–1.8 |
| Clear synchronization state | 3 | 3 | 4 | S–M | 1.7 |
| Audio QC | 5 | 4 | 4 | L | 1.8 |
| Review notes and reports | 4 | 3 | 3 | XL | 2.0 |

## 1.6.1 — Reliability foundation

Theme: make the current professional feature set trustworthy enough to build
larger workflows on top of it.

Status: Engineering complete; release preparation remains.

The completed work is tracked in `IMPROVEMENT_PLAN.md` and
`FOLLOW_UP_IMPROVEMENT_PLAN.md`. It includes correct SMPTE timecode, safe and
atomic output, cancellation-aware media operations, bounded scope and waveform
work, actionable playback errors, accessibility, backend isolation, and release
preflight checks.

Release gates:

- [ ] Complete final release build, signing, notarization, and update-feed
  validation.
- [ ] Run the documented playback/backend smoke matrix on representative media.
- [ ] Update screenshots and public release notes to reflect the current UI.
- [ ] Publish the accumulated reliability work before expanding the 1.7 beta.

## 1.7 — Compare & Inspect

Theme: compare any two masters confidently without leaving the player.

This is the next release's headline. The detailed technical sequence lives in
`COMPARE_MODE_IMPLEMENTATION_PLAN.md`.

Release promise:

> Compare any two masters frame-accurately—side by side, with a draggable
> wipe, A/B switching, or a visual difference view—even when their codecs
> differ.

### Milestone A — Comparison foundation

Status: Implemented and validated with generated real-decoder fixtures. The
oldest-supported-hardware release profile remains a separate release gate.

- [x] Load source B inside the current window.
- [x] Align by source timecode with relative-start fallback.
- [x] Provide A, B, and side-by-side presentation modes.
- [x] Share transport, seeking, scrubbing, frame stepping, and shuttle control.
- [x] Keep B silent by default without changing persisted mute preferences.
- [x] Add cancellation-safe replacement and teardown.
- [x] Add pure alignment and overlap tests.
- [x] Validate MPV/MPV, AVFoundation/AVFoundation, and mixed-backend pairs.
- [x] Measure sustained drift and confirm correction stays within one A-frame at
  normal speed.

### Milestone B — The demo-worthy comparison tools

- [x] Add a draggable vertical and horizontal wipe.
- [x] Add instant A/B switching with a dedicated keyboard shortcut.
- [x] Add opacity overlay with an adjustable blend amount.
- [x] Add a GPU-backed display-space difference view with gain control.
- [x] Normalize rotation, pixel aspect ratio, and display geometry.
- [x] Add explicit A/B audio monitoring.
- [x] Export a comparison still containing filenames, timecode, view mode, and
  selected technical metadata.

### Milestone C — Make professional inspection visible

The current interface hides important tools behind menus and shortcuts. Add a
compact QC toolbar that remains quiet during playback but makes the product's
purpose obvious.

- [x] Add visible Compare, Scopes, Waveform, and Inspector controls.
- [x] Use selected/active states that remain legible over light and dark video.
- [x] Keep every action keyboard reachable and VoiceOver-labelled.
- [x] Add a first-run callout that introduces Compare Mode without blocking
  playback.
- [x] Replace the README's “quickly just checking playback” language with the
  product positioning above.
- [ ] Refresh README and release imagery around a real inspection workflow.

### Milestone D — Detail inspection without resizing the window

Add a loupe first, then reuse its coordinate and magnification model for an
optional pan-and-zoom viewport. The loupe preserves full-frame context and is
the more useful default for quick inspection.

Status: Initial display-space loupe implemented on 2026-09-05. It follows the
pointer inside the fitted picture, supports 2×/4×/8× magnification, pinning,
and keyboard-accessible position sliders. Compare Mode displays paired A/B
previews at the same normalized picture coordinate. Capture is capped at 10 fps
with one worker per source and independent scope-output ownership. Production
performance, transformed live-pixel registration, and hands-on accessibility
validation remain before milestone acceptance. The complete 319-test Release
suite passes with no skips, including mixed-backend capture and rendered-pixel
checks; static analysis and all 61 release-preflight checks also pass.

- [x] Show a pointer-following loupe over the fitted video without changing the
  player window or playback layout.
- [x] Offer fixed magnifications of 2×, 4×, and 8×.
- [ ] Offer a verified 1:1 source-pixel view accounting for Retina display scale.
  MPV's current screenshot path may resample for display geometry, so this
  cannot yet be presented as exact source-pixel inspection.
- [x] Allow the loupe to be pinned so the pointer can operate playback controls.
- [x] Refresh from the active decoder while paused, seeking, stepping, and
  playing, with bounded capture work. Production-resolution cadence remains a
  validation gate; the preview is capped at 10 fps.
- [x] In Compare Mode, inspect the same normalized image coordinate in paired
  A/B loupes. Samples are independently captured, not frame-locked.
- [ ] Complete live-pixel validation for differing raster sizes, pixel aspect
  ratios, rotations, and letterbox/pillarbox regions. Pure picture-coordinate
  mapping excludes black bars; the capture path uses display-oriented imagery.
- [ ] Add optional whole-viewport zoom and pan after the loupe interaction is
  proven, with a one-action return to Fit.
- [x] Describe loupe imagery as display-space output without RGB/code values.
- [x] Make activation, magnification, pinning, and reset available from the
  keyboard and accessible without precise pointer movement. Hands-on VoiceOver
  and Full Keyboard Access validation remains.

Acceptance:

- Activating or moving the loupe never resizes the window or shifts controls.
- The magnified region stays registered to the source point at every supported
  rotation and pixel aspect ratio.
- A/B loupe inspection uses the same picture coordinate after comparison
  geometry normalization.
- Closing the loupe releases any capture/render work immediately.

### Milestone E — Comparison-aware information

- [x] Show persistent A/B identity and compact codec, raster, frame-rate,
  duration, color-space, transfer-function, and audio-layout mismatches.
- [x] Show the comparison offset and overlapping interval on the timeline.
- [x] Render existing chapter markers directly on the timeline.
- [x] Explain whether alignment is source-timecode, relative, or a manual offset.
- [x] Allow a manual frame/time offset when embedded timecode is missing or
  intentionally different. The alignment control accepts signed seconds or
  source-A frames, supports one-frame nudges, and restores automatic alignment.
  Overrides are session-local and reset when B is replaced or removed.

### Milestone F — Clarify synchronization

Compare Mode should replace the multi-window settings puzzle for the common
two-file workflow. Ordinary multi-window synchronization remains useful, but
its scope and state must be explicit.

- [x] Show when playback-command synchronization is active.
- [x] Distinguish transport synchronization from one-shot timecode alignment in
  settings and menus.
- [x] Explain that ordinary windows are synchronized but not continuously
  frame-locked.
- [x] Provide a direct “Compare these windows” path where technically safe, or
  document why a file must be reopened inside a compare session. See
  `docs/WINDOW_SYNCHRONIZATION.md` for scope, ownership, and the reopen workflow.

The September 5 implementation adds observable participant counts and an active
transport-sync indicator. Hands-on keyboard/VoiceOver and live-media checks
remain part of the 1.7 verification gate, not implied by these code completions.
The expanded 290-test suite passes without skips; static analysis and the
61-check release preflight also pass.

### 1.7 release gates

- [ ] Pass the comparison verification matrix in
  `COMPARE_MODE_IMPLEMENTATION_PLAN.md`.
- [ ] Profile two-stream UHD/HDR playback on the oldest supported Apple Silicon
  Mac.
- [x] Confirm all existing single-file playback tests and shortcuts remain
  unchanged.
- [ ] Record the release demo: source versus encode, automatic alignment, A/B,
  wipe, difference view, mismatch summary, and comparison-still export. Use
  `docs/COMPARE_MODE_DEMO.md`; synchronized loupe remains a separate milestone.
- [ ] Complete a short hands-on beta with editors, colorists, or finishing
  artists using their own source/encode pairs.

## 1.8 — Audio QC and richer navigation

Theme: inspect the soundtrack and move through long-form media with the same
confidence as the picture.

### Audio QC

- [x] Add per-channel mute and solo without changing the encoded file.
- [ ] Add peak and true-peak meters with clear dBFS/dBTP units.
- [ ] Add live momentary and short-term loudness, plus integrated loudness over
  a selected range or full file.
- [ ] Show channel labels and layout mismatches clearly in Compare Mode.
- [x] Support A/B audio switching and optional channel-by-channel comparison.
- [ ] Define calibration, ballistics, hold behavior, and EBU/ATSC presets before
  presenting measurements as compliance information.
- [ ] Test and profile multichannel, multi-track, very long, and malformed
  sources without unbounded memory or background work.

### Inspection timeline

- [ ] Add lightweight thumbnail navigation that is generated lazily and cached
  within a bounded budget.
- [ ] Add visible chapter, trim, comparison-overlap, and mismatch markers.
- [ ] Add an overview/zoom model for long-form media without sacrificing precise
  frame stepping.
- [ ] Keep the minimal current timeline available when extra information is not
  useful.

### 1.8 release gates

- [ ] Validate meter accuracy against trusted reference files and tools.
- [ ] Confirm meter and thumbnail work remains bounded during long playback.
- [ ] Complete keyboard and VoiceOver coverage for channel controls and the
  richer timeline.

## 2.0 — Review & Report

Theme: turn an inspection finding into something another person can act on.

Review notes follow Compare Mode and Audio QC because they are more valuable
when attached to a strong inspection workflow.

- [ ] Add frame-accurate markers with severity, category, status, and notes.
- [ ] Support region/range notes as well as single-frame notes.
- [ ] Store review data in a documented, non-destructive sidecar format.
- [ ] Attach annotated A/B comparison stills to findings.
- [ ] Filter and navigate notes from the timeline.
- [ ] Export CSV and PDF reports.
- [ ] Export common NLE marker formats after validating round trips with target
  editors.
- [ ] Keep reports useful without requiring an account or cloud service.

Release gates:

- [ ] Sidecars survive media moves through a deliberate relinking workflow.
- [ ] Exports preserve frame rate, drop-frame rules, source timecode, and file
  identity without rounding errors.
- [ ] A complete review can be created and exported using only the keyboard.

## Later / evaluate after user validation

These ideas should not displace the committed inspection roadmap until direct
user evidence shows stronger demand.

- Playlists and screening queues.
- Safe-area, aspect-ratio, title/action-safe, and custom guide overlays.
- Offline objective analysis such as PSNR, SSIM, or VMAF with explicitly
  normalized inputs.
- Caption presence, timing, and safe-area checks.
- Optional batch preflight for a folder of deliverables.

## Roadmap maintenance

- Keep implementation detail in feature-specific plans; keep this document
  focused on product sequence, scope, and release gates.
- Move an initiative into a release only when its acceptance criteria and owner
  are clear.
- Update statuses when code lands, but do not mark a milestone complete until
  its live-media and performance gates pass.
- Re-rank Later items after every release using direct user feedback rather than
  feature count.
