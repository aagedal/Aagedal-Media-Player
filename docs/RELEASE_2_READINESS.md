# 2.0 release readiness

Assessment updated: 2026-10-01. This is a prioritization of the existing
[product roadmap](../PRODUCT_ROADMAP.md), not a change to its committed scope.
It is based on the repository's plans and retained verification reports,
including the September 12 meter foundation and programme-loudness follow-up.
The same continuation now adds selected-track meter identity, typed player
events and clock policy, an owning per-window meter session and activating
panel, timestamp-verified decoder packets, an exact candidate-checkout
validation mode, explicit optional-test skips, mixed-backend paused-alignment
hardening, direct Review commands and focused review-field entry, deterministic paused-discontinuity ownership,
dynamic A/B meter fallback, and compressed 5.1 production-path coverage. No new
editor, spoken accessibility or release-floor hardware acceptance is implied.
The current continuation also fixes live-meter EOF drainage, adds stable native
review accessibility hooks, validates XCTest result/skip evidence, isolates two
order-sensitive mixed-backend transport checks, and binds release publication
to the verified source/package identity and uploaded artifact. The latest
hardening additionally verifies decoded channel-layout identity, prevents
unsupported-speed recovery from reviving a replaced meter source, exposes
stable frequently-updated meter accessibility elements, reconciles every
detailed XCTest outcome, and binds publication to the remote asset size/digest.
The September 15 continuation hardens HDR scope rendering and auxiliary
waveform source replacement, and adds an opt-in representative live-meter
profiler with fail-closed input identity, production-path, boundedness, memory,
routing, cancellation, and authoritative EOF evidence. The harness makes the
remaining acceptance repeatable; it does not itself supply authentic media,
trusted meter comparisons, long-play, or base-M1 evidence.
A generated 30-second video/AAC engineering smoke passes the final harness
schema across MPV playback, bundled FFmpeg/DSP measurement, routing mutation,
cancellation, and exact near-EOF drainage; it is plumbing evidence, not
representative-media acceptance.
The current continuation also exercises a generated compressed-AAC timestamp
gap through the production metadata, player, owning meter session, bundled
decoder and display path. It produces a cleared, actionable Unavailable state
with Retry rather than retaining stale measurement provenance. Three focused
Debug checks pass; producer-authentic malformed-media acceptance remains open.

The latest September 30 continuation proves and fixes two live-meter handoff/clock
races, preserves Review text correction ownership and retained failure context,
and raises candidate consumption to 738 aggregate tests. A fresh local universal
GPL/Metal CoreAudio build now passes independent identity/feature checks and
three authentic native profiles. The bounded MXF upstream candidate passes full
library tests, six complete exporter comparisons and three production app/cache
profiles; FX6 lifetime-peak increase falls from 368.516 to 18.5625 MiB. These
local candidates still require immutable dependency releases and shipping repins.
The first dependency receipt rejection and temporary metadata build's restored
stale-output incident remain explicit in the evidence. See the
[GPL/Metal build](evidence/coreaudio-gpl-metal-20260930/README.md),
[meter source races](evidence/live-meter-clock-handoff-20260930/README.md) and
[production MXF candidate](evidence/bounded-mxf-app-production-20260930/README.md).
Native spoken accessibility, hardware/soak, remaining editor and distribution
gates are still open.
The [canonical continuation verification](evidence/release-candidate-bounded-continuation-20260930/README.md)
passes for implementation commit `82597597ba3e4f854799b03857a916d864873cab`:
730 passes, eight allowlisted opt-in skips, both isolated transport checks,
static analysis and 61 preflight checks. The first missing-fixture rejection is
retained; existing explicit fixture generation resolved it without skip changes.
Later documentation retention does not replace matching-HEAD release checks.

The latest extended GPL/Metal observations pass 120 seconds on authentic FX6
mono, 90 seconds on authentic GoPro AAC stereo and 30 seconds on a local
six-channel AC-3 preparation. A DTS track fails with a reproduced 56-frame
timestamp deviation, beyond the unchanged one-millisecond limit. The failure
and all source/binary/output/power identities are retained. The production
runner now owns an awake assertion and retains power evidence on failure.
These observations do not close 30-minute, audible/device/surround hardware,
base-M1 or dependency publication gates. See
[extended native evidence](evidence/live-meter-gpl-metal-extended-20260930/README.md).

Repeated-import acceptance now passes thirty distinct production URLs per
original Sony input on a freshly built bounded-reader app. All ninety immediate
cache comparisons and three earliest-URL revisits preserve the complete model;
maximum post-first-release growth is 2.578/1.922/4.406 MiB and open descriptors
stay at nine. The explicit 32 MiB/four-descriptor budgets pass. The new opt-in
profile raises candidate consumption to 739 aggregate tests with nine named
optional skips; fresh integrated verification follows separately. See
[resource evidence](evidence/bounded-mxf-reimports-20260930/README.md).

The GPL repair has a verified unpublished package/source/input payload: eight
rebuilt assets, twenty-one auxiliary binary targets, twenty exact build inputs
and three committed source archives. Eleven mutation regressions and native
SwiftPM manifest/dependency checks pass. Public reconstruction/environment,
remote provenance, publication, fresh resolution and shipping repin remain
open. See [local publication preparation](evidence/coreaudio-publication-preparation-20260930/README.md).

Review now extends correction ownership to passive range callbacks: an
unrelated finding cannot save its changed range or displace the range selected
by action preflight. One new regression raises the candidate floor to 740 total
tests with nine named optional skips. The native app-binding attempt returns no
UI state and is cancelled after 639.7 seconds; keyboard/Full Keyboard Access/
spoken VoiceOver acceptance remains open. See
[range correction evidence](evidence/review-range-correction-ownership-20260930/README.md).

The resource/Review batch passes canonical optimized Release verification at
`dfc9137fe39e4c93ed01f63cbe81717dec01902e`: 731 passes, nine named opt-in skips
(740 total), both isolated transport checks, static analysis, all 61 preflight
checks and no-sleep/source/package evidence. Exact validation requires the new
range correction regression. A subsequent script-only validator follow-up has
thirteen passing focused checks and byte-identical stricter resource receipts;
app/test/package hashes still match the canonical run. Final script checks and
source identity are retained separately. See
[integrated continuation evidence](evidence/release-candidate-resource-continuation-20260930/README.md).
Matching-HEAD release consumption, dependency publication and native/hardware/
editor/distribution gates remain open.

The latest implementation continuation extends Review correction ownership to
ordinary Return/Apply/blur/current-frame failures, with three new regressions.
DTS qualification rules out source-zero seeking and coarse container timing
alone as grounds to accept the retained timestamp sequence; two codec/timestamp
regressions preserve the existing one-millisecond contract. See
[DTS qualification](evidence/live-meter-dts-timestamp-qualification-20260930/README.md).
Offline dependency tooling restores verified exact source commits and cached
inputs and declares missing compilation/environment prerequisites. Actual
reconstruction passes independent identity checks; see
[offline reconstruction](evidence/coreaudio-offline-reconstruction-20260930/README.md).
It does not publish or compile a dependency. Programme profiling now stays awake and retains
failed-test and sleep diagnostics. The clean eight-hour production matrix now
passes all six workloads, with consistent Stereo/5.1 whole/early/late tone
results and no sleep. Container-index memory scaling remains explicit;
representative content, hardware and elapsed-time soak gates remain open. See
[eight-hour evidence](evidence/programme-eight-hour-production-20260930/README.md). Canonical optimized Release verification passes at
`f5411b154dd6065a4901132a487b27ccf6d51058`: 736 passes, nine named opt-in skips,
both isolated transport directions, analysis and all 61 preflight checks. All
five new regressions pass exact detailed validation. The independent host-attributes
script correction has a final passing script gate and byte-identical app/test/pin
identity; see [integrated receipts](evidence/release-candidate-completion-20260930/README.md). The candidate floor is 745
aggregate tests plus both isolated mixed-backend checks. Native keyboard/spoken
accessibility, public dependencies, hardware/soak/editor and distribution gates
remain open.

The next continuation defers Review focus and passive commits while editing is
unavailable, restores the selected correction when editing resumes, and preserves
complete source URLs and exact per-finding capture rates/frames in PDF reports.
Three Review and two PDF regressions raise candidate consumption to 750 aggregate
tests plus both isolated transport directions. All sixty focused optimized
Release checks and script validators pass; all three PDF fixture pages are
visually checked. See [focused evidence](evidence/review-pdf-availability-20260930/README.md).
Canonical optimized Release verification passes at clean implementation commit
`4c91fe3e27b7d1af52adb94bc7c8ed0d76142443`: 741 passes, nine named skips,
both isolated transport directions, analysis, 61 preflight checks and final
source/package/cache/no-sleep identity. All five new regressions pass detailed
validation. See [integrated receipts](evidence/release-candidate-next-continuation-20260930/README.md). The offline dependency auditor passes 11,089 declared
source files and twenty input ZIPs, with upstream provenance now bound to the
receipt; public compilation/publication/repin remains open. See
[reconstruction audit](evidence/coreaudio-reconstruction-audit-20260930/README.md).
A separately qualified lossless DTS-HD MA extraction/remux preserves every coded
packet and decoded PCM sample and passes a twenty-second six-channel production
profile with exact EOF drainage. The new source clock does not qualify the
original rejected timestamps; stereo native output does not establish audible
surround/hardware acceptance. See
[DTS preparation](evidence/live-meter-dts-lossless-preparation-20260930/README.md).

The latest startup/PDF/payload continuation passes canonical optimized Release
verification at clean implementation commit `f2370dcfdee472e8c3aca24b8885d7aa0e489818`:
747 passes, nine named opt-in skips (756 total), both isolated mixed-backend
transport directions, static analysis, all 61 preflight checks and final
source/package/cache/no-sleep identity. All six new app regressions pass exact
detailed validation. Live meters now bound stalled startup before first PCM;
PDFs distinguish and preserve source/relative timecodes; comparison labels
retain extreme finite metadata safely and distinctly. The offline audit now
rejects undeclared build inputs and verifies exactly 11,109 payload files.
The canceled initial build and focused scientific-notation assertion failure
are retained beside the accepted run. Four PDF fixture pages are visually
checked. See [integrated receipts](evidence/release-candidate-startup-pdf-20260930/README.md).
Native accessibility/editor, public dependencies, audible/device/surround,
hardware/soak/base-M1 and distribution gates remain open. Documentation
retention does not replace matching-HEAD release consumption.

The October 1 continuation reveals filtered-out ordinary Review corrections,
rejects non-finite current live loudness, and enforces exact dependency stage
inventory including nonregular manifests. All fifty focused optimized Release
checks and the script-validator gate pass. Four new regressions raise aggregate
candidate consumption to 760 tests plus both isolated transport checks; all four
are required by exact test identity. Canonical committed-source verification
follows separately. A native Avid First attempt reaches a disposable project and
EDL picker but does not complete file navigation or reach marker-text import;
editor acceptance stays open. See [focused evidence](evidence/review-meter-integrity-20261001/README.md)
and [dependency stage evidence](evidence/coreaudio-stage-inventory-20261001/README.md).
Native/accessibility, editor, hardware/soak, public dependencies and distribution
gates remain open.

The first October 1 canonical run is rejected: 750 passes, nine named skips
and one SIGBUS while the bundled experimental DCA encoder creates a synthetic
fixture. Production live decoding had not started. Direct trials reproduce it,
including with SIMD disabled. The decoder check now uses pinned generated DTS
bytes without changing its assertions, and all FFmpeg wrappers preserve quiet
failure exit/signal details. Three new regressions raise candidate consumption
to 763, with seven new checks and the pinned DTS decoder check required by exact
identity. Focused and fresh canonical verification follow separately. The DCA
encoder defect remains open; this fixture setup correction supplies no authentic
DTS/native/hardware acceptance. See [diagnosis](evidence/dts-fixture-encoder-diagnosis-20261001/README.md)
and [rejected candidate evidence](evidence/encoder-diagnostics-20261001/README.md).

The Review & Report implementation is substantially present: structured point
and range findings, versioned local sidecars, relinking, deliberate historical
timebase migration, save recovery, and CSV/PDF/editor-format export. That makes
the product a credible candidate for a focused beta. It does **not** yet make
the committed 2.0 roadmap close to release-candidate acceptance: the preceding
Audio QC milestone still includes unfinished representative-media live-meter
acceptance, and important
performance and interoperability gates have no completed acceptance record.
SwiftMediaMetadata 3.0.1 is now integrated at its exact release commit, and the
production metadata path varies by only a few MiB across duration-correct one-hour
and eight-hour sparse-payload regression containers, without following their
290 MB versus 2.32 GB payload sizes. This closes the previously listed metadata payload-copy
blocker at the engineering level. The project is now close to a reasonable focused
beta, but producer-authentic live-meter evidence, native workflow/accessibility
acceptance and a signed/notarized distributable build remain before calling it a
beta release. The project still declares version 1.6.1.

The September 19 Phase 113 native player/Final Cut continuation fixes a
one-frame duration overstatement and verifies a fresh native import/re-export:
14,625 frames, 160 × 90, exact 23.976 timing and all eight findings survive.
Final Cut's parsed note whitespace still differs. This focused result leaves
the broader editor matrix open; see [native duration evidence](evidence/fcp-native-duration-23976-20260919/README.md).

Phase 123 confirms that the remaining Final Cut whitespace difference causes
actual formatting loss on native re-import: tabs/newlines become spaces in the
browser Notes column and subsequent XML. All eight findings, timing and media
bytes survive. The export save panel now discloses this limitation; exact
whitespace acceptance remains open. See [second-generation native evidence](evidence/fcp-whitespace-reimport-20260920/README.md).

Phase 124 passes the canonical clean-checkout verifier at
`f8d8d0ec870ccc84e8ce8c58c951f9c076f89e86`: 690 optimized Release tests pass
with eight explicit allowlisted skips (698 total), both isolated mixed-backend
transport tests pass, Release static analysis succeeds, and all 61 source-tree
preflight checks pass. Final source and pinned-package identities are unchanged.
This refreshes regression evidence through Phase 123; external-input, native,
editor, release-floor performance and distribution acceptance remain open.
See [retained candidate evidence](evidence/release-candidate-20260920/README.md).

Phase 125 adds app-menu access to every review export format and Cmd–Option–E
for CSV. A focused native MPV/MPV keyboard check verifies unsubmitted note edits,
filtered and closed-review exports, and cancel/reopen behavior; all three CSVs
retain both findings. Full structured-control traversal, keyboard-only comparison
setup, Full Keyboard Access, spoken VoiceOver and AVFoundation acceptance remain
open. See [keyboard export evidence](evidence/review-keyboard-export-20260920/README.md).

Phase 126 adds File → Add Comparison File (Cmd–Option–O) and fixes the local
trim handler consuming that shortcut as clear-Out. Native picker opening,
cancellation and Out-point preservation pass, as do 31 focused optimized Release
tests and static analysis. Native Go to Folder interaction prevented completion
of source-B selection; complete keyboard setup and review navigation remain open.
See [keyboard setup evidence](evidence/comparison-keyboard-setup-20260921/README.md).

The next September 29 continuation makes each repeated blocked Review action
request scrolling and correction-field focus again, even if the error text is
unchanged. Four focused Debug tests pass; native disclosure/focus and spoken
VoiceOver acceptance remain open. AVFoundation Native pixels now also checks
the acquired buffer against the active track's coded format before transforming
it; 43 focused loupe checks pass without skips, including both decoder geometry
matrices. MPV's audited screenshot conversion still resamples display geometry
and remains ineligible. The live-meter profiler now accepts deliberate per-input
audio ordinals and validates request identity across both measured segments;
13 input/validator regressions and its Debug build pass. The actual runner
passes a generated video with two explicitly selected stereo AAC tracks; an
audio-only mono input fails with CoreAudio errors and remains under diagnosis.
See [selected-track engineering evidence](evidence/live-meter-selected-tracks-20260929/README.md). These changes advance
correctness and repeatable acceptance, without closing producer-authentic media,
MPV 1:1, native accessibility or release-floor gates.

Phase 148 passes the canonical clean-checkout verifier at
`2d314c8b47c090555a99f19bc6dd890c40053d75`: 702 optimized Release tests pass
with eight documented optional skips, both isolated mixed-backend transport
tests pass, Release static analysis succeeds and all 61 preflight checks pass.
Source, package and cache identities are revalidated. The final harness also
closes its observation session on failed checks. This verifies the integrated
engineering batch, while the retained mono native-output failure and external
workflow/media/performance gates remain open. See [current candidate evidence](evidence/release-candidate-20260930/README.md).

## Must close before a defensible 2.0 candidate

The latest parallel continuation produces a complete isolated macOS mpv/FFmpeg
build for both architectures, with immutable local source/recipe commits and
verified universal artifacts. A separately linked current Release app passes
producer-original AAC and selected FX6 mono tracks, plus a sample-preserving
ITU six-channel preparation. The matched FX6 120-second repeat passes; an
incremental candidate's earlier near-EOF synchronization failure remains
unexplained. Local artifact publication/package repin, audible/device/surround
and hardware acceptance remain open. See [clean build](evidence/live-meter-native-output-20260930/clean-rebuild/README.md)
and [authentic native checks](LIVE_AUDIO_METER_AUTHENTIC_NATIVE_CHECK_2026-09-30.md).

A subsequent configuration audit finds GPL components and FFmpeg Metal support
disabled in that full-built candidate relative to shipping MPVKit-GPL. The builder
now needs explicit product/configuration gates; the missing Xcode Metal compiler
blocks a feature-equivalent replacement. These local playback observations do
not qualify a shipping repin.

Three authentic camera metadata profiles pass cache parity, but expose a
transient 368.516 MiB peak increase on the original 8.64 GB FX6 MXF. A complete
mapped KLV header/peek scan is consistent with that cost; bounded file-backed
reading and long-duration scaling need investigation. These observations do
not replace the resolved top-level MP4 payload-copy fix. See
[camera memory evidence](evidence/authentic-camera-metadata-memory-20260930/README.md).

The JXL contradiction now has a [tested upstream correction proposal](evidence/jxl-contract-proposal-20260930/README.md),
with three Release checks against unchanged library sources and the original
fixture. Upstream reconciliation and the historical XMP remain open. Review
now preserves correction requests across unrelated fields and findings; native
app binding again hung, so no new keyboard or spoken accessibility acceptance
is inferred. The first integrated run at `8626ae9` rejects one paused mixed-backend alignment
failure (722 passes, eight skips, one failure). The unchanged isolated repeat
passes. A new deterministic regression reproduces B resuming from a delayed
primary playing observation while A remains paused. Explicit Pause now remains
authoritative until deliberate playback resumes. Explicit Play/shuttle during B
loading stays with the session, and its request arms synchronization even before
A publishes the Play acknowledgement; 16 final focused Release checks pass. The candidate/release floor is 733 aggregate tests plus both isolated
transport directions. Canonical committed-source verification passes below. See
[transport diagnosis and correction](evidence/compare-paused-alignment-20260930/README.md).

The integrated authentic continuation passes canonical verification at clean
commit `1e8023258c7192b8c426ea42f5e64162b4890ca4`: 725 optimized Release passes,
eight documented optional skips (733 total), both isolated transport directions,
Release static analysis, the complete script-validator gate and all 61 preflight
checks. The four new Review/transport cases pass exact detailed validation.
Power/source/package/cache evidence passes. The first rejected run and reproduced
transport bugs are retained. This verifies the engineering batch against the
unchanged shipping dependency; a feature-equivalent CoreAudio rebuild/repin,
bounded MXF implementation and native/hardware/distribution gates remain open.
See [integrated evidence](evidence/release-candidate-authentic-continuation-20260930/README.md).

The sustained-acceptance continuation passes canonical verification at clean
commit `601bbb859c436037388c3d3c080cb0132b7e357d`: 721 optimized Release passes,
eight documented optional skips (729 total), both isolated transport directions,
Release static analysis, the complete script-validator gate and all 61 preflight
checks. No sleep interrupts the run, and final source/package/cache identities
agree. Review's clip-end rounding/overflow correction, the explicit 30-minute
meter harness interval, isolated CoreAudio input/archive safeguards and release
source identity guards are integrated. The actual longer native observation,
immutable full MPVKit build/repin, editor/accessibility, base-M1 and distribution
gates remain open. Candidate/release consumption now requires 729 aggregate
tests plus both isolated transport directions. See
[retained continuation evidence](evidence/release-candidate-sustained-20260930/README.md).

The integrated parallel continuation passes canonical verification at clean
commit `88e8bdbfaacb1136770a9d6fcbb88296c8d0608b`: 718 optimized Release passes,
eight documented optional skips (726 total), both isolated transport directions,
Release static analysis and all 61 preflight checks. Expanded script validators,
no-sleep evidence and final source/package/cache identity checks pass. The
candidate/release aggregate floor is now 726. This run uses the shipping pin;
the repaired local dependency's production evidence remains separate. See
[integrated continuation evidence](evidence/release-candidate-parallel-20260930/README.md).

The CoreAudio repair now advances from compile-only diagnosis to a locally
linked dependency candidate. Both architecture archives retain all unrelated
objects byte-for-byte. A copied current Release app passes the unchanged native
profile/output validator on four generated inputs, then repeats them alongside
an authentic Sony stereo recording (five rows). No output-initialization errors
occur in those candidate runs. Rebuild receipts bind source/config/compiler and
archive identities, with six safety tests in the script-validator gate.
This is an incremental local build; the app's shipping dependency pin is
unchanged. An immutable full MPVKit build/repin and repeated audible, device-switch,
monitoring, supported-macOS and hardware acceptance remain required. See
[linked candidate evidence](evidence/live-meter-native-output-20260930/incremental-rebuild/README.md).

The parallel continuation fixes a Review correction-focus handoff: correcting
empty text now takes priority over unrelated range blur validation, and accepted
text clears its own correction without dropping range errors. Nineteen focused
optimized Release tests pass. Native inventory returns a locked Mac, so keyboard,
Full Keyboard Access and spoken VoiceOver remain unverified. See
[Review correction evidence](evidence/review-correction-focus-20260930/README.md).

MPV screenshot capture now validates node tags and overflow-safe raster storage
before reading/copying pixels. Thirty-four focused Release tests pass, including
real asymmetric MPV capture. The source audit confirms display-size RGB conversion
in the public screenshot path; MPV Native pixels still requires a decoder-raster
dependency API with geometry and timing provenance. See
[screenshot boundary evidence](evidence/mpv-screenshot-parser-20260930/README.md).

The same continuation compares authentic ITU live decoder/DSP per-channel
sample/true-peak maxima with the independent integer-PCM Annex 2 reference.
All nine channels agree with 0 dB difference, including exact EOF/filter-tail
provenance. The runner also rejects an explicitly supplied null live-evidence
file. Sixteen validator/calculator tests pass. These whole-programme maxima
close a numerical gap, while live display timing, playback/session, native output,
compressed authentic media and hardware acceptance remain separate. See
[live peak references](evidence/live-meter-itu-peaks-20260930/README.md).

The integrated continuation passes canonical verification at clean commit
`7bccab4f619eb88f7a1ad08de1c6fddf9e8943d9`: 707 optimized Release passes,
eight documented optional skips, both isolated transport directions, Release
static analysis, all 61 preflight checks and verified no-sleep evidence. Final
source/package/cache identities agree. See [current integrated evidence](evidence/release-candidate-2-continuation-final-20260930/README.md).
The same source's actual Release native profile then confirms the stronger
output gate: both source-meter rows and XCTest pass, but logged CoreAudio
channel-map failures make the runner exit 1 without a passing summary. See
[current native rejection](evidence/live-meter-native-output-20260930/release-output-gate/README.md).
The dependency repair remains pending; these records do not close external
media, editor/accessibility, hardware or distribution gates.

The next September 30 continuation fixes Review's current-range action leaving
invalid typed input behind when its accepted endpoint is unchanged. It also
passes 4,896 momentary/short-term comparisons from the production live decoder
and DSP against independent `ebur128` readings on original ITU mono/stereo
programmes and a sample-preserving, explicitly labelled 5.1 preparation. Every
reading agrees within 0.0005 LU; this is numerical decoder/DSP evidence, separate
from the owning playback/session/UI, native output and release-floor gates.
See [retained programme comparisons](evidence/live-meter-itu-windows-20260930/README.md).

The authentic Sony ARW is recovered, independently reviewed and pinned; three
former skips now pass. The exact 3.0.1 fixture run has 17 passes, two historical
XMP skips and one unchanged upstream JXL assertion failure. The JXL diagnostic
now verifies the exact integrated release and pinned codestream identity.
See [fixture recovery](METADATA_FIXTURE_RECOVERY_20260930.md).

The linked MPV CoreAudio object is now tied to a reproduced ChannelMap
type-contract defect: typed integer maps initialize in all twelve isolated
mono/stereo checks, while malformed mono/planar-stereo maps fail in all nine
checks. A retained upstream repair candidate applies and compiles for both
architectures; MPVKit has not been rebuilt or repinned. The profile now retains
Release error logs and rejects native-output initialization failures even when
video clocks and source meters progress. This invalidates the earlier output
false-pass without claiming a production playback correction. See
[dependency diagnosis](LIVE_AUDIO_METER_NATIVE_OUTPUT_DIAGNOSIS_2026-09-30.md).
Native Review interaction remains unverified because the app connection hung
until cancellation; source regression coverage does not establish spoken
VoiceOver or Full Keyboard Access acceptance.

The fresh awake canonical verifier subsequently passes at clean commit
`61b2d0e9a4001a320cd1bb9e4cb44e245570cbf1`: 705 optimized Release passes with
eight documented optional skips, both isolated transport directions, Release
analysis and all 61 preflight checks. Its retained power interval contains no
sleep, and source/package/cache identities are revalidated. All three new loupe
track/composition cases pass. This supersedes the interrupted attempt without
changing transport tolerances. The bounded native Review inventory reports a
locked Mac; no native interaction or spoken accessibility is accepted.
See [awake candidate evidence](evidence/release-candidate-continuation-20260930/README.md).

The September 30 continuation strengthens live-meter evidence consistency,
restores the 710-test aggregate release floor, and binds AVFoundation loupe
geometry and native-raster proof to the ready item's single enabled video
track. All 16 focused profile validator checks, 12 release-script checks and
15 focused loupe gate/decoder checks pass; the strengthened composition preview
check also passes separately. Composed or ambiguous video remains preview-only,
and MPV still lacks a verified decoder-raster capture path. A source audit found
no new Review draft/focus defect, but native Review interaction could not start
because the computer-use app connection hung and was cancelled. No native
keyboard or spoken VoiceOver acceptance is inferred from that audit or its
successful Debug build.

The same continuation retains unsuccessful native audio-output probes and
removes their temporary production policies. The profiler now retains separate
native-output/meter diagnostics, stops promptly on unavailable state, and checks
source decoder channel identity during the active monitoring matrix. Its two
original stereo-video rows pass the revised harness, but native CoreAudio
channel-map rejection can coexist with a progressing video clock. Audible
mono/stereo output remains unresolved; generated-video meter plumbing cannot
close that gate. See [native-output diagnosis](LIVE_AUDIO_METER_NATIVE_OUTPUT_DIAGNOSIS_2026-09-30.md).

The first integrated attempt at `c4a7557` passes 705 optimized Release tests
with eight documented optional skips, but both isolated transport checks are
interrupted by repeated system sleep. Power records correlate 534- and
900-second sleeps with the failed observations. That attempt never reaches
analysis/preflight/final identity and supplies no passing candidate. The runner
now holds scoped sleep assertions, requires retained no-sleep evidence and
bounds each isolated test to 120 seconds. The passing awake replacement is
recorded above.
See [interrupted-attempt evidence](evidence/release-candidate-sleep-interrupted-20260930/README.md).

Phase 127 completes fresh keyboard-only A/B loading, note creation at distinct
frames and CSV export using the unchanged Phase 126 Release app. Retained
sidecar/CSV records agree on A/B frames, rates, text and source URLs; media
hashes are unchanged. The automated Previous Note shortcut leaves a witness
at frame 10, so Previous/Next keyboard navigation remains open pending input
delivery/layout versus command-routing diagnosis. This does not establish
structured-control, Full Keyboard Access, spoken VoiceOver or AVFoundation
acceptance. See [native keyboard evidence](evidence/review-keyboard-setup-20260921/README.md).

Phase 128 closes Phase 127's focused Previous/Next keyboard-navigation gap.
The old bracket input exposes a keyboard-layout dependency; new
Cmd–Control–Left/Right menu shortcuts pass native MPV/MPV checks at frames
0 and 10, duplicate positions, both boundaries and with filter-field focus.
Native sidecar/CSV witnesses agree on A/B frames, original findings and media
are unchanged, and 31 focused optimized Release tests plus static analysis pass.
Broader structured-control, Full Keyboard Access, spoken VoiceOver and
AVFoundation acceptance remain open. See [navigation evidence](evidence/review-navigation-keyboard-20260921/README.md).

Phase 129 distinguishes same-frame review controls by spoken list position and
source-A frame, rejects stale AVFoundation loupe rasters when evaluating 1:1
availability, and checks all three public RTMD read APIs against exact 3.0.0
and 3.0.1 Release container-edge probes (27 cases per revision). Focused loupe
tests and a cached-package Debug build pass. This narrows identity and error-
semantics risks; spoken VoiceOver, Full Keyboard Access, MPV verified source
pixels, exact missing upstream metadata fixtures and producer-authentic media
acceptance remain open.
The combined optimized Release run then passes 700 tests with eight expected
opt-in skips, no failures or runtime warnings. Release static analysis,
script-validator self-tests and all 61 source-tree preflight checks pass. A
fresh clean-checkout candidate run remains required for distribution.

Phase 130 tightens AVFoundation Native pixels eligibility to exact whole-pixel
track transforms, restores filter-field focus when Clear Filter removes its
button, and makes exported-app preflight compare bundle ID and Sparkle update
metadata with reviewed source values. Focused loupe tests, a Debug build and
script-validator tests pass. The integrated Debug suite passes 702 tests with
eight documented opt-in skips and no failures; Release static analysis passes.
The running app has not been
rebuilt for a native filter-focus check. All 61 source-tree preflight checks pass
with normal code-signing service access; an initial sandboxed invocation
reported a false ffmpeg signature failure. This run supplies no new editor,
representative-media, VoiceOver or release-floor evidence.

The September 23 continuation marks known source-A intervals without a
corresponding B frame in amber on the comparison timeline. Alignment and
duration determine these time-localized gaps; image/audio content-difference
markers still need a detector and timestamp model. Invalid Review range ends
now return keyboard focus to the field with specific correction feedback;
leaving that field now commits a valid changed range before keyboard or pointer
navigation. Native keyboard traversal and spoken VoiceOver remain unverified. An MPV
anamorphic screenshot resampled the coded raster, so MPV Native pixels remains
disabled with clearer provenance guidance until a source-pixel capture path can
be validated. The metadata container-edge harness adds seven positive/error
cases and passes 34 fixtures against each of 3.0.0 and 3.0.1. The missing
ARW/XMP originals and upstream JXL fixture/assertion disagreement remain open.
Focused timeline, loupe, Review, and metadata checks pass; source-tree release
preflight passes all 61 checks. This is not a fresh clean-checkout candidate run.

The September 29 Review continuation retains pending note and range drafts
across popover dismissal and same-source reloads, checks drafts before Notes or
report actions, reveals blocking findings, and keeps a note draft when its
mutation is rejected. Focused Debug lifecycle checks pass. Native retry/export,
Full Keyboard Access and spoken VoiceOver acceptance remain open.

The same continuation shows an immediate finding-level correction when a Review
text edit is rejected on field exit and blocks an extreme 96 kHz live-meter
worker frame position before its ahead allowance can overflow. Four focused
tests pass together in a rebuilt Debug app. Metadata fixture validation now
refuses unreviewed recovered ARW/XMP files, and the JXL diagnostic pins its
input identity and reports the upstream write-assertion disagreement. The
original missing fixtures and upstream correction remain open. Avid Media
Composer First accepted a retained Resolve EDL as an offline sequence, but
marker import and the app's Avid marker-text path remain unverified.

The Phase 144 clean-checkout candidate run at `2730a4b6d122e19a4ae3aadc4df73ae61d6c71e6`
passes 699 optimized Release tests with eight explicit optional skips, both
isolated mixed-backend tests, Release static analysis and all 61 preflight
checks. Source and resolved-package identities remain stable. This is current
regression evidence, not completion of the external native, media, performance
or distribution gates. See [retained candidate evidence](evidence/release-candidate-20260929/README.md).

Phase 122 now rejects Final Cut XML exports for quarter-turn anamorphic source
A with an actionable CSV/PDF fallback. This contains the demonstrated native
Fit defect without changing source media or adding unverified scale compensation.
The guard covers normalized negative/wrapped rotations and valid non-square PAR,
even when raster dimensions are missing. Native conform resolution and broader
geometry acceptance remain open; earlier successful XML-generation checks for
this combination are historical evidence, not current supported export behavior.

Phase 115 adds ten real geometry fixtures through the production metadata/exporter
path and a native rotated anamorphic round trip. It exposes and fixes a comparator
false positive: Final Cut changes the asset raster while preserving the browser
clip format. Timing, point findings and media bytes match, but native geometry
acceptance remains open. See [asset-format divergence evidence](evidence/fcp-rotated-anamorphic-20260919/README.md).

Phase 116 corrects quarter-turn browser formats by swapping raster dimensions
and inverting pixel aspect ratio together. Native diagnostic display improves
and browser format, timing, findings and media bytes survive re-export, but
Final Cut still rewrites asset PAR. This remains a partial result; see the
[oriented anamorphic evidence](evidence/fcp-oriented-anamorphic-20260919/README.md).

Phase 117 compares that review with an independently imported byte-identical
source in a native portrait timeline. Both show surrounding margins at default
Fit/100% and share native asset geometry. The strict asset-PAR mismatch remains;
calibrated rendered geometry and fresh production UI export are still required.
See [timeline and independent-source evidence](evidence/fcp-timeline-anamorphic-20260919/README.md).

Phase 118 measures a native ProRes export of that timeline. All four sampled
review/direct-import frames are identical: correctly oriented 9:16 content
occupies only 813 × 1444 pixels inside 1080 × 1920. This confirms real rendered
padding under default Fit, not merely viewer zoom. The calibrated measurement
task is complete; Fit geometry, asset PAR and fresh production UI export remain
open. See [rendered geometry evidence](evidence/fcp-rendered-anamorphic-20260919/README.md).

Phase 119 narrows the generated-fixture Fit failure to combined rotation and
anamorphic pixels: unrotated anamorphic, rotated square-pixel and baked controls
pass a four-clip native render. The diagnostic now uses an axis-independent
aspect tolerance; the original padding still fails the unchanged Fit check.
This does not resolve native asset PAR or replace fresh production UI acceptance.
See [conform isolation evidence](evidence/fcp-conform-isolation-20260919/README.md).

Phase 120 completes the fresh rebuilt-player UI browser export/import/re-export
repeat in a separate native library. Exact marker text, timing, browser geometry
and source bytes survive; the native asset-PAR mismatch is reproduced. A new
render of this UI export and resolution of the earlier Fit padding remain open.
See [production UI evidence](evidence/fcp-production-ui-anamorphic-20260919/README.md).


Phase 121 completes the native rendered-output repeat using the Phase 120
production UI export. Four sampled frames across two complete clip instances
all reproduce 813 × 1444 content inside 1080 × 1920; orientation/aspect pass,
Fit fails. Browser findings, timing and source bytes remain intact; asset PAR
still differs. This closes the fresh-UI render-repeat task while leaving the
conform defect and geometry acceptance open. See [measured production UI render](evidence/fcp-production-ui-render-20260919/README.md).

| Gap | Acceptance evidence required |
| --- | --- |
| Metadata compatibility and error semantics | The 3.0.1 production payload-copy regression is closed and the authentic ARW now passes all three original cases. Recover the historical XMP sidecar needed by the two remaining skips, reconcile the JXL fixture/assertion disagreement, and complete intended-error coverage. Keep this compatibility gate separate from the resolved memory defect. See [fixture recovery](METADATA_FIXTURE_RECOVERY_20260930.md), [library fixture acceptance](METADATA_LIBRARY_FIXTURE_VALIDATION.md), and [real-media validation](METADATA_REAL_MEDIA_VALIDATION.md). |
| Committed live Audio QC | Implement peak/true-peak and momentary/short-term loudness with explicit units, calibration, ballistics, hold/reset behavior, and presets. Validate the actual live path against trusted references, including pause/seek/replacement, channel routing, malformed media and cancellation; demonstrate bounded work during long playback. Existing offline loudness results do not satisfy this promise. See the [live-meter implementation contract](LIVE_AUDIO_METER_DESIGN.md) and [offline audio loudness](AUDIO_LOUDNESS.md). The design, bounded DSP/display, source-rate-paced suspendable decoder, hard 250 ms worker admission bound, timestamp-verified packets, bounded precise seek with generated AAC/ALAC/AC-3 checks, lifecycle ownership, selected A/B track mapping and fallback, typed player events, clock/drift policy, owning window session and mounted activating UI are implemented. Generated compressed ALAC 5.1 now passes the shipping metadata/player/session/FFmpeg/DSP/presentation path under independent monitor routing. The [representative production harness](LIVE_AUDIO_METER_PERFORMANCE.md) now retains exact source/provenance, pacing, routing, memory, cancellation, and EOF evidence. Producer-authentic inputs, trusted measurement comparison, long-play/base-M1 execution, malformed-media behavior, and complete native production acceptance remain. See [meter foundation](LIVE_AUDIO_METER_DSP.md). |
| Real editor interoperability | Complete Resolve, Final Cut Pro, and Avid acceptance rows with exact editor versions and retained import/re-export results. Check fractional rates, DF minute/ten-minute boundaries, inclusive ranges, duplicate positions, note content, and source identity. Where re-export is unavailable, retain the documented visible frame/count evidence and explicitly state the limitation. App exports and parser tests alone are insufficient. See [interchange run sheet](COMPARE_MODE_INTERCHANGE.md). |
| Release-floor playback and resource use | Run the named base 2020 M1 MacBook Air/8 GB gate: 120 seconds per comparison scenario, including UHD/HDR, mixed backends, reflected sources, scopes and loupe; retain decoder/drift results plus Instruments CPU/GPU and thermal observations. Complete concurrent-playback long-file thumbnail and multichannel loudness profiles. September 12 programme profiling exposed and corrected silent long-range channel loss; per-input container-index memory still grows with duration, and sleep-interrupted timings are excluded. See [programme profiling](PROGRAMME_LOUDNESS_PERFORMANCE.md). See [comparison performance](COMPARE_MODE_PERFORMANCE.md), [thumbnails](TIMELINE_THUMBNAIL_PERFORMANCE.md), and [loudness performance](AUDIO_LOUDNESS_PERFORMANCE.md). |
| Complete native workflows and accessibility | Finish keyboard-only structured review creation/edit/filter/navigation/export, relink/migration/recovery, timeline zoom/hover, and audio controls. Complete Full Keyboard Access and spoken VoiceOver, including narrow layouts and both backends. Focused existing native checks cover useful subsets; accessibility-tree labels are not spoken VoiceOver acceptance. See [review native checks](COMPARE_REVIEW_NATIVE_CHECK_2026-09-08.md), [timeline](TIMELINE_NAVIGATION.md), and [loupe manual tests](INSPECTION_LOUPE_MANUAL_TESTS.md). |
| Representative-media visual correctness | Finish the comparison raster/color/backend matrix and live loupe registration across rotation, PAR, different raster sizes and black bars. Record what was actually observed; independently captured display-space loupes cannot be described as frame-locked or exact source pixels. See [comparison verification matrix](../COMPARE_MODE_IMPLEMENTATION_PLAN.md#verification-matrix). |
| Candidate and distribution evidence | The canonical verifier now records the exact commit and resolved-package hash, runs the self-contained script-validator gate, and requires fresh optimized Release tests, static analysis and source preflight with every optional input identified as a skip. Repeat it against the final candidate, then complete representative-media smoke tests, archive/sign/notarize, stapler/Gatekeeper and update-feed validation. Retain current screenshots, a workflow demo and a short editor/colorist beta with resolved blocking findings. See [release procedure](RELEASE.md) and [demo run sheet](COMPARE_MODE_DEMO.md). |

The verifier now enforces that requirement rather than relying on log review:
unexpected or unexplained skips, runtime warnings, expected failures and a test
count below the recorded floor fail validation. Release execution must consume
matching aggregate and isolated-transport result evidence for the exact HEAD and
`Package.resolved` hash. The release script also refuses version/build overrides
that differ from committed project metadata and withholds appcast changes until
the GitHub tag commit, non-draft state and exact ZIP asset are verified.
Automated Homebrew publication now requires a tracked cask file within the tap
repository root and rechecks its resolved path after pulling the tap, before
writing. This closes an external-path and post-pull symlink escape in the
publication script; it does not provide distribution acceptance evidence.

The September 13 clean-checkout candidate verification at commit
`3fdba621bb731aab234350df842e63fa0b4f405d` passes 654 optimized Release tests
with seven explicit skips (661 total) and passes static analysis. Six skips name
their required external reference/profile inputs; the seventh is the opt-in
real-volume-exhaustion test. This includes timestamp framing, ordered
maxima-reset, source-relative gap, live-meter window teardown, and hardened
mixed-backend transport/pause coverage. Evidence, including the exact
`Package.resolved` hash, is retained at `/tmp/aagedal-candidate-3fdba62-20260913`.
The verifier syntax-checks the repository helpers and runs every
self-contained validator regression, including the mocked comparison-profiler
matrix, before starting Xcode; that gate passes 99 Python cases and retains the
combined log.
Focused subprocess/decoder verification also passes without the earlier
callback-barrier priority-inversion diagnostics.
Phase 88 adds a 23-test focused session/coordinator/production-path pass that
covers paused seek ownership, dynamic distinct-stream A/B selection and fallback,
monitor-routing invariance, and generated compressed six-channel measurement.
That Phase 88 full Debug suite passed 648 tests with seven explicit skips (655
total), and Xcode static analysis passed. The current continuation advances the
worktree baseline to 653 tests passed with the same seven explicit skips and no
failures (660 total), followed by a focused guarded-selection regression. The
release-helper gate passes 99 self-contained Python cases plus the mocked
comparison-profiler matrix. This remains regression evidence, not a replacement
for the clean-checkout optimized Release verifier.
The subsequent direct review-field continuation passes its focused six-test
Debug suite and a native MPV/MPV focus check. Its exact code commit
`43abae5cad3261f484dad239c54cb4cc9ea78e44` also passes the canonical verifier
on a fresh retry: 655 optimized Release tests pass with seven explicit skips
(662 total), static analysis passes, and all 61 preflight checks pass. The first
full run had two non-reproducible MPV integration-test failures; both passed in
a sequential isolation run before the clean full retry. This is a candidate
repeatability risk to watch, not spoken VoiceOver acceptance.
The complete 61-check release preflight passes for 1.6.1 (163) when run
outside the restricted workspace sandbox, where macOS can reach its normal
code-signing trust services.
Strict verification confirms that the tracked FFmpeg is signed by the expected
Developer ID team with Hardened Runtime and a secure timestamp. The sandbox's
`invalid signature` result was a trust-service access false negative, not an
artifact defect; the exact tracked blob's checksum, CodeDirectory page hashes,
and CMS signature were also verified unchanged. This is source-tree preflight
evidence, not completed candidate signing or distribution evidence.
The release pipeline now also fail-closes unless the final distribution ZIP can
be re-extracted and its app passes the app preflight, stapler validation, and
Gatekeeper assessment. That automated gate has not yet produced candidate
evidence because no exact candidate has completed archive, signing,
notarization, packaging, and distribution validation.

The September 13 Phase 92–93 continuation passes a split Debug verification:
the process-isolated aggregate contains 662 tests (655 passed and the same seven
named opt-in skips) with no failures or runtime warnings, while both mixed-
backend transport directions pass in a fresh two-test serial runner. A one-host
serial experiment reproduced late-class resource/order failures and is retained
as diagnosis, not acceptance. The canonical verifier enforces both result
bundles, rechecks source identity at completion, and release execution consumes
only matching evidence. Candidate status therefore follows the retained verifier
output for the exact clean commit rather than a durable claim in this document.

The September 15 canonical clean-checkout verifier passes at commit
`d3b703097049c2bb0af209e251c05048fd0bdfee`, with the exact committed
`Package.resolved` SHA-256
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.
The new optional offline-cache route first checked the three pinned package
checkout revisions and clean states, then supplied them to Release tests and
analysis when a fresh isolated DerivedData could not reach GitHub DNS. The
script-validator gate, 678 optimized Release passes with eight explicit
allowlisted skips (686 total), two separate serial mixed-backend transport
passes, static analysis, and all 61 source-tree preflight checks pass. The
verifier rechecked HEAD, `Package.resolved`, package checkouts and the clean
worktree before recording `status=passed`. Full logs and `.xcresult` bundles
are retained at `/private/tmp/aagedal-improvement-candidate-offline-20260915`.
This validates that exact checkout; later documentation-only commits need a
fresh exact-HEAD verification before any release execution.

Resolve Studio 21.1.0.14 now has a real import/re-export attempt with generated
29.97 drop-frame media. The corrected-start import retains six of eight
in-range findings, including two three-frame durations, Unicode and both
source URLs. It loses the first-frame and duplicate-frame findings; the
adjacent finding's text lands one frame early. An earlier import at the
timeline's wrong starting timecode also persists as seven negative-frame
markers in the disposable project. The re-export exposes all thirteen
observed markers, but this is a partial interoperability result, not editor
acceptance. The subsequent fresh correct-start investigation passes as recorded
below; the app now explicitly rejects same-frame findings. See
[the retained interchange record](COMPARE_MODE_INTERCHANGE.md).

The September 19 continuation adds an explicit Resolve EDL limitation: reviews
with same-frame findings now fail export with a CSV/PDF alternative, preserving
the complete review instead of risking another silent dropped finding. Distinct
adjacent frames remain unchanged. The fresh-timeline investigation below closes
the focused timing check; this guard alone does not establish interoperability.

The same continuation adds a strict, repeatable original/re-export EDL
comparison. It rejects the retained partial round trip and reports exact
missing and unexpected records with input hashes; six focused regressions and
the complete script-validator suite pass. The user imported the seven-finding diagnostic into a fresh correctly started
Resolve timeline. All seven API-reported anchors, durations and exact marker
texts match, including first/adjacent frames and DF boundaries. The earlier
adjacent-frame displacement does not reproduce in this clean import. Native
re-export now passes the exact seven-finding comparison, with no missing or
unexpected events; post-export media and sidecar hashes are unchanged. This
closes the focused 29.97 DF timing investigation. Historical note URLs and the
reduced fixture leave current-source identity and other rates unaccepted.
The same-frame guard stays in place, and the wider editor
acceptance gate remains open. See the [retained evidence](evidence/resolve-markers-20260919/README.md).

Phase 106 prepares the next Resolve rate/source-identity check: fixture generation
can now retain the full review alongside an explicitly documented unique-anchor
copy, and the EDL comparator can verify unchanged fixture hashes and current A/B
URLs against its manifest. Thirteen focused regressions pass, and real 59.94 DF
fixtures are prepared at `/private/tmp/aagedal-resolve-5994-20260919`. Native app
export and editor import/re-export were subsequently completed in Phase 107 below;
fixture preparation alone did not establish editor acceptance.

Phase 107 completes native app export and the user's Resolve 59.94 DF import/re-export
from the prepared seven-finding copy. All seven actual marker records match,
including both DF boundaries, ranges and exact text. The read-only editor
snapshot additionally verifies the current source-A file, source rate/start/frame
count and full untrimmed timeline placement; both media and both reviews retain
their original hashes. Seventeen focused helper tests and the full script-validator
suite pass. Native re-export passes all seven exact records, with no missing or
extra events and unchanged post-export fixture hashes. 23.976, same-frame
findings and other editors remain outside this focused result. See the
[retained 59.94 evidence](evidence/resolve-markers-5994-20260919/README.md).

Phase 108 verifies native app export at 23.976 with no embedded source timecode:
all seven relative anchors/durations match the selected review and fixture hashes
are unchanged. A separate zero-start Resolve timeline contains the verified
14,625-frame source-A clip. The user's native marker import now passes all seven
actual marker records, including exact text and inclusive durations. The native
re-export also passes all seven exact records, with no missing or extra events
and unchanged post-export media/review hashes. Eighteen focused helper regressions
include the retained 23.976 round trip. This closes the focused 23.976
relative-time gate; same-frame findings and other-editor acceptance remain
separate. See the
[retained acceptance record](evidence/resolve-markers-23976-20260919/README.md).

Phase 109 completes a first native Final Cut Pro 12.3 round trip at 23.976.
Only five of eight findings survive: three anchors inside inclusive ranges
are dropped. FCPXML export now rejects overlapping findings and recommends
CSV/PDF; adjacent non-overlapping markers remain available. The input and native
re-export are retained with unchanged source/review hashes. Native re-export
also exposes whitespace normalization, a defaulted browser-clip raster, and
source-duration clamping. These remain open; the guard does not establish Final
Cut acceptance. See [the retained failure](evidence/fcp-markers-23976-20260919/README.md).

Phase 110 supersedes the FCP overlap guard: one-frame markers preserve range
endpoints in text, and same-frame findings share individually labelled marker
notes. Native Final Cut Pro 12.3 re-export now retains all eight findings in
seven markers at correct positions. Note content matches with XML attribute
whitespace normalization explicitly qualified. The production exporter was
invoked by the retained fixture test because the rebuilt player’s native content
view went blank on load; native player UI export needs a repeat. Raster/duration,
other rates and exact whitespace acceptance remain open. See
[the grouped-marker evidence](evidence/fcp-grouped-markers-23976-20260919/README.md).

Phase 111 supplies the missing source raster and valid pixel aspect ratio in
FCPXML format metadata. All 33 focused exporter tests and bundled FCPXML 1.9 DTD
validation pass; the retained fixture now declares its actual 160×90 raster.
This does not close the native raster gate: repeat player UI export and Final
Cut import/re-export, including portrait/anamorphic/rotated sources. Duration
rounding and whitespace/rate acceptance remain open.

Phase 114 extends native Final Cut evidence to 59.94 DF with a nonzero source
start: exact 36,563-frame duration, raster, rate, DF display and all eight
findings at seven anchors survive. Imported source bytes and original fixture
hashes match. Exact note whitespace remains the only comparator failure; ten
Python regressions pass. This does not close the remaining rate/raster/editor
or accessibility gates. See [the retained 59.94 DF evidence](evidence/fcp-native-markers-5994-20260919/README.md).

## Remaining scope that needs an explicit product decision

These are unfinished roadmap commitments, not silently deferred features:

- **Verified 1:1 source-pixel inspection:** the app now enables native-pixel
  placement for AVFoundation only after the live capture matches the expected
  oriented coded raster. Complete and validate an equivalent MPV path, or
  explicitly limit the release promise to this guarded AVFoundation capability
  plus the existing display-space loupe. The current MPV screenshot may resample.
- **Time-localized mismatch markers:** define what detects a mismatch and its
  timestamp, then implement and validate the model. Static A/B metadata
  differences do not establish time-localized findings. Removing this from
  the milestone requires a recorded roadmap decision.
- **Live meters:** a narrower 2.0 centered on Compare & Review could be a product
  choice, but it would explicitly re-sequence Audio QC. This assessment does
  not make that choice or mark the 1.8 milestone complete.
- **Release sequence:** the roadmap still calls for publishing the reliability
  work before expanding the comparison beta. If releases are consolidated into
  2.0, record that change; do not treat unreleased milestones as already shipped.

## Optional or already outside the bounded scope

These should not delay a candidate merely to increase feature count:

- Optional whole-viewport zoom/pan after the loupe interaction is proven.
- Playlists, batch preflight, caption QC, objective PSNR/SSIM/VMAF analysis,
  and additional custom guides in the roadmap's Later section.
- Spatial image-region annotations and persistent editable image attachments.
- Wider WAVE/ADM/legacy-encoding support and immersive layouts beyond verified
  support. Keep limitations explicit and preserve actionable failures; in
  particular, unsupported RIFX playback/trim must not be advertised as working.
- More synthetic fixture families without a demonstrated coverage gap. Prioritize
  the outstanding producer-authentic, published-reference and native acceptance
  evidence over repeatedly extending already well-covered cases.

## When to call it close

The implementation is already at a credible **focused/private beta** level:
the major workflows exist, regression coverage is broad, and the remaining
risk can be exercised through named acceptance gates. Call it a distributable
beta only after choosing the version/channel strategy, passing representative
smoke and native accessibility checks, and producing a signed, notarized,
Gatekeeper-accepted beta artifact. Resolve's observed marker loss also needs a
fix or clear beta limitation if editor interchange is advertised. Those are
still real release tasks.

Call it **close to a reasonable 2.0 release** when the production memory defect
is resolved, committed feature scope is implemented (or explicitly revised),
and editor interoperability, native accessibility, and release-floor performance
have passed with no unresolved blocking defects. At that point the remaining
work should be a bounded beta-fix list, final release verification, imagery,
demo and distribution—not new measurement architecture or untested workflows.

Track those gates by evidence and concrete defects, rather than by total test
count or percentage of checked roadmap items. Historical green suites remain
valuable regression evidence, but do not establish an untested release gate.
