# 2.0 release readiness

Assessment updated: 2026-09-12. This is a prioritization of the existing
[product roadmap](../PRODUCT_ROADMAP.md), not a change to its committed scope.
It is based on the repository's plans and retained verification reports,
including the September 12 meter foundation and programme-loudness follow-up.
No new editor, accessibility or release-floor hardware acceptance is implied.

The Review & Report implementation is substantially present: structured point
and range findings, versioned local sidecars, relinking, deliberate historical
timebase migration, save recovery, and CSV/PDF/editor-format export. That makes
the product a credible candidate for a focused beta. It does **not** yet make
the committed 2.0 roadmap close to release-candidate acceptance: the preceding
Audio QC milestone still includes unfinished live meters, and important
performance and interoperability gates have no completed acceptance record.
The project still declares version 1.6.1.

## Must close before a defensible 2.0 candidate

| Gap | Acceptance evidence required |
| --- | --- |
| Production metadata memory spike | Complete the reviewed dependency integration and outstanding fixture/error-semantics review; pin the accepted revision and repeat full-app long-file profiling. The isolated candidate's roughly 20 MiB peak versus the original dependency's roughly 4.3 GiB is promising, but is not a shipping-app result. See [metadata investigation](METADATA_MEMORY_PERFORMANCE.md) and [library fixture acceptance](METADATA_LIBRARY_FIXTURE_VALIDATION.md). |
| Committed live Audio QC | Implement peak/true-peak and momentary/short-term loudness with explicit units, calibration, ballistics, hold/reset behavior, and presets. Validate the actual live path against trusted references, including pause/seek/replacement, channel routing, malformed media and cancellation; demonstrate bounded work during long playback. Existing offline loudness results do not satisfy this promise. See the [live-meter implementation contract](LIVE_AUDIO_METER_DESIGN.md) and [offline audio loudness](AUDIO_LOUDNESS.md). The design, bounded DSP/display, source-decoder and reusable presentation foundations are implemented; the window-owned transport coordinator, app wiring and live validation remain. See [meter foundation](LIVE_AUDIO_METER_DSP.md). |
| Real editor interoperability | Complete Resolve, Final Cut Pro, and Avid acceptance rows with exact editor versions and retained import/re-export results. Check fractional rates, DF minute/ten-minute boundaries, inclusive ranges, duplicate positions, note content, and source identity. Where re-export is unavailable, retain the documented visible frame/count evidence and explicitly state the limitation. App exports and parser tests alone are insufficient. See [interchange run sheet](COMPARE_MODE_INTERCHANGE.md). |
| Release-floor playback and resource use | Run the named base 2020 M1 MacBook Air/8 GB gate: 120 seconds per comparison scenario, including UHD/HDR, mixed backends, reflected sources, scopes and loupe; retain decoder/drift results plus Instruments CPU/GPU and thermal observations. Complete concurrent-playback long-file thumbnail and multichannel loudness profiles. September 12 programme profiling exposed and corrected silent long-range channel loss; per-input container-index memory still grows with duration, and sleep-interrupted timings are excluded. See [programme profiling](PROGRAMME_LOUDNESS_PERFORMANCE.md). See [comparison performance](COMPARE_MODE_PERFORMANCE.md), [thumbnails](TIMELINE_THUMBNAIL_PERFORMANCE.md), and [loudness performance](AUDIO_LOUDNESS_PERFORMANCE.md). |
| Complete native workflows and accessibility | Finish keyboard-only structured review creation/edit/filter/navigation/export, relink/migration/recovery, timeline zoom/hover, and audio controls. Complete Full Keyboard Access and spoken VoiceOver, including narrow layouts and both backends. Focused existing native checks cover useful subsets; accessibility-tree labels are not spoken VoiceOver acceptance. See [review native checks](COMPARE_REVIEW_NATIVE_CHECK_2026-09-08.md), [timeline](TIMELINE_NAVIGATION.md), and [loupe manual tests](INSPECTION_LOUPE_MANUAL_TESTS.md). |
| Representative-media visual correctness | Finish the comparison raster/color/backend matrix and live loupe registration across rotation, PAR, different raster sizes and black bars. Record what was actually observed; independently captured display-space loupes cannot be described as frame-locked or exact source pixels. See [comparison verification matrix](../COMPARE_MODE_IMPLEMENTATION_PLAN.md#verification-matrix). |
| Candidate and distribution evidence | Run fresh Release tests (with optional reference/real-filesystem coverage identified explicitly), static analysis and preflight against the exact candidate. Complete representative-media smoke tests, archive/sign/notarize, stapler/Gatekeeper and update-feed validation. Retain current screenshots, a workflow demo and a short editor/colorist beta with resolved blocking findings. See [release procedure](RELEASE.md) and [demo run sheet](COMPARE_MODE_DEMO.md). |

## Remaining scope that needs an explicit product decision

These are unfinished roadmap commitments, not silently deferred features:

- **Verified 1:1 source-pixel inspection:** complete and validate it, or explicitly
  revise the release promise to the existing display-space loupe. The current
  MPV screenshot path may resample.
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

Call it **close to a reasonable 2.0 release** when the production memory defect
is resolved, committed feature scope is implemented (or explicitly revised),
and editor interoperability, native accessibility, and release-floor performance
have passed with no unresolved blocking defects. At that point the remaining
work should be a bounded beta-fix list, final release verification, imagery,
demo and distribution—not new measurement architecture or untested workflows.

Track those gates by evidence and concrete defects, rather than by total test
count or percentage of checked roadmap items. Historical green suites remain
valuable regression evidence, but do not establish an untested release gate.
