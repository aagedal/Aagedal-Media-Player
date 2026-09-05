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
- source-timecode, relative, or session-local manual alignment mapping;
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
metadata loading or suspended backend preparation, and preservation of
specific decoder failures. A real `NSWindow` close integration test now
verifies that window teardown cancels an in-flight B metadata load, restores
audio safety, resets both controller paths, and rejects the late completion.
The 2026-09-05 hardening pass also added an explicit cancel action while B
metadata loads, made decoder-readiness timeout a terminal preparation result,
invalidated late review-sidecar save completions, suspended drift correction
during active scrubbing, and synchronized B when A loops across every backend
pairing.
Real-decoder
integration coverage now verifies source-timecode alignment, paired
seek/play/pause, frame stepping, scrubbing, forward shuttle acceleration,
one-frame drift convergence, and audio suppression for
MPV/MPV, AVFoundation/AVFoundation, and both mixed-backend directions using
generated fixtures. Additional mixed-backend fixtures now verify relative
alignment when neither file has source timecode while codec, raster, frame
rate, audio codec, and duration differ. A disjoint source-timecode pair also
verifies no-overlap detection, keeps B parked on its first frame while A plays,
and surfaces the overlap status in the toolbar. Boundary-aware transport also
holds B at either clamp until the primary timeline enters the shared range in
the active playback direction. Eight-second
sustained playback coverage now verifies that all four backend pairings keep
advancing and reconverge within one second of a transient out-of-frame
excursion. Additional mixed-backend checks exercise every supported frame-rate
variant, normalize a rotated anamorphic source against a square-pixel portrait
source, and retain explicit SDR/HDR metadata and scope-transfer distinctions.
Longer production-resolution validation
remains before Phase 1 acceptance is complete. A repeatable opt-in profiler now
generates UHD 10-bit HDR pairs and runs the same drift assertions for an
extended duration across all four backend pairings, while reporting wall time,
CPU time, and peak resident memory. It also mounts the real comparison canvas
in both mixed-backend directions, repeatedly drives all seven visual modes and
their controls, measures main-actor responsiveness, and verifies decoder and
native-surface identity. The profiler runs serially with Release optimization,
injects configuration into a disposable test run, derives tolerances from the
fixture frame rate, and lets an excursion already active at the cutoff use only
its remaining one-second recovery window. The drift-duration assertion allows
one 25 ms sampling interval of measurement tolerance while the final one-frame
drift assertion remains strict. Both backends retain render outputs at the
configured profile resolution, while ordinary integration tests keep 320×180
outputs and a 960×540 hosted comparison canvas. A 30-second UHD HDR
decoder-only baseline passed on an M5 Pro with a 0.851-second worst recovery
and about 847 MiB peak resident memory. The extended eight-second visual smoke
run also passed there: both 3840×2160 canvases delivered 80 updates, covered all
seven modes, stayed under 51 ms worst main-actor delay, reconverged within
0.599 seconds, and used about 848 MiB peak resident memory. The profiler still
needs to be run for the defined 120-second-per-scenario release duration on the
oldest supported Apple Silicon Mac with a complementary Instruments GPU/thermal
pass. An eight-second UHD HDR
profile of the new live-scope workload passed on the M5 Pro in both
mixed-backend directions: A, B, and display difference produced 95/99 fresh
scope renders, worst main-actor delay stayed under 87 ms, drift recovery stayed
within the one-second-plus-sample allowance, and peak resident memory for the
complete serial profile was about 855 MiB. After making AVFoundation correction
latency-aware, a complete 30-second-per-scenario UHD HDR development profile
also passed on the M5 Pro: all eight serial decoder, visual, and live-scope
scenarios met the drift gates; the worst excursion was 0.739 seconds, the
largest main-actor delay was 96 ms, the visual passes delivered 300 updates
each, and aggregate peak resident memory was about 853 MiB. This battery-power
development result does not replace the 120-second base-M1 release gate. The
profiler now rejects skipped or metric-free XCTest runs and validates reusable
fixtures against the test suite's manifest contract.
The release-validation continuation requires each of the eight expected
scenario/backend combinations exactly once, preserves original Xcode failure
codes, retains logs on setup failures, and samples thermal observations every
two seconds throughout the run. Its standalone rejection tests cover missing,
duplicate, unexpected, malformed, skipped, and empty scenario output.
A full 120-second-per-scenario UHD HDR development run now passed all eight
scenarios on the M5 Pro: worst drift recovery was 0.910 seconds, worst
main-actor delay was 96 ms, and both visual passes delivered 1,200 updates.
The MPV/AVFoundation scope workload was within one frame for 84.4% of samples
while meeting the recovery gate; this is not continuous frame lock. See
`docs/COMPARE_MODE_PROFILE_2026-09-05.md` for all results and conditions.
Historical profiler CPU/RSS values above are command-accounting observations;
XCTest's separately hosted app may be excluded. Direct app CPU/GPU/memory and
thermal measurements still require Instruments, along with the controlled
base-M1 release run.
The full project test suite also passed after the loop, scrub, lifecycle, and
AVFoundation correction changes, preserving the existing single-file coverage.
In this continuation the initial complete Release suite passed 274 tests, and
all 64 focused tests passed after the additional evidence-export/sidecar fixes.
Static analysis and all 61 release-preflight checks passed. A later complete
suite attempt encountered native audio startup timeouts and playback stalls;
a fresh-process disjoint-range retry reproduced the failure. A clean complete
suite remains required before release. The dated profile record retains both
the successful benchmark and these later unsuccessful playback checks.

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

Status: Planned Phase 2 implementation completed through 2026-09-03. Hosted
real-decoder coverage mounts the actual comparison canvas and cycles every
visual mode during playback in both mixed-backend directions, verifying that
the MPV and AVFoundation surfaces and decoder instances remain stable. The
opt-in production profiler now sustains that workload at the configured render
size, sweeps wipe, overlay, and difference controls, checks paired drift, and
measures main-actor scheduling delay. A symmetric half-resolution live-render
option now reduces both native surfaces and the comparison composite while
leaving source files, scopes, and exports unchanged. Hands-on pixel and
Instruments GPU validation at production resolution remains.
Exported-still pixel tests now verify distinct A/B corner colors, orientation,
letterbox/pillarbox placement, divider pixels, and PNG pixel preservation.
An additional 25-aspect-pair matrix verifies side-by-side picture/guide
registration at full and reduced resolution on an odd-sized canvas. Empty
still annotations also return safely without accessing nonexistent CoreText
attributes. These checks do not replace live-compositor pixel validation.

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
The primary timeline now marks the playable A/B overlap and its adjacent legend
shows the signed, frame-accurate B offset.
Timestamp-aware scope-difference frame pairing is also implemented with bounded
A/B capture histories. The production profiler now mounts live mixed-backend
scopes in both directions, cycles A, B, and display difference with gain,
requires fresh waveform/vectorscope output, and sweeps every safe-area and
aspect-ratio guide combination. Its first eight-second UHD HDR run passed on an
M5 Pro; Instruments GPU/thermal validation and a full-duration run on the
oldest supported Mac remain.

- [x] Let scopes inspect A, B, or their display-space difference.
- [x] Add explicit A/B audio switching.
- [x] Add optional channel-by-channel audio comparison after the cross-backend
  per-channel mute/solo architecture planned for Audio QC.
- [x] Export a comparison still containing both filenames, timecode, alignment,
  and selected technical metadata.
- [x] Add a compact mismatch summary for codec, raster, frame rate, color,
  audio layout, and duration.
- [x] Add safe-area and aspect-ratio overlays shared across both sources.
- [x] Show the comparison offset and overlapping interval on the timeline.

## Phase 4 — Review workflow

Status: Frame-accurate comparison notes, pair-specific non-destructive JSON
sidecars, CSV/PDF review reports with annotated A/B stills, and source-A marker
interchange for DaVinci Resolve, Final Cut Pro, and Avid Media Composer are
implemented through 2026-09-04. Editor round-trip validation remains.
FCPXML now explicitly preserves DF/NDF display interpretation and safely
encodes pasted Unicode and tabs while replacing XML-invalid characters.
Parser-based tests verify 29.97/59.94 drop-frame minute-boundary positions and
text integrity. Follow `docs/COMPARE_MODE_INTERCHANGE.md` for the remaining
editor import/re-export evidence.
Sidecar loading and writing now reject duplicate note identifiers, invalid
positions/rates, and values that overflow frame arithmetic. Invalid documents
remain untouched, and rejected saves do not suppress a later valid revision.
FCPXML also reduces rational timestamps before multiplication and reports an
actionable export error when the actual media rate makes a timestamp
unrepresentable, even if a sidecar supplied a different stored rate.

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
bounded backend-aware correction: MPV can use a temporary rate adjustment,
while AVFoundation uses a latency-compensated precise seek when it cannot
sustain faster-than-realtime UHD decoding. The 30-second-per-scenario M5 Pro
profile confirms those bounds under that development load; the 120-second
base-M1 release profile remains outstanding.

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
The UI now permits symmetric half-resolution live comparison if sustained
full-frame rendering is not possible. Changing render resolution intentionally
uses the paired reload path so MPV cannot retain a stale MoltenVK destination.

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
automated lifecycle tests. A suspended backend-selection test also verifies
that stopping the compare session tears down B and rejects the decoder's late
completion. Window-close integration now drives a real `NSWindow` close while
B metadata is loading and verifies that the late completion cannot recreate
its decoder. Small real-decoder
fixtures now cover MPV/MPV, AVFoundation/AVFoundation, and both mixed-backend
directions for timecode alignment, shared transport, and eight seconds of
sustained playback without a decoder stall or an out-of-frame excursion that
persists longer than one second. Mixed-backend fixtures also cover relative
alignment with simultaneous codec/raster/rate/duration differences, plus a
disjoint source-timecode range whose B decoder remains parked while A plays.
Generated integration checks now cover isolated
rate variants, rotated/anamorphic pairing, and SDR/HDR pairing. The full
raster/color matrix and 120-second release-floor production run still require
hands-on validation. Hosted mixed-backend checks mount `ComparePlayerView`,
cycle all seven presentation modes during playback, move both wipe variants,
verify that neither native surface nor decoder is rebuilt, and exercise every
safe-area/aspect-ratio guide combination. In profiling mode those checks use
the configured production render size, repeatedly sweep the visual controls
for the full observation, measure main-actor response, and apply the same
decoder-advance and drift-recovery assertions. Separate hosted scope passes
exercise A, B, and timestamp-paired display difference in both mixed-backend
directions. Hands-on pixel correctness plus Instruments GPU utilization and
thermal behavior remain manual gates.

## Release and marketing work

- [x] Review the separate `IMPROVEMENT_PLAN.md` and
  `FOLLOW_UP_IMPROVEMENT_PLAN.md` before release preparation. Both mark their
  engineering phases complete; `docs/RELEASE.md` now requires reviewing them
  and the outstanding `PRODUCT_ROADMAP.md` gates for each candidate. Historical
  completion does not replace current tests, analysis, and release preflight.
- [x] Add a first-run callout for Compare Mode without interrupting playback.
- [x] Replace the README's “just checking playback” positioning with a professional
  inspection message.
- [x] Prepare deterministic source-derived demo fixtures and a release-demo run
  sheet.
- [ ] Record the short demo: source vs encode, timecode alignment, wipe,
  difference, and comparison-still export. Follow
  `docs/COMPARE_MODE_DEMO.md`; the recording and final imagery remain manual.
- [ ] Benchmark sustained drift and CPU/GPU load on the oldest supported Mac.
  The gate is a 120-second-per-scenario automated run plus the Instruments pass
  on the base 2020 M1 MacBook Air defined in
  `docs/COMPARE_MODE_PERFORMANCE.md`.

Run `scripts/profile-compare-mode.sh` for the automated decoder/drift baseline,
then follow `docs/COMPARE_MODE_PERFORMANCE.md` for the Instruments visual-mode
and GPU validation.

## Manual alignment follow-up — 2026-09-05

The alignment control accepts a signed total B offset in seconds or source-A
frames, with one-frame nudges and an Automatic reset. The mapping is
`B time = A time + offset`; manual values replace the automatic offset.
It updates the timeline overlap, playback mapping, and newly captured review
positions. Existing notes retain their original A/B positions. Replacing or
removing B clears the override; reloading the same pair retains it. Invalid or
unrepresentable values are rejected. See `docs/COMPARE_MODE_ALIGNMENT.md` for
operation and validation. Hands-on verification remains in the release matrix.

Verification: the expanded 290-test suite passes with no skips, including
manual alignment, boundary holds, and automatic restoration on both
MPV/AVFoundation directions. Xcode static analysis passes, and release preflight
passes all 61 checks. This does not replace the oldest-supported-hardware,
hands-on accessibility, or editor round-trip release gates.

## Inspection loupe follow-up — 2026-09-05

The roadmap's initial loupe is implemented with pointer-following 2×/4×/8×
magnification, pinning, accessible picture-position sliders, and paired A/B
previews at the same normalized picture coordinate. It uses bounded capture
from the existing decoders and independent AV output ownership alongside
scopes. The previews are display-space, independently sampled images; exact
source-pixel 1:1, whole-viewport zoom, and production/hands-on validation remain
in `PRODUCT_ROADMAP.md` and `docs/INSPECTION_LOUPE.md`.

The paused-step pixel check exposed a pre-existing AVFoundation seek issue:
adding the comparison offset could leave a Double infinitesimally below the
intended frame boundary, then conversion to a 600-tick CMTime truncated it to
the preceding frame. AV seeks now use explicitly rounded 120,000-tick times,
including initial preparation and readiness replays. The regression verifies
both backend clocks and changed loupe pixels after a mapped 24 fps frame step.

Verification: the complete Release suite passes 319 tests with zero failures
and no skips, including both mixed-backend loupe checks and 32 rendered-pixel
cases across magnifications and display scales. Xcode static analysis and all
61 release-preflight checks pass. The hands-on and hardware gates remain open.

## Loupe registration and audio-layout continuation — 2026-09-05

Selected-track audio details now show numbered A/B channel roles, unmatched
roles, layout mismatches, and explicit positional pairing when layouts are
unknown. See `docs/COMPARE_MODE_AUDIO.md` for operation and remaining hands-on
routing/accessibility checks.

Ten asymmetric fixtures now verify real paused captures on each backend,
including differing rasters, PAR, all quarter-turn rotations, horizontal and
vertical mirroring, and reflected quarter-turns. A separate 128-case lens
rendering matrix verifies normalized picture positions at different coded and
display aspects, magnifications, and display scales.

These checks exposed MPV losing reflection from QuickTime display matrices.
Playback preparation now detects reflected transforms and restores reflection
before MPV rotation, using VideoToolbox copyback and a vertical video filter for
reflected media. Playback, scopes, and loupe captures share the corrected output.
Unreflected media retains its existing decode path. The asynchronous transform
probe is guarded by playback-preparation identity and cancellation.

Verification: the complete Release suite passes 329 tests with zero failures
and no skips. Xcode static analysis and all 61 release-preflight checks pass.
End-to-end pointer registration in every live comparison mode, reflected
UHD/HDR filter performance, the base-M1 profile, accessibility, and editor
round-trips remain release gates.

## Pointer routing and reflected profiling continuation — 2026-09-05

The canvas hover handler now shares its production pointer routing with
rendered-lens tests. Another 120 paired lens renders cover all seven modes,
unequal A/B display and coded aspects, all magnifications, and 1×/2× scale.
Black-bar and divider regressions preserve the previous inspected point.
A fully B overlay now follows B's fitted geometry instead of A's, fixing
registration for differing aspect ratios. Native hover/fullscreen/resizing
validation remains a hands-on gate.

The profiler accepts `COMPARE_PROFILE_REFLECTED=1` for horizontally reflected
UHD HDR sources. It records reflection in the manifest and report, rejects
incompatible fixture reuse, and verifies both actual transforms in XCTest.
Twelve shell configuration checks supplement the metric rejection tests.
The first reflected run exposed an early-exit race in the loop-resume check:
it now waits for both playing and aligned states within the unchanged deadline
and drift tolerance. See `docs/COMPARE_MODE_REFLECTED_PROFILE_2026-09-05.md`
for the measured results and limits.

The complete Release suite passes 333 tests with no failures or skips. The
corrected reflected UHD/HDR smoke profile passes all eight scenarios, with
0.754-second worst recovery and 89 ms worst main-actor delay. The 120-second
base-M1 release and hands-on Instruments/loupe gates remain open.
Static analysis and all 61 release-preflight checks pass.

## Loupe cadence profiling continuation — 2026-09-05

The production profiler now includes paired-loupe workloads in both
mixed-backend directions, with simultaneous scopes. The hosted production
overlay sweeps picture positions and 2×/4×/8× magnification. Metrics record
changed-pixel captures per source, actual observation duration and capture
rates, maximum capture gaps, main-actor delay, and the existing playback drift
measurements. Closing the overlay verifies image/output release while scopes
continue. The shell validator now requires all ten scenario/backend records;
legacy eight-scenario, duplicate-loupe, and unknown-workload reports are rejected.

The 120-second base-M1 runs, direct Instruments CPU/GPU/memory measurements,
native-event registration, keyboard/VoiceOver, and editor round-trips remain
release gates. Exact 1:1 source pixels and whole-viewport pan/zoom remain deferred
until the loupe interaction is validated. See `docs/INSPECTION_LOUPE.md` and
`docs/COMPARE_MODE_PERFORMANCE.md` for the repeatable procedure.

The first UHD/HDR run exposed AVFoundation loupe captures using a timestamp
that became obsolete during background metadata awaits. Pixel-buffer acquisition
now occurs immediately at the current playback time; conversion stays in the
bounded background worker. Failed and corrected profile evidence is recorded in
`docs/INSPECTION_LOUPE_PROFILE_2026-09-05.md`.

Verification: all 335 Release tests pass with no failures or skips; Xcode static
analysis and all 61 release-preflight checks pass. Profiler rejection and
reflection-configuration checks also pass.

The complete ten-scenario reflected UHD/HDR smoke profile passes with no skips.
Loupe capture rates are 5.11–5.75 fresh frames per second, worst main-actor delay
is 116 ms, and worst drift recovery across all workloads is 0.732 seconds. The
report retains the initial capture failures and an intermediate scope-only
280 ms delay failure; no thresholds were relaxed for the final passing run.

## Manual loupe acceptance preparation — 2026-09-05

The remaining native-pointer, fullscreen, accessibility, and release-floor
performance gates now have an actionable run sheet at
`docs/INSPECTION_LOUPE_MANUAL_TESTS.md`, including transformed fixture names,
expected behavior for all seven modes, and a results template. No hands-on
checks have been recorded as passed.

Synthetic NSHostingView event injection did not provide representative native
input evidence: correctly typed events did not reliably reach the hover
handler without real desktop-pointer state. The experimental code was removed;
no product behavior changed. Existing coordinate/rendered-pixel tests remain,
and real pointer dispatch over native playback surfaces needs manual testing.

Exact source-pixel 1:1 remains deferred because MPV's display-space screenshot
can resample pixel aspect ratio/rotation; captured-bitmap pixel sizing alone
does not establish original source-pixel registration. Whole-viewport zoom/pan
remains sequenced after loupe interaction acceptance.

Verification after removing the experiment: all 335 Release tests pass with
zero failures and no skips; release preflight passes all 61 checks. The
retained changes are documentation only.

## Pinned loupe resize correction — 2026-09-06

A continuation audit found that a pinned loupe retained its original pointer
position after the window shrank. Vertical placement could then put the lenses
below the current canvas. Overlay placement now clamps both axes to the current
canvas, reduces margins when space is tight, and centers unavoidable overflow
when the canvas is smaller than the lenses. The inspected normalized picture
coordinate remains unchanged.

Three regression tests cover stale pointer coordinates after resize,
above/below placement, and small canvases. The manual acceptance run sheet now
explicitly includes pinning near the bottom-right corner before shrinking the
window. Native resizing, keyboard/VoiceOver, editor round trips, and the
release-floor hardware profile remain open gates.

Verification: all 338 Release tests pass with zero failures and no skips;
Xcode static analysis and all 61 release-preflight checks pass.
