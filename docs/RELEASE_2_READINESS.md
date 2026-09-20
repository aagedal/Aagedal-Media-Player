# 2.0 release readiness

Assessment updated: 2026-09-21. This is a prioritization of the existing
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

## Must close before a defensible 2.0 candidate

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
| Metadata compatibility and error semantics | The 3.0.1 production payload-copy regression is closed, but recover the five missing ARW/XMP fixture inputs, reconcile the remaining JXL fixture/assertion disagreement, and expand unusual-container and intended-error coverage. Keep this compatibility gate separate from the resolved memory defect. See [library fixture acceptance](METADATA_LIBRARY_FIXTURE_VALIDATION.md), [real-media validation](METADATA_REAL_MEDIA_VALIDATION.md), and [metadata investigation](METADATA_MEMORY_PERFORMANCE.md). |
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
