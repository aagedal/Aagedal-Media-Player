# Aagedal Media Player Follow-up Improvement Plan

This plan tracks the follow-up work identified by the 2026-09-01 source,
test, and static-analysis review. It complements `IMPROVEMENT_PLAN.md`, whose
original nine phases are complete.

## Verification baseline

- [x] Debug test suite passes (92 tests on 2026-09-01).
- [x] Xcode static analysis passes on 2026-09-01.
- [x] Review completed without modifying existing app behavior.
- [x] First implementation batch passes the expanded 99-test suite and static
  analysis on 2026-09-01.
- [x] Phase 11 completion passes the expanded 106-test suite, real bundled
  ffmpeg multichannel decoding, release preflight, and static analysis on
  2026-09-01.
- [x] Phase 12 completion passes the expanded 109-test suite and static analysis
  on 2026-09-01.
- [x] Phase 13 completion passes the expanded 115-test suite, 61-check release
  preflight, and static analysis on 2026-09-01.
- [x] Phase 14 audio-routing completion passes the expanded 118-test suite and
  static analysis on 2026-09-01.
- [x] Phase 15 track-lifecycle completion passes the expanded 121-test suite
  and static analysis on 2026-09-01.
- [x] Phase 16 playback-observer isolation passes the expanded 122-test suite
  and static analysis on 2026-09-02.
- [x] Phase 17 MPV-publisher isolation passes the expanded 123-test suite and
  static analysis on 2026-09-02.
- [x] Phase 18 scope-capture isolation passes the expanded 124-test suite and
  static analysis on 2026-09-02.
- [x] Phase 19 LUFS-analysis isolation passes the expanded 127-test suite and
  static analysis on 2026-09-02.
- [x] Phase 20 update-request coalescing passes the expanded 128-test suite and
  static analysis on 2026-09-02.
- [x] Phase 21 auxiliary-waveform startup ownership passes the expanded
  130-test suite and static analysis on 2026-09-02.
- [x] Phase 22 queued playback-timer isolation passes the expanded 132-test
  suite and static analysis on 2026-09-02.
- [x] Phase 23 dropped-file load ownership passes the expanded 133-test suite
  and static analysis on 2026-09-02.
- [x] Phase 24 deferred UI-work ownership passes the expanded 134-test suite
  and static analysis on 2026-09-02.
- [x] Phase 25 media-operation feedback ownership passes the expanded 135-test
  suite and static analysis on 2026-09-02.
- [x] Phase 26 SwiftMediaMetadata 3.0.0 migration passes the 135-test suite and
  static analysis on 2026-09-02.
- [x] Release preflight passes all 61 checks after installing the verified
  Developer ID-signed ffmpeg 9.0.1 artifact and updating its provenance
  checksum on 2026-09-02.
- [x] Phase 27 playback-preparation ownership passes the expanded 136-test
  suite and static analysis on 2026-09-02.
- [x] Phase 28 metadata-copy feedback ownership passes the expanded 137-test
  suite and static analysis on 2026-09-02.

## Phase 10 — Playback and preload correctness

Status: Completed on 2026-09-01.

- [x] Preserve zero as a valid playback volume instead of treating it as an
  unset preference.
- [x] Cover zero, bounds, and non-finite persisted volume values with tests.
- [x] Replace the structured metadata timeout with a deadline that does not
  wait for the non-cancellable metadata operation.
- [x] Allow timed-out metadata work to finish and populate the metadata cache.
- [x] Deduplicate in-flight metadata requests so post-timeout enrichment joins
  the original parser rather than launching a duplicate read.
- [x] Add deterministic tests for deadline, early-completion, and continued
  cache-fill behavior.

Acceptance: volume can be reduced to zero, and slow metadata cannot delay the
initial media load beyond the preload deadline.

## Phase 11 — Audio waveform lifecycle and performance

Status: Completed on 2026-09-01. Replacement and cancellation behavior is
covered end to end, PCM reduction is duration-bounded, and the reproducible
8-channel 1/8/24-hour baseline is documented in
`docs/AUDIO_WAVEFORM_PERFORMANCE.md`.

- [x] Add generation identities so cancelled waveform tasks cannot publish
  stale images, errors, or loading state.
- [x] Move cached waveform image rerendering off the main actor.
- [x] Add unit coverage for generation invalidation and synchronous cancellation
  state cleanup.
- [x] Add end-to-end tests for replacement and stale image completion behavior.
- [x] Replace whole-file PCM loading with bounded streaming aggregation for
  long recordings.
- [x] Profile multichannel files at 1, 8, and 24 hours.

Acceptance: replacing or closing a waveform never corrupts current UI state,
appearance adjustments remain responsive, and memory use is bounded by output
resolution rather than media duration.

## Phase 12 — Media operation ownership

Status: Completed on 2026-09-01. Screenshots and trim exports are owned by the
player window that initiated them. Closing that window cancels preparation and
encoding, dismisses save panels, terminates ffmpeg across the process-attachment
race, removes temporary output, and invalidates late operation feedback.

- [x] Define whether screenshots and exports cancel or continue when their
  player window closes.
- [x] Store operation tasks explicitly and apply the selected close policy.
- [x] Keep completion and failure feedback reachable if operations continue.
  The selected policy cancels window-owned work, so no post-close result needs
  to be delivered outside its initiating window.
- [x] Add lifecycle tests for closing a window during preparation and encoding.

Acceptance: no ffmpeg process continues invisibly, and closing a window has a
clear, tested outcome for every active media operation.

## Phase 13 — Update status and maintainability

Status: Completed on 2026-09-01. The fallback checker now publishes one typed
attempt result, records every successful check, exposes retryability, and uses
injected networking, time, version, and defaults dependencies. Update settings
were also extracted from the remaining large settings file.

- [x] Publish a typed update-check result, including retryable failures.
- [x] Record `lastChecked` after every successful automatic or manual check.
- [x] Prevent stale state from presenting a failed check as "Up to date."
- [x] Inject networking and time dependencies for deterministic tests.
- [x] Continue splitting the remaining large settings and playback components
  when a change requires touching them.

Acceptance: update UI always reflects the latest attempt truthfully and the
checker can be fully tested without network access.

## Phase 14 — AVFoundation audio-track routing

Status: Completed on 2026-09-01. AVFoundation audio options now retain their
preferred display order while carrying the original source index through both
media-selection and lower-level player-item routing paths.

- [x] Separate audio-track display positions from AVFoundation source indices.
- [x] Route sorted rows to their matching media-selection options.
- [x] Use the source index for the lower-level `AVPlayerItemTrack` fallback.
- [x] Cover reordered, incomplete, and metadata-free routing with pure tests.
- [x] Pass the full test suite and static analysis.

Acceptance: selecting an AVFoundation audio row activates the track described
by that row even when the preferred display order differs from file stream
order.

## Phase 15 — Track-discovery lifecycle isolation

Status: Completed on 2026-09-01. Audio selection, audio discovery, and chapter
discovery now use independent generations so superseded AVFoundation work
cannot publish into a replacement file. Delayed MPV discovery and post-switch
playback resumption are also bound to the preparation that created them.

- [x] Invalidate pending audio and chapter discovery whenever a newer request
  starts or track state resets.
- [x] Prevent superseded AVFoundation loads from publishing stale audio or
  chapter options.
- [x] Prevent a superseded audio selection from reporting success and resuming
  playback after the active media changes.
- [x] Bind delayed MPV track discovery to its originating preparation and
  backend instance.
- [x] Inject AVFoundation discovery dependencies and cover replacement and
  reset races with deterministic suspended-operation tests.

Acceptance: rapidly replacing media cannot show the previous file's tracks or
chapters, apply a previous selection, or start playback in the replacement
file.

## Phase 16 — Playback-observer lifecycle isolation

Status: Completed on 2026-09-02. AVFoundation observer callbacks now carry the
preparation, player, and player-item identity that installed them, and all
asynchronous readiness paths revalidate that identity after suspension. The
MPV end-of-file timer is likewise bound to its originating preparation and
backend instance.

- [x] Prevent queued AVFoundation playback-end and failure notifications from
  acting on a replacement player item.
- [x] Prevent stale periodic-time and time-control callbacks from publishing
  playback time, reverse, playing, or buffering state.
- [x] Revalidate AVFoundation readiness work after every asynchronous asset
  load and seek, including the fallback error path.
- [x] Prevent a completed loop seek from restarting playback after the active
  media changes.
- [x] Bind delayed MPV end-of-file polling work to its originating preparation
  and player instance.
- [x] Cover preparation, player, and player-item identity matching with a
  focused regression test.

Acceptance: callbacks and continuations originating from a superseded playback
backend cannot change the replacement file's time, readiness, buffering,
failure, reverse, or play/pause state.

## Phase 17 — MPV publisher lifecycle isolation

Status: Completed on 2026-09-02. Every MPV publisher and delayed callback now
revalidates both its preparation and originating player before changing shared
controller or scope state.

- [x] Bind every MPV publisher bridge to its originating preparation and
  player instance.
- [x] Prevent queued stale values from changing play state, video geometry,
  HDR scope configuration, or reverse-playback mode.
- [x] Apply the same identity check to MPV time, duration, readiness, errors,
  buffering, and delayed track discovery.
- [x] Cover preparation and player identity matching with a focused regression
  test.
- [x] Pass the full test suite and static analysis.

Acceptance: no publisher value or delayed callback originating from a
superseded MPV backend can mutate the replacement file's controller or scope
state.

## Phase 18 — Scope-capture lifecycle isolation

Status: Completed on 2026-09-02. Asynchronous MPV screenshots now publish only
into the capture session and backend that requested them, and playback teardown
cannot schedule an AVFoundation pipeline rebuild against replacement media.

- [x] Bind asynchronous MPV screenshot results to their originating capture
  session and player instance.
- [x] Prevent a stale completion from clearing a replacement capture that is
  already in flight.
- [x] Invalidate pending capture work when capture stops or either playback
  backend is replaced.
- [x] Suppress AVFoundation's delayed same-item pipeline rebuild when the
  entire playback backend is being torn down.
- [x] Cover capture-session and MPV-player identity matching with a focused
  regression test.
- [x] Pass the full test suite and static analysis.

Acceptance: a scope screenshot or delayed AVFoundation rebuild originating
from superseded media cannot publish into, stall, or restart the replacement
file.

## Phase 19 — Metadata-inspector analysis isolation

Status: Completed on 2026-09-02. Per-stream LUFS analyses now carry independent
operation generations, cancel when their media is replaced or the inspector
closes, and cannot publish or clear state belonging to replacement work.

- [x] Cancel every in-flight LUFS subprocess when the inspected media changes.
- [x] Cancel LUFS work when the metadata inspector closes.
- [x] Keep concurrent analyses for different audio streams independent.
- [x] Prevent a superseded completion from publishing into replacement media
  or clearing a newer retry's loading state.
- [x] Cover keyed replacement, concurrent work, stale completion, and bulk
  invalidation with focused regression tests.
- [x] Pass the full test suite and static analysis.

Acceptance: replacing media, retrying a stream, or closing the inspector cannot
leave invisible LUFS work running or allow an obsolete result to affect the
current inspector state.

## Phase 20 — Update-request coalescing

Status: Completed on 2026-09-02. Overlapping automatic and manual fallback
checks now join one in-flight request and return its completed typed result.

- [x] Coalesce overlapping automatic and manual fallback update checks onto one
  in-flight request.
- [x] Make every overlapping caller await and receive the completed typed result
  instead of the transient `checking` state.
- [x] Cover request count, automatic/manual overlap, and shared final results
  with a deterministic suspended-network test.
- [x] Pass the full test suite and static analysis.

Acceptance: overlapping fallback update checks perform one network request and
every caller receives the same completed attempt result.

## Phase 21 — Auxiliary-waveform startup ownership

Status: Completed on 2026-09-02. The deferred waveform startup is owned by its
panel, so closing or replacing that panel invalidates queued generation before
it can start ffmpeg work.

- [x] Track and invalidate deferred waveform generation when the panel closes.
- [x] Prevent replaced deferred startup work from running.
- [x] Cover cancellation and replacement with focused regression tests.
- [x] Pass the full test suite and static analysis.

Acceptance: closing or replacing an auxiliary waveform panel before its hosted
view is ready cannot start invisible ffmpeg work after cleanup.

## Phase 22 — Queued playback-timer isolation

Status: Completed on 2026-09-02. Timer ticks now carry the identity of the
scope-capture or reverse-playback session that scheduled them, so invalidating
an NSTimer is backed by explicit stale-callback rejection.

- [x] Bind scope-capture timer ticks to the capture session that scheduled them.
- [x] Prevent stopped or replaced scope sessions from starting queued frame
  capture work.
- [x] Bind timer-driven reverse-playback seeks to their timer generation and
  playback preparation.
- [x] Prevent stopped, restarted, or superseded reverse sessions from seeking
  active media through a queued stale tick.
- [x] Cover current, stopped, regenerated, and replacement identities with
  focused regression tests.
- [x] Pass the full test suite and static analysis.

Acceptance: a timer callback queued before scope capture or simulated reverse
playback stops cannot start work or seek after that session is stopped,
restarted, or replaced by newer media.

## Phase 23 — Dropped-file load ownership

Status: Completed on 2026-09-02. Asynchronous item-provider loads are now owned
by the player window and cancelled when superseded or when that window closes.

- [x] Retain and cancel the progress objects returned by dropped-file loads.
- [x] Invalidate the pending result collector when a newer drop replaces it.
- [x] Prevent a completion already queued on the main actor from opening files
  after its window closes or a newer drop starts.
- [x] Cover collector cancellation with a focused regression test.
- [x] Pass the full test suite and static analysis.

Acceptance: closing a player window or beginning a replacement drop cannot let
an earlier asynchronous provider completion open files or spawn new windows.

## Phase 24 — Deferred UI-work ownership

Status: Completed on 2026-09-02. Delayed waveform rerenders and timecode-entry
focus handoffs are now explicitly cancellable and owned by their SwiftUI views.

- [x] Extend the deferred main-actor task owner with cancellable delayed work.
- [x] Cancel a pending waveform gain rerender when its view disappears.
- [x] Cancel pending timecode focus and character insertion when editing ends
  or the controls disappear.
- [x] Cover delayed cancellation with a focused regression test.
- [x] Pass the full test suite and static analysis.

Acceptance: closing a waveform view cannot restart rendering after cleanup,
and cancelling timecode entry cannot restore focus or text from an obsolete
activation.

## Phase 25 — Media-operation feedback ownership

Status: Completed on 2026-09-02. Delayed screenshot and trim-export feedback
cleanup is now explicitly owned per operation. The expanded 135-test suite,
61-check release preflight, and static analysis pass.

- [x] Replace fire-and-forget screenshot and trim-export feedback timers with
  cancellable deferred-task owners.
- [x] Give screenshot and trim-export feedback independent ownership so one
  operation cannot cancel the other's cleanup.
- [x] Cancel pending cleanup when feedback is replaced, dismissed, or its
  player window closes.
- [x] Cover repeated equal-valued feedback with a focused regression test.
- [x] Pass the full test suite and static analysis.
- [x] Pass release preflight with the bundled ffmpeg signed using a Developer
  ID Application identity, Hardened Runtime, and a secure timestamp.

Acceptance: replacing, dismissing, or tearing down media-operation feedback
cannot let an obsolete delayed task clear a newer message, and no feedback
timer remains owned by a closed player window.

## Phase 26 — SwiftMediaMetadata 3.0.0 migration

Status: Completed on 2026-09-02. The renamed SwiftMediaMetadata package,
product, and module now use the latest 3.0.0 release and its exact resolved
revision.

- [x] Review the 3.0.0 changelog for source-breaking enum additions.
- [x] Confirm the app does not exhaustively switch over the affected XMP and
  photo-metadata value enums.
- [x] Raise the package requirement to 3.0.0 and refresh `Package.resolved`.
- [x] Remove stale current documentation that still describes the product and
  module as SwiftExif while preserving historical release notes.
- [x] Pass the full test suite and static analysis against 3.0.0.

Acceptance: a fresh package resolution selects SwiftMediaMetadata 3.0.0, the
app builds against its renamed module without compatibility shims, and current
documentation no longer describes the old SwiftExif package identity.

## Phase 27 — Playback-preparation ownership

Status: Completed on 2026-09-02. Asynchronous backend selection is now owned by
the player controller, cancelled during teardown, and guarded by a preparation
generation that teardown invalidates even if AVAsset property loading ignores
task cancellation.

- [x] Retain the asynchronous ProRes RAW backend-selection task.
- [x] Cancel backend selection whenever playback is torn down or replaced.
- [x] Advance the preparation identity during teardown so a late completion
  cannot construct a new backend after its player window closes.
- [x] Inject the codec probe and cover a suspended completion after teardown
  with a deterministic regression test.
- [x] Pass the full test suite and static analysis.

Acceptance: closing a player window or replacing its media while backend
selection is suspended cannot create an AVFoundation or MPV backend after
teardown.

## Phase 28 — Metadata-copy feedback ownership

Status: Completed on 2026-09-02. The metadata inspector's copied-confirmation
delay is now explicitly owned by the view, replaced on every copy, and
cancelled when the inspected media changes or the inspector disappears.

- [x] Replace the fire-and-forget copied-confirmation delay with a cancellable
  deferred-task owner.
- [x] Restart the full confirmation interval after every copy so an older
  delayed completion cannot hide newer feedback.
- [x] Cancel and clear pending copy feedback when the media changes or the
  inspector closes.
- [x] Cover delayed task replacement with a focused regression test.
- [x] Pass the full test suite and static analysis.

Acceptance: repeated metadata copies each receive their full confirmation
interval, and no copy-feedback task remains owned by a closed or repurposed
metadata inspector.

## Phase 29 — AVFoundation frame-boundary seek precision

Status: Completed on 2026-09-05 after the inspection-loupe pixel tests exposed
an off-by-one-frame comparison seek. The 319-test Release suite, static analysis, and all 61 release-preflight checks
pass; details are recorded with the loupe continuation in `COMPARE_MODE_IMPLEMENTATION_PLAN.md`.

- [x] Replace truncating seconds-to-CMTime conversion with explicitly rounded
  integer ticks at a timescale supporting the standard rational frame rates.
- [x] Apply the conversion to precise backend seeks, initial preparation,
  readiness replay, and interactive scrub targets.
- [x] Reject negative, non-finite, and unrepresentable targets safely.
- [x] Cover offset addition just below a frame boundary and integer/fractional
  frame-rate round trips.
- [x] Verify both backend clocks and changed captured pixels after a paused
  mapped frame step in both mixed-backend directions.

Acceptance: adding a comparison offset cannot truncate a precise AVFoundation
seek to the preceding frame through floating-point rounding.

## Phase 30 — Reflected QuickTime playback orientation

Status: Completed on 2026-09-05. The 329-test Release suite passes without
failures or skips; static analysis and all 61 release-preflight checks pass.
Asymmetric live-loupe fixtures exposed the bundled MPV retaining only rotation
from reflected QuickTime display matrices. A file-owned reflection correction
now applies to the decoder output, preserving agreement between playback,
scopes, and loupe captures.

- [x] Detect a negative display-transform determinant during MPV preparation.
- [x] Revalidate preparation identity and cancellation after the transform load.
- [x] Restore reflection before MPV rotation using a vertical filter and
  VideoToolbox copyback for reflected files only.
- [x] Preserve the existing decoding path for unreflected files.
- [x] Cover rotation, translation, reflection, and invalid transforms in pure
  tests.
- [x] Verify ten asymmetric real-media fixtures on each backend, including
  PAR, horizontal/vertical reflection, and reflected quarter-turn rotations.

Acceptance: reflected QuickTime source points appear in their intended display
quadrants in both backends and captured inspection imagery. Production UHD/HDR
performance of the reflection-only copyback/filter path remains a release gate
in `docs/INSPECTION_LOUPE.md`.

## Phase 31 — AVFoundation live-loupe frame acquisition

Status: Engineering complete on 2026-09-05. The 335-test Release suite passes
without failures or skips; static analysis and all 61 release-preflight checks
pass. Production loupe profiling exposed stale AVFoundation frame requests
while UHD/HDR playback and scopes continued.

- [x] Acquire the current AV pixel buffer before dispatching background work.
- [x] Keep metadata loading and image conversion in the single background worker.
- [x] Release the worker slot immediately when no buffer is available.
- [x] Preserve preparation identity and stop/replacement rejection.
- [x] Add hosted mixed-backend loupe and scope workloads with changed-pixel
  cadence, capture-gap, responsiveness, decoder identity, and cleanup checks.
- [x] Verify paused, transformed, stepped, and playing capture with the full suite.

Acceptance: the production workload publishes fresh loupes independently from
both decoders, with the existing bounded worker ownership and safe teardown.
The eight-second reflected UHD/HDR loupe checks pass after the fix; complete
profile results and remaining hardware gates are recorded in
`docs/INSPECTION_LOUPE_PROFILE_2026-09-05.md`.

## Phase 32 — MPV native surface sizing

Status: Completed on 2026-09-06. All 343 Release tests pass with no failures
or skips; static analysis and all 61 release-preflight checks pass.
A native loupe acceptance check exposed comparison pictures retaining the
fixed 640×480 bootstrap dimensions after the window enlarged.

- [x] Supply the fitted picture size before attaching MPV to its Metal layer.
- [x] Explicitly update the retained view and drawable when SwiftUI geometry
  changes, including when AppKit does not deliver a layout callback.
- [x] Defer attachment until initial dimensions are finite and usable.
- [x] Preserve existing single-source and coordinated comparison reload policy.
- [x] Cover initial sizing, grow/shrink updates, layer identity, invalid geometry,
  and one-shot reload ownership with focused regressions.
- [x] Repeat the native narrow-to-large MPV/MPV reproduction and visually verify
  fitted pictures in side-by-side, A, B, Vertical Wipe, and fullscreen/exit.
- [x] Pass the full Release suite, static analysis, and release preflight.

Acceptance: comparison pictures occupy their fitted panes after native window
changes. The targeted desktop check is recorded in
`docs/INSPECTION_LOUPE_NATIVE_CHECK_2026-09-06.md`; it does not replace the
remaining all-mode pointer, accessibility, transformed-media, or base-M1 gates.

## Phase 33 — Structured comparison reviews

Status: Completed on 2026-09-06. All 356 Release tests pass without failures
or skips; static analysis and all 61 release-preflight checks pass.

- [x] Add editable severity, category, and status with searchable labels.
- [x] Add inclusive source-A range notes with explicit endpoint validation,
  current-frame capture, end seeking, single-frame reset, and timeline bands.
- [x] Read legacy schema 1 notes and write schema 2 to prevent older app versions
  from silently dropping structured fields.
- [x] Preserve classifications and ranges in CSV/PDF and editor-marker exports.
- [x] Test migration, invalid data rejection, persistence, fractional-rate
  duration arithmetic, and cross-format report content.
- [x] Pass the complete Release suite, static analysis, and release preflight.

Acceptance: classifying or extending a finding retains its original A/B anchor,
text, and stored rational rates; legacy reviews remain readable. Spatial image
annotations, editor round trips, and hands-on keyboard/VoiceOver acceptance
remain roadmap and release work. Phase 34 adds deliberate relinking.

## Phase 34 — Review-sidecar relinking and export consistency

Status: Completed on 2026-09-06. The 376-test Release suite passes without
failures or skips; the final failure-alert change also passes all 36 focused
review tests. Static analysis and all 61 release-preflight checks pass. Native
picker, mapping confirmation, cancellation, visible failure, and successful
import are recorded in `docs/COMPARE_REVIEW_RELINK_CHECK_2026-09-06.md`.

- [x] Provide a deliberate old-to-current A/B mapping preview and confirmation.
- [x] Preserve findings in a new pair-specific sidecar without overwriting the
  original or any existing destination.
- [x] Reject stale previews, invalid documents, unavailable media, concurrent
  destination collisions, and cancelled work before publication.
- [x] Isolate preview/confirmation/write state from replacement and closed sessions.
- [x] Reject editor-marker exports whose stored A rate differs from loaded media;
  accept mathematically equivalent rational rates without overflow.
- [x] Prevent mixed-rate findings from sharing an incorrect annotated PDF still.

Acceptance: relocated original media can recover its review through an explicit
mapping while preserving note data and existing files. Relinking does not
retime findings, infer content equality, or merge reviews. Hands-on keyboard/
VoiceOver acceptance and editor round trips remain release gates.

## Phase 35 — Timeline viewport and report provenance

Status: Engineering complete on 2026-09-06. All 382 Release tests pass without
failures or skips; static analysis and all 61 release-preflight checks pass.

- [x] Add per-window 2×–64× timeline zoom around the playhead and one-action Fit.
- [x] Add a full-duration overview for panning without seeking, with keyboard
  and VoiceOver adjustment hooks and focus-held controls.
- [x] Map normal and precision scrubbing into the visible interval while
  retaining existing frame-step and comparison transport commands.
- [x] Clip chapter, trim, review-range, and comparison-overlap geometry to the
  viewport; hide offscreen point markers rather than piling them at the edges.
- [x] Reset zoom on primary replacement and reveal playback outside the viewport.
- [x] Preserve exact stored A/B rational rates and full source URLs in appended
  CSV columns without moving existing report fields.
- [x] Cover long-recording fractional-frame mapping, viewport boundaries,
  invalid geometry, clipped ranges, same-named sources, and changed loaded rates.

Acceptance: timeline zoom changes display geometry only, and CSV reports retain
unambiguous source paths and stored timebases. Native timeline pointer, Full
Keyboard Access, and VoiceOver checks remain in `docs/TIMELINE_NAVIGATION.md`.
Native editor round trips and release-floor playback/loupe profiling remain
separate release gates; this phase does not claim them complete.

## Phase 36 — Bounded timeline thumbnails

Status: Engineering complete on 2026-09-06. The 386-test Release suite and
40 final focused tests pass without failures or skips. Static analysis and
all 61 release-preflight checks pass.

- [x] Add approximate hover previews mapped through the visible timeline.
- [x] Debounce requests, coalesce pointer movement, and allow one decoder worker.
- [x] Bound the per-window cache to 32 images fitted within 240 × 135 pixels.
- [x] Cancel on dismissal and replacement; reject obsolete results and clear
  the cache when source A changes.
- [x] Preserve display aspect ratio in the ffmpeg fallback, including rotated
  anamorphic media, and leave audio-only sources without preview work.
- [x] Pass integrated Release tests and static analysis.

Acceptance: lazy navigation does not seek or accumulate decoder work. Preview
timecodes are approximate, and native hover/accessibility checks and long-file
release-floor profiling remain in `docs/TIMELINE_NAVIGATION.md`.

## Phase 37 — Review report coordinate integrity

Status: Engineering complete on 2026-09-06. The 386-test Release suite and
40 final focused tests pass without failures or skips. Static analysis and
all 61 release-preflight checks pass.

- [x] Derive report relative timecodes from stored rational frame coordinates,
  without clamping to shorter replacement media.
- [x] Add source-timecode offsets with integer frame arithmetic only when the
  current source rate agrees with the stored rate.
- [x] Omit unavailable annotated A/B stills, keeping the finding and an explicit
  PDF explanation instead of substituting an unrelated last frame.
- [x] Reject Resolve EDL positions and exclusive endpoints reaching the
  24-hour wrap boundary with an actionable alternate-format message.
- [x] Cover shorter A/B replacements, unavailable EOF frames, changed rates,
  preserved PDF text, and near-midnight NDF/DF boundaries.
- [x] Pass integrated Release tests and static analysis.

Acceptance: a report preserves the finding's recorded coordinates and never
silently labels a clamped image as its original frame. Native editor round
trips remain in `docs/COMPARE_MODE_INTERCHANGE.md`.

## Phase 38 — Thumbnail and editor-marker source integrity

Status: Completed on 2026-09-06. The 393-test Release suite passes without
failures or skips; static analysis and all 61 release-preflight checks pass.

- [x] Invalidate thumbnail cache entries when a source URL changes even if the
  media identifier remains unchanged.
- [x] Reject obsolete decoder results while keeping replacement work serialized.
- [x] Clamp extreme finite thumbnail timestamps before safe quantization.
- [x] Preserve full current A/B URLs, stored rational rates, and explicit B
  source/relative timecode labels in editor-marker note text.
- [x] Reject oversized Avid marker text with an actionable alternate-format
  message instead of silently truncating a finding.
- [x] Add focused source-replacement, overflow, provenance, and text-limit tests.

Acceptance: thumbnail images belong to the requested source, and editor export
cannot silently discard finding text or make same-named sources ambiguous.
Actual editor import/re-export remains an independent gate.

## Phase 39 — Primary drawable ownership across comparison transitions

Status: Completed on 2026-09-06. All 394 Release tests pass without failures
or skips in an isolated run. Final static analysis and all 61 release-preflight
checks pass. Native paused entry, B replacement, and exit were repeated after
tests finished; both pictures and A's paused frame remained correct. See
`docs/COMPARE_SURFACE_NATIVE_CHECK_2026-09-06.md`.

- [x] Preserve the primary native video surface when entering comparison,
  replacing B, and exiting comparison.
- [x] Present inactive sessions as full-resolution source A, independent of
  saved comparison view, gain, guides, and live-render resolution.
- [x] Add a real ContentView/MPV regression for paused entry and B replacement
  and exit during playback, retaining the drawable and preparation identities.
- [x] Pass the final Release suite and static analysis.
- [x] Repeat the original native paused-entry reproduction and verify A/B
  images on entry, replacement, and exit.

Acceptance: changing comparison membership cannot leave A rendering into an
obsolete detached layer, and single-source viewing ignores comparison effects.

## Phase 40 — Selected-range loudness analysis

Status: Completed on 2026-09-06. All 400 Release tests pass, static analysis
passes, and release preflight passes all 61 checks. The new silence-export
regression uses lossless ALAC/M4A, supported by the metadata parser.

- [x] Measure integrated loudness, loudness range, and true peak for the
  selected In–Out interval or the whole source audio stream.
- [x] Trim decoded samples before measurement, preserve source-relative
  timestamp offsets, and stop input at Out.
- [x] Cancel per-stream work explicitly and invalidate selected-range results
  when markers, scope, or media change.
- [x] Preserve measured range bounds and digital-silence values in copied JSON.
- [x] Add real bundled-ffmpeg tests for level separation, nonzero container
  timestamps, delayed audio streams, and silence export.
- [x] Pass the final integrated Release suite, static analysis, and preflight.

Acceptance: range measurements describe the selected source samples and carry
their interval into metadata export. Live metering and standards compliance
are outside this phase. See `docs/AUDIO_LOUDNESS.md`.

## Phase 41 — Reproducible long-file thumbnail profiling

Status: Completed on 2026-09-06. All 120 production-loader requests pass over
synthetic 1/8/24-hour long-GOP files on the M5 Pro. The final 400-test Release
suite, static analysis, and all 61 preflight checks pass. Test-only AppKit
surface teardown and overlay state now also obey explicit main-actor isolation.

- [x] Exercise the production loader against explicitly selected long files.
- [x] Measure 40 distributed non-keyframe requests with the real hover delay,
  image dimensions, cache cap, cached reopening, and teardown checks.
- [x] Retain environment, input hashes, XCTest artifacts, latency distribution,
  sampled app-process resident memory, and pixel-cache storage bounds.
- [x] Reject missing/incomplete profile records even when XCTest returns success.
- [x] Record the final 1/8/24-hour local baseline and integrated verification.

Acceptance: maintainers can repeat the same production thumbnail workload on
representative sources and the release-floor Mac. The harness does not replace
native hover acceptance or concurrent UHD/HDR playback profiling. See
`docs/TIMELINE_THUMBNAIL_PERFORMANCE.md`.

## Phase 42 — Audio QC edge cases and accessible monitoring controls

Status: Completed on 2026-09-06. All 404 Release tests pass without failures
or skips, static analysis passes, and all 61 preflight checks pass. Focused
native audio-menu and inspector checks are recorded in
`docs/AUDIO_QC_NATIVE_CHECK_2026-09-06.md`.

- [x] Reject a successful FFmpeg summary when the selected stream contributes
  no samples, including ranges before a delayed stream or after its end.
- [x] Preserve valid digital-silence measurements and show an actionable
  empty-selection error in the inspector.
- [x] Cover 5.1 weighting and LFE exclusion, independent multi-track selection,
  malformed audio, missing streams, and cancellation followed by retry.
- [x] Expose channel Solo/Mute as native checked controls and describe enabled
  channels in the audio menu's accessible value.
- [x] Identify each loudness scope/measure/cancel control by audio stream and
  combine metric labels with their values for accessibility.
- [x] Pass the integrated Release suite, static analysis, and release preflight.

Acceptance: absent audio cannot masquerade as a measured 0 dB peak, and audio
monitoring state is exposed to accessibility clients. Native VoiceOver/Full
Keyboard Access and calibrated reference/performance checks remain separate.

## Phase 43 — Stable MPV drawable sizing during playback

Status: Completed on 2026-09-07. All 406 Release tests pass without failures
or skips; static analysis and all 61 release-preflight checks pass.

- [x] Preserve AppKit-aligned native bounds when SwiftUI repeats an unchanged
  fractional fitted-picture proposal during playback.
- [x] Derive explicit drawable updates from the same native bounds used by
  AppKit layout, preventing alternating one-pixel surface allocations.
- [x] Retain immediate surface resizing when the actual proposal changes.
- [x] Add a regression for repeated fractional proposals, native alignment,
  stable drawable dimensions, and a subsequent real resize.
- [x] Pass the integrated Release suite, static analysis, and release preflight.

Acceptance: a stable window cannot continually rebuild the MPV swapchain just
because SwiftUI and AppKit round a fitted picture differently. An 8K playback
session exposed repeated 3111/3112-pixel allocations at unchanged native bounds;
the regression recreates that proposal/alignment sequence. Representative native
playback and release-floor performance remain separate checks.

## Phase 44 — Reproducible multichannel loudness profiling

Status: Completed on 2026-09-07. The isolated one/eight-hour 5.1 profile and
its artifact validator pass. All 406 Release tests, five profile-validator tests,
static analysis, and all 61 release-preflight checks pass.

- [x] Exercise production whole-file and early/late 30-second range analysis
  against explicitly selected long multichannel files.
- [x] Record stream metadata, measurement values, wall time, and separately
  sampled parent/FFmpeg child resident memory with a cancellation deadline.
- [x] Retain hardware/build details, source hashes, raw XCTest attachments,
  and validated machine-readable results.
- [x] Reject incomplete inputs/scopes, invalid timing/ranges, inconsistent
  stream metadata, and missing memory observations with validator regressions.
- [x] Record an isolated one/eight-hour 5.1 baseline.
- [x] Pass the integrated Release suite, static analysis, and release preflight.

Acceptance: maintainers can repeat the real analysis workload on representative
sources and the release-floor Mac. Sampled memory is an observation, not a proof
of bounds for every codec; reference accuracy, concurrent-job UI acceptance,
and live meters remain separate. The eight-hour metadata discovery also exposed
a roughly 2.3 GiB transient parent resident-memory spike; that memory gate remains open.
See `docs/AUDIO_LOUDNESS_PERFORMANCE.md`.

## Phase 45 — Native loudness cancellation and numerical references

Status: Completed on 2026-09-07. All 409 Release tests, static analysis, and
all 61 release-preflight checks pass. Final native cancellation, retry, and
keyboard inspector hide/reopen checks also pass.

- [x] Cancel active loudness work when the native inspector is hidden, even
  when SwiftUI retains its content and does not call `onDisappear`.
- [x] Give per-stream cancellation its own full-width action row.
- [x] Add independently synthesized PCM references for absolute stereo levels,
  absolute/relative gating, and phase-sensitive intersample true peaks.
- [x] Exercise two simultaneous native stream measurements, individual
  cancellation, surviving-job completion, and inspector hide/reopen cleanup.
- [x] Pass the final integrated Release suite and static analysis.

Acceptance: hiding analysis controls cannot leave their jobs running invisibly,
while cancelling one stream leaves another independent job intact. Selected
EBU numerical references are regression evidence, not complete certification.
See `docs/AUDIO_QC_NATIVE_CHECK_2026-09-07.md` and `docs/AUDIO_LOUDNESS.md`.

## Phase 46 — Metadata memory diagnosis and candidate dependency fix

Status: Diagnosis and selected candidate validation complete on 2026-09-07;
production integration remains open.

- [x] Isolate the spike to RTMD detection's generic top-level box walk, which
  materializes `mdat` even in ordinary audio-only M4A files.
- [x] Preserve a minimal dependency patch using the existing skip-mdat walker.
- [x] Add a reproducible baseline/patched harness with fresh processes,
  source/input hashes, lifetime-peak RSS, and selected metadata parity checks.
- [x] Verify one/eight-hour ALAC inputs: normal-read peaks fall from
  564/4,447 MiB to 11/20 MiB, with all 12 workload/parity checks passing.
- [x] Validate 27 synthetic RTMD/container cases against original and candidate
  builds: leading/trailing `moov`, absolute `stco`/`co64` offsets, extended/zero
  atoms, malformed/truncated inputs, decoded frames, and complete motion samples.
  All 54 isolated runs pass. See `docs/METADATA_CONTAINER_VALIDATION.md`.
- [x] Validate the full paired memory workload matrix before summary publication;
  reject invalid scalar types, non-finite metrics, incomplete snapshots, missing
  workloads, and inconsistent raw/summary records. Eight validator regressions
  and the retained 12-workload baseline pass.
- [x] Compare a native Sony clip's 672 RTMD frames, first-frame snapshot,
  2,000 Hz IMU rate, and complete 26,880-sample gyro/accelerometer streams;
  compare exported metadata for Sony, BRAW, CRM, and R3D. All paired results match.
  The final run verifies unchanged media and NRT sidecar hashes; see
  `docs/METADATA_REAL_MEDIA_VALIDATION.md` for exact coverage and limitations.
- [x] Run the candidate's local upstream library Release suite: 1,662 tests,
  20 fixture-dependent skips, zero failures. CLI tests are excluded; the
  selected local CRM is independently covered by the paired exporter check.
- [x] Run the unchanged candidate Release CLI suite offline: all 50 tests
  pass without skips or failures. Require every pinned suite and both aggregate
  totals; nine acceptance-validator regressions reject incomplete evidence.
- [x] Extend paired native-media parity to a second Sony A1 clip (5,568 RTMD
  frames and 222,720 samples per motion stream), ProRes RAW HQ, ARRIRAW, and
  X-OCN LT. All five paired workloads pass on 2026-09-08 with unchanged inputs.
- [ ] Complete upstream review and remaining fixture coverage, integrate a
  reviewed dependency release, and repeat full-app memory profiling. The latest
  remote tag is still 3.0.0 as checked on 2026-09-08.

Acceptance: the source of the memory spike and a measured candidate fix are now
established. The app still uses the original pinned dependency; its memory gate
remains open. See `docs/METADATA_MEMORY_PERFORMANCE.md`.

## Phase 47 — Loudness range references across sample rates

Status: Completed on 2026-09-07. All 410 Release tests pass without failures
or skips; Xcode static analysis and all 61 release-preflight checks pass.

- [x] Add independently synthesized EBU Tech 3342 LRA cases 1–4 at 44.1, 48,
  and 96 kHz, including exclusion of quiet sections by relative gating.
- [x] Extend EBU absolute stereo calibration to those three sample rates.
- [x] Verify all 18 calibration/LRA references through production analysis.
- [x] Document the exact numerical scope without claiming full certification.

Acceptance: selected offline LRA and calibration references pass at three
sample rates. Authentic programme material, transient peaks, additional channel
layouts, and live-meter behavior remain separate. See `docs/AUDIO_LOUDNESS.md`.

## Phase 48 — Independent channel-layout loudness references

Status: Completed on 2026-09-07. All 415 Release tests pass without failures
or skips; static analysis and all 61 release-preflight checks pass.

- [x] Synthesize explicit WAVEFORMATEXTENSIBLE speaker layouts in Swift.
- [x] Verify absolute front-channel calibration in 2.1 and 3.0 layouts.
- [x] Check isolated front and side-surround weights in 5.1(side).
- [x] Verify that loud LFE signals contribute to true peak but not integrated
  loudness in 2.1, 5.1(side), and the front/LFE portion of 7.1.
- [x] Pass the integrated Release suite and static analysis.

Acceptance: 13 independent 48 kHz references supplement the existing stereo
and sample-rate matrix. Programme material, transient peaks, 7.1 rear weighting,
immersive layouts, and live meters remain separate. See `docs/AUDIO_LOUDNESS.md`.

## Phase 49 — Native review feedback and accessible finding identity

Status: Focused scope completed on 2026-09-07. Updated labels and saved-note
restoration are verified in the rebuilt native app; all 415 Release tests,
static analysis, and 61 release-preflight checks pass.

- [x] Confirm native note creation via Return, filter-field Tab focus, and
  filtering without deleting the stored finding.
- [x] Save a CSV while its note is hidden by the filter and verify the finding,
  exact source-frame rates, timecodes, and full A/B URLs in the output.
- [x] Give Add, note text, and Delete explicit accessibility labels, including
  source-A frame identity for repeated finding rows.
- [x] Verify updated labels in the rebuilt native app.

Acceptance: this is partial native review evidence. Full keyboard traversal,
spoken VoiceOver, range editing, relinking, and narrow-window acceptance remain
open. See `docs/COMPARE_REVIEW_NATIVE_CHECK_2026-09-07.md`.

## Phase 50 — Broader true-peak references and 7.1 measurement qualification

Status: Completed on 2026-09-08. All 417 Release tests pass with no skips or
unexpected failures; two strict expected rear-weight discrepancies are recorded. Static
analysis and all 61 release-preflight checks pass. The rebuilt native inspector
shows the full qualification at its normal width.

- [x] Extend independent phase-sensitive true-peak references to 44.1 and
  96 kHz, retaining the existing 48 kHz cases.
- [x] Test isolated 7.1 side and rear speakers against BS.1770-5 weights.
  Rear references expose a bundled-analyzer discrepancy: −24.5 LUFS versus
  the −26.0 LUFS reference. Strict expected failures retain the standards
  target; separate assertions pin the diagnosed behavior.
- [x] Show the known 7.1 weighting limitation beside inspector measurements
  and retain it as `lufsWarning` in copied JSON for measured 7.1 streams.
- [x] Cover measured/unmeasured and affected/unaffected JSON exports.
- [x] Verify native layout and full accessibility text; explicitly allow wrapped
  warning text so the standard-width inspector does not truncate it.
- [x] Pass the integrated Release suite and static analysis.

Acceptance: additional numerical coverage and truthful measurement qualification
are in place. Rear weighting was subsequently corrected in Phase 51; these
historical expected failures were not evidence of standards conformance. See
`docs/AUDIO_LOUDNESS.md`.

## Phase 51 — Correct conventional 7.1 loudness weighting

Status: Completed on 2026-09-08. All 425 Release tests pass without failures,
expected failures, or skips; static analysis and all 61 release-preflight checks pass.

- [x] Correct conventional 7.1 rear-speaker energy weights inside the analysis
  graph without altering source samples, playback, or true-peak amplitudes.
- [x] Require explicit eight-channel `7.1` metadata; reject missing named input
  speakers rather than silently remixing a mismatched source.
- [x] Record correction provenance on results and copied JSON; preserve legacy
  decoding and warnings for uncorrected measurements.
- [x] Replace the expected rear-weight failures with standards assertions and
  cover all seven non-LFE speakers at 44.1/48/96 kHz, mixed-channel levels,
  selected ranges, LFE peaks, gating/LRA, and rear intersample peaks.
- [x] Compare every Float32 sample through the complete production graph.
- [x] Route stream metadata through the inspector and production profiler;
  verify selection of a conventional 7.1 stream from a real multi-stream MOV.
- [x] Pass final full Release regression, static analysis, and release preflight.

Acceptance: conventional 7.1 offline analysis uses BS.1770-5 rear weights and
preserves source true peaks. This is selected numerical evidence, not complete
standards certification. Native inspection of the revised explanatory text and
broader programme/live-meter acceptance remain open. See `docs/AUDIO_LOUDNESS.md`.

## Phase 52 — Transient true-peak references and native loudness layout

Status: Completed on 2026-09-08. All 426 Release tests pass without failures,
expected failures, or skips; static analysis and all 61 release-preflight
checks pass.

- [x] Add 12 independently synthesized, band-limited transient references at
  44.1/48/96 kHz, with both polarities and peaks above full scale while stored
  PCM samples remain below full scale.
- [x] Verify reconstructed peaks against analytical maxima through the
  production analyzer, including separation from sample-peak measurements.
- [x] Confirm native pre/post-measurement 7.1 correction text, accessible
  stream identity, and a rear-speaker measurement in the rebuilt app.
- [x] Fix the truncated native Loudness Analysis heading by placing it above
  the scope control; verify the normal-width layout after rebuilding.
- [x] Pass the integrated Release suite and static analysis.

Acceptance: selected transient reconstruction references and native correction
layout are covered. Authentic programme material, broader transient families,
Full Keyboard Access, and spoken VoiceOver remain separate acceptance work.
See `docs/AUDIO_LOUDNESS.md` and `docs/AUDIO_QC_NATIVE_CHECK_2026-09-08.md`.

## Phase 53 — Bounded WAVE metadata and broader transient references

Status: Completed on 2026-09-08. All 435 Release tests pass without failures
or skips; static analysis and all 61 release-preflight checks pass.

- [x] Diagnose the missing Float32 WAVE inspector metadata: the production
  video-metadata API does not handle RIFF/WAVE. The separate audio API copies
  chunk payloads, omits duration, and guesses surround layout from channel count.
- [x] Add bounded PCM/IEEE-float RIFF header reading, exact frame-derived
  duration, and explicit extensible speaker-mask handling without remuxing.
- [x] Cover classic/extensible formats, malformed headers, unknown masks,
  out-of-order chunks, and a sparse 1 GiB recording with regression tests.
- [x] Add 18 independent transient references spanning signed-sidelobe and
  two-carrier pulses, three sample rates, and left/right/anti-phase stereo.
- [x] Pass integrated Release regression and static analysis.

Acceptance: supported PCM/IEEE-float RIFF WAVE files expose audio metadata
without loading the recording into memory or guessing conventional 7.1.
RF64/BW64, compressed WAVE, BWF tags, native inspector acceptance, authentic
programme material, and live meters remain separate work.

## Phase 54 — Large WAVE containers and contextual review controls

Status: Completed on 2026-09-08. All 444 Release tests, static analysis, and
61 preflight checks pass. Focused native WAVE, review and relink checks pass.

- [x] Extend bounded audio metadata reading to RF64/BW64, including 64-bit
  data and ancillary sizes, repeated table IDs, and format-specific sample counts.
- [x] Bound retained size-table entries and reject malformed headers, incomplete
  frames, overflowing lengths, and inconsistent RF64 sample counts.
- [x] Add eight regressions covering production FFmpeg RF64 output, sparse
  8 GiB recordings, large ancillary chunks, and RF64 `fact` precedence.
- [x] Give review seek, classification, and range controls source-frame context;
  adapt range actions to available width and expose complete relink path values.
- [x] Verify native RIFF/RF64/BW64 metadata and corrected rear-speaker loudness.
- [x] Verify distinct expanded review labels, keyboard range submission and
  explicit relinking with unchanged complete findings and original sidecar.
- [x] Pass integrated Release regression, static analysis and preflight.

Acceptance: technical RF64/BW64 metadata support does not imply ADM tag
interpretation, live-meter conformance, or complete keyboard/VoiceOver acceptance.
See `docs/WAVE_METADATA.md` for supported formats and resource bounds, and
`docs/COMPARE_REVIEW_NATIVE_CHECK_2026-09-08.md` for native evidence and limits.

## Phase 55 — Original ITU programme loudness references

Status: Completed on 2026-09-08. The three official references pass in isolation
and in the full 444-test Release suite, with no failures or skips. Static
analysis and all 61 release-preflight checks pass.

- [x] Obtain original mono voice/music, stereo, and six-channel programme
  references directly from ITU, retaining media outside the repository.
- [x] Pin original SHA-256 hashes and verify metadata plus whole-file integrated
  loudness through the production service against the published −23 ±0.1 target.
- [x] Add an explicit opt-in runner retaining results, hashes and build evidence;
  require all three records so an unconfigured test cannot pass as validation.
- [x] Record programme LRA and true peak as observations without reference claims.
- [x] Pass the full integrated suite with original programme references enabled,
  static analysis and release preflight.

Acceptance: all three original files measure −23.0 LUFS. This adds authentic
programme integrated-loudness evidence, not programme LRA/true-peak or complete
meter certification. EBU programme LRA download returned HTTP 403; those cases
remain open. See `docs/AUDIO_PROGRAMME_REFERENCES.md`.

## Phase 56 — Broadcast WAVE recording metadata

Status: Completed on 2026-09-08. All 453 Release tests pass with both ITU
reference opt-ins enabled, along with static analysis, 61 release-preflight
checks and focused native inspector acceptance.

- [x] Read bounded `bext` recording identity, origination date/time, exact
  64-bit sample references, raw UMID, and coding-history fields.
- [x] Decode valid version-2 embedded loudness with sentinel/range checks and
  display its producer provenance separately from the player's measurements.
- [x] Preserve BWF values in metadata JSON without treating sample references
  as video timecode or adding audio-sized allocations.
- [x] Add eight regressions covering version gates, malformed/duplicate chunks,
  RF64/BW64, JSON compatibility and sparse 1 GiB coding history.
- [x] Pass integrated Release tests and native inspector acceptance.

Acceptance: the reader retains at most 602 fixed bytes plus 16 KiB of coding
history. ADM/iXML interpretation, compressed WAVE and spoken VoiceOver remain
separate. See `docs/WAVE_METADATA.md`.

## Phase 57 — Official eight-channel loudness evidence

Status: Completed on 2026-09-08. The original reference passes through the
rebuilt Release analyzer at −23.0 LUFS and in the full 453-test Release suite.

- [x] Obtain and pin the original ITU eight-channel −23 LKFS gain reference.
- [x] Prepare an explicit conventional 7.1 WAVE with a lossless channel reorder
  from ITU's documented speaker order, pinning the resulting PCM hash.
- [x] Add an opt-in production-analyzer test and result-validating runner.
- [x] Verify the official −23 ±0.1 target and correction provenance.

Acceptance: this is an original reference with documented sample-preserving
speaker-order preparation. Its missing-mask original is not automatically
interpreted as conventional 7.1 by the app. Programme LRA/true-peak and immersive
layout conformance remain separate. See `docs/AUDIO_PROGRAMME_REFERENCES.md`.

## Phase 58 — Narrow comparison controls and native relink edge cases

Status: Completed on 2026-09-08. Rebuilt 270/1,728-point native toolbar checks,
all 453 Release tests, static analysis and 61 release-preflight checks pass.

- [x] Diagnose a comparison toolbar extending beyond the 270-point player.
- [x] Collapse comparison settings into a scrollable popover when needed,
  retaining direct Review, Exit, Loupe and Inspector access.
- [x] Preserve settings, use labeled compact controls, and close the popover
  before file/export panels or source transitions.
- [x] Verify native relink picker and preview cancellation creates no sidecar.
- [x] Verify a destination created after preview produces an actionable conflict
  and preserves both original and destination bytes.
- [x] Validate rebuilt narrow/wide native layouts and integrated regression.

Acceptance: native pointer access at narrow widths and relink data safety are
separate from complete Full Keyboard Access, spoken VoiceOver, and NLE round trips.
See `docs/COMPARE_REVIEW_NATIVE_CHECK_2026-09-08.md`.

## Phase 59 — Big-endian WAVE metadata and safe offline decoding

Status: Engineering complete on 2026-09-08. All 35 focused WAVE/RIFX tests pass.

- [x] Read classic RIFX PCM/float metadata with bounded big-endian header reads,
  correct codec labels, malformed-input checks and a sparse 1 GiB regression.
- [x] Detect the bundled FFmpeg sample-byte-order error and select a validated
  input decoder for offline loudness and waveform generation.
- [x] Verify actual positive/negative samples at all seven encoding widths,
  independent calibration tones and production waveform amplitudes.
- [x] Reject unsafe RIFX playback and trim export with conversion guidance,
  including without metadata. Native opening confirms the error reaches the UI.

Acceptance: metadata and offline analysis support classic RIFX. Playback/export,
RIFX extensible/BWF variants and producer-authentic acceptance remain separate.
See `docs/WAVE_METADATA.md`.

## Phase 60 — Independent programme loudness-range comparison

Status: Completed on 2026-09-08. The fresh Release runner passes all three
official integrated targets, all three independent LRA comparisons (largest
difference 0.1416 LU), and nine calculator regressions.

- [x] Calculate LRA directly from the three hash-pinned original ITU PCM files
  using published K-weighting and EBU short-term gating/percentile rules.
- [x] Check the calculator against all four synthesized EBU LRA sequences,
  absolute calibration, channel isolation, gates and malformed inputs.
- [x] Integrate it into the programme runner with retained source, hashes,
  Python version, calculated/app values and explicit target provenance.

Acceptance: these are independently calculated comparison values, separate
from published programme LRA targets. EBU's original programme download still
returns HTTP 403; those cases and programme true-peak targets remain open.
See `docs/AUDIO_PROGRAMME_REFERENCES.md`.

## Phase 61 — Comparison toolbar keyboard ownership and focus visibility

Status: Native keyboard verification complete on 2026-09-08. Keyboard-only
comparison opening, point-note creation/restoration/CSV export, wipe adjustment
and focus-triggered scrolling pass. Integrated verification is recorded below.

- [x] Reproduce Space starting playback while Add Comparison owns focus.
- [x] Track all toolbar controls, preserve visible focus rings and overlay
  visibility, and let focused controls receive Space and arrow keys.
- [x] Keep raw keys in compact comparison settings instead of running playback
  shortcuts while menus/sliders are being operated.
- [x] Reveal controls reached below the compact popover's visible scroll area.
- [x] Verify a keyboard-only point-note creation/reopen/CSV export workflow,
  preserving text, exact A/B frame anchors/rates and source URLs.

Acceptance: macOS Keyboard Navigation is distinct from Accessibility's Full
Keyboard Access and spoken VoiceOver. Complete assistive-technology, editor
round-trip and hardware matrices remain open. Native evidence is retained in
`docs/COMPARISON_KEYBOARD_NATIVE_CHECK_2026-09-08.md`.

## Integrated continuation verification — 2026-09-08

All **464 Release tests pass with zero failures and zero skips**, with both
original ITU reference sets enabled. The suite took 113.316 seconds (113.592
including suite overhead). Release static analysis and all 61 release-preflight
checks pass. Existing loudness/metadata/profile validators also pass, and the
fresh programme runner includes all nine independent LRA calculator checks.

Artifacts: `/tmp/aagedal-rifx-keyboard-full-20260908.xcresult`,
`/tmp/aagedal-rifx-keyboard-full-20260908.log`,
`/tmp/aagedal-rifx-keyboard-analyze-20260908.log` and
`/tmp/aagedal-programme-lra-fresh-20260908`. These temporary artifacts are
reproducible evidence, not a durable release archive. Native keyboard acceptance
and RIFX error propagation are recorded separately from the XCTest run.

## Phase 62 — Bounded iXML recording labels

Status: Implementation complete on 2026-09-09; integrated verification is
recorded below.

- [x] Read explicit UTF-8 BWFXML project, scene, take, tape/sound roll, note,
  version, circled-take and UID labels from RIFF/RF64/BW64 without audio reads.
- [x] Bound payload, nesting, element count and retained field sizes; reject
  DTD/entities, malformed or ambiguous XML without losing valid PCM/BWF data.
- [x] Keep iXML separate from Broadcast WAVE fields in the model, inspector
  and copied JSON; do not infer timecode, speaker layout or loudness.
- [x] Add eleven regressions including XML edge cases, sparse audio skipping,
  and metadata-service/inspector JSON integration.

Producer-authentic recorder fixtures, additional encodings and ADM remain
separate acceptance work. See `docs/WAVE_METADATA.md`.

## Phase 63 — Exact frame rates from decimal metadata

Status: Native export reproduction diagnosed and corrected on 2026-09-09;
integrated and rebuilt native verification are recorded below.

- [x] Reproduce a real 29.97 review failing editor export because decoded
  metadata was rounded to `29970/1000`, differing from stored `30000/1001`.
- [x] Normalize known decimal broadcast rates to their rational timebases,
  retain micro-fps precision for other decimals and reject unsafe numeric input.
- [x] Preserve explicit rationals and existing review rates without silently
  retiming historical findings or weakening editor-export compatibility checks.
- [x] Require exact rational rates through generated-media metadata reads and
  verify 29.97/59.94 drop-frame source labels plus CSV/EDL/FCPXML/Avid output.
- [x] Add disposable editor acceptance fixture generation for eight structured
  findings, fractional rates, duplicate/adjacent/final frames and DF boundaries.

Old reviews captured with rounded rates retain their original coordinates;
CSV/PDF remain available, while editor export rejects the differing timebase.
An explicit migration workflow remains separate work. Actual editor round
trips remain unverified; Final Cut Pro launch automation timed out in this run.

## Phase 64 — Independent authentic-programme true-peak comparison

Status: Independent calculation complete on 2026-09-09; current Release
integration is recorded below.

- [x] Calculate all three pinned original ITU 48 kHz PCM16 programmes with
  the published BS.1770-5 Annex 2 four-phase FIR, including every channel/LFE.
- [x] Use bounded PCM blocks and exact coefficient arithmetic; complete the
  filter tail and skip only blocks with a proven upper bound below the peak.
- [x] Add eleven calibration, channel/boundary and malformed-evidence checks.
- [x] Integrate the independent comparison into the existing programme runner.

Selected calculated values agree with production within the preselected
0.4 dB project tolerance. This is distinct from published programme targets;
the authentic EBU 5/15 LU LRA files remain unavailable from the official server.
Broader content/rates and live meters remain open. See
`docs/AUDIO_PROGRAMME_REFERENCES.md`.

## Phase 65 — Expanded metadata camera and library fixture acceptance

Status: Focused acceptance expansion complete on 2026-09-09; the overall
dependency integration gate remains open.

- [x] Verify GoPro Hero9/Hero12, DJI Action4 MP4 and Sony FX6 MXF exporter
  parity alongside the Sony A1 control: all twelve isolated executions pass.
- [x] Stage original local image/sidecar/CRM/MXF fixtures without changing
  source originals or upstream assertions, except recorded path relocation.
- [x] Exercise the original twenty skipped cases against candidate and clean
  baseline: both report fourteen passed, five missing and one failed.
- [x] Preserve the newly exposed JXL fixture/assertion disagreement as a failure;
  add seven harness acceptance/rejection regressions and reproducible evidence.
- [x] Recheck upstream release availability; no reviewed newer release found.

Five cases still need the exact ARW/XMP originals. The JXL disagreement requires
upstream reconciliation, broader native RTMD acceptance is still relevant, and
the production pin remains unchanged. See
`docs/METADATA_LIBRARY_FIXTURE_VALIDATION.md` and
`docs/METADATA_REAL_MEDIA_VALIDATION.md`.

## Integrated continuation verification — 2026-09-09

All **479 Release tests pass with zero failures and zero skips**, including
both original ITU reference sets, in 115.263 seconds (115.468 including suite
overhead). Release static analysis and all 61 release-preflight checks pass.
The fresh programme runner also completes its own build/test, nine independent
LRA-calculator checks, eleven true-peak-calculator checks, and all three
programme comparisons. The metadata fixture harness's seven regression checks
pass; its preserved upstream JXL failure is a separate dependency gate.

Native rebuilt-app acceptance confirms the iXML/BWF inspector sections and
successful 29.97 CSV/FCPXML export of the unchanged eight-finding fixture.
Saved bytes preserve exact DF boundary positions, inclusive durations,
classifications, Unicode and full source URLs; original file/sidecar hashes
remain unchanged. Actual editor round trips and spoken assistive-technology
acceptance remain open.

Artifacts: `/tmp/aagedal-continuation-full-20260909.xcresult`, corresponding
build/full/analyze logs, `/tmp/aagedal-programme-complete-20260909`, and
`/tmp/aagedal-fcpxml-20260909-final`. These temporary outputs supplement the
committed scripts, tests and documented reproduction steps.

## Phase 66 — Bounded UTF-16 iXML recording labels

Status: Engineering complete on 2026-09-09. All 47 WAVE reader tests pass in
the 503-test Release suite; static analysis and 61 release-preflight checks pass.

- [x] Read little- and big-endian UTF-16 iXML with a BOM, plus explicit
  UTF-16LE/UTF-16BE declarations without one.
- [x] Reject conflicting declarations, odd byte lengths, invalid surrogates,
  NUL characters, and encoded DTD/entity declarations without losing technical
  audio or Broadcast WAVE metadata.
- [x] Retain the encoded payload cap and decoded field, depth, and element caps;
  cover Unicode, CDATA, both byte orders, and malformed/bounded inputs.

Acceptance scope: direct recording labels only. Native UTF-16 acceptance,
authentic recorder fixtures, nested iXML timing/track objects, and other
encodings remain separately tracked in `docs/WAVE_METADATA.md`.

## Phase 67 — Deliberate historical review timebase migration

Status: Engineering complete on 2026-09-09. All 18 migration regression tests
pass in the 503-test Release suite. Native preview/cancellation was exercised;
final save/reopen and corrected-sheet layout acceptance remain open.

- [x] Preview recognized historical decimal broadcast rates against the loaded
  sources' exact rational rates, including per-note frame/range/time changes.
- [x] Preserve recorded A/B frames, inclusive A endpoints, finding identity,
  text, classifications and source identities; recompute changed-source seconds.
- [x] Save and adopt a new sidecar through exclusive publication, retaining the
  original and refusing stale reviews, changed sources, and existing destinations.
- [x] Reopen a same-pair review copy explicitly, with subsequent edits and
  exports using the displayed active sidecar.
- [x] Compare persisted note representations so JSON timestamp precision cannot
  falsely report that a just-saved review changed before preview.
- [x] Add regression coverage for rate limits, ranges, lifecycle, conflicts,
  source replacement, copy reopening and restored editor exports.
- [x] Configure report save-panel content types and visible extensions before
  assigning the filename to address the native doubled EDL extension.
- [x] Add a historical-rate option to the reusable interchange fixture generator.
- [x] Inspect the native eight-finding migration preview and cancel without
  changing original hashes or creating a copy; fix the discovered collapsed
  preview scroll area and truncated explanations.

Acceptance scope: this corrects stored timebases while retaining frame indexes;
it cannot recover a different intended frame after historical capture rounding.
Copy selection is explicit in each new session. Native migration acceptance and
actual editor round trips remain separate from automated exporter checks. See
`docs/COMPARE_REVIEW_SIDECAR.md` and
`docs/COMPARE_REVIEW_MIGRATION_NATIVE_CHECK_2026-09-09.md`.

## Integrated Phase 66–67 verification — 2026-09-09

All **503 Release tests pass with zero failures**, with both original ITU
reference sets enabled, in 115.063 seconds (115.336 including suite overhead).
Release static analysis and all 61 release-preflight checks pass. A final
view-only migration-sheet layout correction then passed a fresh Release build
and static analysis. The 23.976 historical fixture generator also completed;
all eight stored note rates/seconds and manifest values were checked.

The Mac locked before the final native recheck. Native migration save/reopen,
the corrected dialog layout/default EDL filename, and UTF-16 inspector acceptance
are therefore still open. The existing Resolve fixture was exported as eight
EDL events and its source was imported into a disposable Resolve 21.1 project;
actual marker import/re-export was not completed. See the native migration
record above and `docs/COMPARE_MODE_INTERCHANGE.md` for exact evidence/limits.

## Phase 68 — Bounded iXML recording track labels

Status: Engineering complete on 2026-09-09. The first integrated run passes
all 510 Release tests, including 53 WAVE reader tests and both original ITU
reference sets. Final combined verification is recorded below.

- [x] Read optional direct `TRACK_LIST` track names and explicit one-based
  source-channel/file-interleave indexes, without inferring routing or timing.
- [x] Preserve optional fields and producer document order; validate declared
  counts and reject ambiguous duplicate indexes/fields without losing recording,
  technical audio or Broadcast WAVE metadata.
- [x] Bound track lists to 256 entries within the existing payload, field,
  nesting and element limits; cover both UTF-16 byte orders and Unicode.
- [x] Show the producer track labels/indexes in the inspector and copied JSON,
  with backward-compatible decoding of metadata without a track list.

Focused native UTF-16LE/UTF-16BE inspector acceptance passes, including Unicode
track labels/indexes, unchanged stereo audio metadata and separate BWF values.
Producer-authentic recorder and wider assistive-technology acceptance remain.
Timing, speaker roles, track routing, vendor functions and ADM remain outside
this implementation. See `docs/WAVE_METADATA.md`.

## Phase 69 — Review transition persistence and native migration acceptance

Status: Implementation complete on 2026-09-09; final combined verification
is recorded below.

- [x] Recheck both sources' timing after a migration save completes, keeping
  the original review active if metadata changed while publication was pending.
- [x] Flush pending note-text drafts before copy opening, migration, relinking
  and report export; wait for persistence and reject failed or stale transitions.
- [x] Lock editing while an action awaits saving; retain failed edits/deletions
  across error dismissal and unrelated successful writes, retry them before the
  next action, and clear completed drafts before they can mask newer note text.
- [x] Add delayed-store regressions for A/B timing updates during migration,
  successful/failed draft saves, and primary replacement during an action.
- [x] Verify the corrected native migration sheet's scroll area and explanations.
- [x] Save/adopt the native eight-note migration copy, preserving original
  source/sidecar hashes and exact note identities, frames and inclusive ranges.
- [x] Verify the default EDL filename has one extension and saves eight events.
- [x] Reopen the source pair, confirm original-sidecar selection, then explicitly
  reopen the migrated copy and confirm its active path and eight findings.
- [x] In the final rebuilt app, edit an existing note without Return and export
  CSV; verify the active copy and eight-row report preserve the new text while
  original media/sidecar hashes remain unchanged.

The native migration checks precede the subsequent draft-transition fix; the
native pending-edit CSV check uses the final build. Broader keyboard/VoiceOver,
native failure/retry and actual editor round-trip acceptance remain distinct.
See `docs/COMPARE_REVIEW_MIGRATION_NATIVE_CHECK_2026-09-09.md`.

## Integrated Phase 68–69 verification — 2026-09-09

All **513 Release tests pass with zero failures**, including both original ITU
reference sets, in 114.991 seconds (115.250 including suite overhead). Release
static analysis and all 61 release-preflight checks pass. Independent review
rechecked pending-action locking, failed-mutation retry and stale draft cleanup.

Focused native acceptance now covers migration layout/save/adoption/copy reopening,
the default EDL extension and eight-event output, UTF-16LE/BE recording and track
labels, and pending note text reaching both the active copy and CSV export.
Original review/media hashes stay unchanged; test edits affect only the migrated
copy. The Resolve automation call stalled, and actual editor marker round trips
remain open. Temporary evidence includes `/tmp/aagedal-review-final-full-20260909.xcresult`,
its build/full/analyze logs, and `/tmp/aagedal-tracks-migration-preflight-20260909.log`.

## Phase 70 — Review failure/retry regressions and JXL gate diagnosis

Status: Complete on 2026-09-10 within the focused scope below. All 515 Release
tests, static analysis and 61 release-preflight checks pass.

- [x] Exercise a migration destination collision through the controller, preserving
  the active review and both existing files before a successful new-destination retry.
- [x] Exercise corrupt copy reopening, retained original editing after failure,
  repaired-copy reopening, and subsequent writes isolated to the active copy.
- [x] Verify native corrupt-copy error/repaired-copy reopening and isolated
  subsequent editing, with original file hashes unchanged.
- [x] Verify native migration publication conflict, preserved existing destination,
  fresh-destination retry and correct active-copy adoption with all eight findings.
- [x] Diagnose the upstream JXL fixture disagreement with the original container
  and its genuine extracted codestream, without altering upstream assertions.
- [x] Require seven identical baseline/candidate write/preservation/orientation
  results and unchanged fixture/checkout hashes; add four evidence regressions.

All 13 focused migration-controller tests pass. Both isolated Release JXL
probes pass all seven checks, and all eleven JXL/fixture-harness regressions pass.
The JXL throw expectation is obsolete even for the actual bare codestream;
substituting the correct fixture alone cannot reconcile the upstream test.
The production dependency pin remains unchanged. See
`docs/METADATA_LIBRARY_FIXTURE_VALIDATION.md` for the reproducible diagnostic
and remaining integration gates.

The integrated suite passes 515 tests with zero failures and zero skips,
including both official ITU reference sets, in 117.247 seconds (117.494 with
suite overhead). Release static analysis and 61 release-preflight checks pass.
Native corruption/conflict alerts and both retries pass in the rebuilt app;
all original media/sidecar hashes remain unchanged. See
`docs/COMPARE_REVIEW_MIGRATION_NATIVE_CHECK_2026-09-09.md` for reproduction,
evidence and the distinction from broader keyboard/VoiceOver or disk-full checks.

## Phase 71 — Explicit review save recovery

Status: Complete on 2026-09-10 within the scope below. All 521 Release tests,
static analysis and 61 release-preflight checks pass.

- [x] Offer Retry Save for failed review edits/deletions, committing current
  text drafts before retrying and suppressing duplicate retry actions.
- [x] Chain retained failed edits behind freshly queued draft saves during the
  same action, without duplicating writes or looping on persistent errors.
- [x] Refuse review reload while unsaved mutations remain, preserving the
  displayed edits and active review through repeated write failures.
- [x] Cover injected permission-denied and disk-full errors at store/controller
  boundaries, including revision recovery, edits/deletions and successful retry.
- [x] Exercise the production atomic writer against a real read-only disposable
  directory, preserve sidecar/media bytes and directory contents, then restore
  permissions and retry successfully.
- [x] Cover the same permission failure/retry through exclusive migration and
  relink publication, preserving the original files and reviewed proposal.

The permission test changes only its own temporary directory and restores its
permissions during cleanup. Disk-full coverage injects errors; it does not fill
a volume. Native Retry Save layout/keyboard/VoiceOver acceptance and actual
volume-exhaustion behavior remain separate checks.

The integrated suite passes 521 tests with zero failures and zero skips,
including both original ITU reference sets, in 116.610 seconds (116.848 with
suite overhead). All three real directory-permission failures and subsequent
retries pass in the Release app-hosted XCTest bundle. An independent review
identified the queued-draft retry edge case above; the final queue cleanup and
generation handling were re-reviewed after correction. Evidence:
`/tmp/aagedal-save-recovery-full-20260910.xcresult`, its `.log`, and the matching
`aagedal-save-recovery-analyze-20260910.log` and
`aagedal-save-recovery-preflight-20260910.log` in `/tmp`.

## Phase 72 — Review save lifecycle and real filesystem recovery

Status: Complete on 2026-09-10 within the scope below. All 524 Release tests,
static analysis and 61 release-preflight checks pass.

- [x] Reject every queued note write after comparison stop/replacement, including
  unretained intermediate tasks waiting behind an already-started save.
- [x] Add deterministic three-save regressions for both stop and source-B reload.
  Both fail with the old guard: the middle write starts and replaces the saved
  text. Both pass with the generation check before store entry.
- [x] Add a bounded, opt-in real disk-full test for production atomic save/delete
  failures, unchanged original bytes/media, no partial files, and revision recovery.
- [x] Provide an owned 32 MiB HFS+ image harness with strict path/device/capacity
  checks, bounded filler, retained evidence, full-suite support and cleanup.
  Missing/skipped coverage cannot count as success.
- [x] Verify native permission-denied note creation and deletion, retained error
  and edits across popover reopening, Retry Save recovery, and active-copy isolation.
- [x] Confirm the enlarged native popover shows the wrapped error and Retry Save
  action, with original media/sidecar hashes and directory permissions preserved.

The native check is recorded in
`docs/COMPARE_REVIEW_SAVE_RECOVERY_NATIVE_CHECK_2026-09-10.md`. It combines
keyboard text/file selection and accessibility actions; complete keyboard and
spoken VoiceOver acceptance remain. The disk-image test establishes bounded
HFS+ production-store behavior, not APFS or native disk-full interaction.
An already-started write may finish after comparison invalidation, but its
completion cannot mutate the replacement UI; queued writes never begin.

The integrated suite passes **524 tests with zero failures and zero skips**,
including the real disk-image test and both original ITU reference sets, in
114.710 seconds (114.957 including suite overhead). The image reaches zero
available blocks, preserves the existing sidecar through save/delete failures,
then passes both retries after the owned filler is truncated and synchronized.
The harness verifies execution proof and exits successfully after detaching
and removing its image. POSIX canonical-path checks handle macOS's `/tmp`
alias without relaxing the mount safeguards; fixed timestamps avoid JSON date
precision affecting document equality.

Evidence: `/tmp/aagedal-review-recovery-verified-20260910/Tests.xcresult`,
its `run.log`, `tests.json`, volume/environment records and successful cleanup
status; `/tmp/aagedal-review-queue-analyze-20260910.log` and
`/tmp/aagedal-review-recovery-preflight-final-20260910.log`.

## Phase 73 — Bounded UTF-32 iXML recording metadata

Status: Complete on 2026-09-10 within the scope below. All 528 Release tests,
static analysis and 61 release-preflight checks pass.

- [x] Read UTF-32LE/BE recording labels and explicit track indexes/names in
  RIFF/RF64/BW64 without changing audio routing or technical metadata.
- [x] Detect four-byte signatures before overlapping UTF-16 BOMs and require
  matching encoding declarations, with explicit byte order when no BOM exists.
- [x] Reject incomplete code units, invalid scalars, conflicting declarations,
  malformed XML and encoded DTD/entities; preserve existing payload/field/tree caps.
- [x] Work around Darwin XMLParser's inconsistent UTF-32 support through strict
  decoding and bounded UTF-8 transcoding, changing only the validated encoding name.
- [x] Add Unicode/CDATA/JSON/container, invalid-input and boundary regressions;
  independently review the conversion and security checks.

See `docs/WAVE_METADATA.md` for the supported encoding contract. Authentic
recorder files and spoken VoiceOver remain separate acceptance work.

## Phase 74 — Real APFS review save recovery

Status: Complete on 2026-09-10 within the scope below. Focused APFS/HFS+ and
the integrated 528-test Release suite pass, with static analysis and all 61
release-preflight checks.

- [x] Extend the opt-in harness to a disposable 128 MiB APFS image, preserving
  fixed filesystem-specific capacity/write caps and the default 32 MiB HFS+ path.
- [x] Validate filesystem, canonical mount, device, capacity and per-run token
  before filling; require both successful tests and completion proof.
- [x] Verify actual APFS out-of-space save/delete errors, unchanged source and
  sidecar bytes, no partial files, valid-revision recovery and successful retries.
- [x] Recheck HFS+ with the same test bundle and verify both images are detached
  and removed. Enable Release testability in direct harness builds.

Both focused runs pass with zero failures or skips. APFS may report reserved
free blocks despite returning ENOSPC; the test requires real errors rather than
zero reported blocks. Native disk-full popover/alert interaction remains open.
See `docs/COMPARE_REVIEW_APFS_DISK_FULL_CHECK_2026-09-10.md`.

## Integrated Phase 73–74 verification — 2026-09-10

All **528 Release tests pass with zero failures and zero skips**, including
all 57 WAVE reader tests, both official ITU reference sets, and the real APFS
exhaustion test, in 117.054 seconds (117.310 including suite overhead).
Release static analysis and all 61 release-preflight checks pass. The APFS
harness verifies its completion proof, detaches the image and removes the
fixture. Separate focused HFS+ and APFS runs also pass.

Final review tightened declaration recognition so similarly named processing
instructions cannot replace XML declarations, and uses byte-based whitespace
checks to preserve valid CRLF declarations in UTF-16/UTF-32. Native app access
stalled before UTF-32 fixture opening; no native inspector acceptance is claimed.
An earlier integrated run was interrupted by static analysis replacing the
shared test product; the final passing run used no concurrent build actions.

Evidence: `/private/tmp/aagedal-player-integrated-final-20260910/Tests.xcresult`,
its `run.log`, `tests.json`, environment/volume records and successful cleanup
status; `/tmp/aagedal-utf32-final-build.log`,
`/tmp/aagedal-utf32-analyze-final.log`, and
`/tmp/aagedal-utf32-preflight-final.log`.

## Remaining work after this continuation

- Integrate the measured metadata-memory dependency fix after upstream review,
  broader camera/format acceptance, and remaining fixture coverage, then
  repeat full-app profiling. Synthetic
  containers, selected real Sony/raw media, and the candidate library suite now
  pass. The September 9 fixture expansion exercises the original twenty skips:
  fourteen pass, five still lack their exact ARW/XMP originals, and one JXL
  expectation fails identically in baseline/candidate and needs reconciliation.
  Phase 70 proves successful byte-preserving writes with its genuine bare
  codestream too; both the mislabeled fixture and obsolete throw assertion
  need upstream reconciliation.
  All 50 upstream CLI
  tests now pass without skips; nine validator regressions require complete
  pinned-suite evidence. The
  isolated candidate reduces the eight-hour peak from about 4.3 GiB to 20 MiB;
  production still uses the original dependency. September 8 adds a longer Sony
  clip, ProRes RAW HQ, ARRIRAW, and X-OCN LT parity; no newer upstream release
  is available. September 9 adds GoPro/DJI/Sony FX6 exporter parity. See Phases
  46 and 65.

- Native timeline zoom/hover, comparison review, relinking, channel/loudness controls,
  and loupe pointer/Full Keyboard Access/VoiceOver acceptance. A focused native
  timeline check now confirms zoom, overview adjustment without seeking,
  frame-step reveal, and Fit in single-source and comparison views. The September 7
  extension also verifies pointer scrubbing, paused overview panning, fullscreen
  seeking, and primary-replacement Fit reset. The wider
  pointer and assistive-technology matrix remains open. Phase 42 also verifies
  native channel-routing summaries and loudness metric labels; spoken narration,
  and keyboard traversal remain open. The September 7 check verifies concurrent
  jobs, independent cancellation/completion, and inspector hide/reopen cleanup;
  wider playback and assistive-technology acceptance remains open.
  A focused native review check now covers note creation, filtering, and CSV
  export of a filtered-out finding. Phase 54 adds keyboard inclusive-range entry,
  distinct expanded labels, and successful explicit native relinking with
  unchanged findings/original sidecar. Phase 58 adds native cancellation and
  a write-time destination-conflict check with unchanged bytes. Phase 61 adds
  native keyboard-only comparison opening, review-note creation, CSV export
  and compact wipe adjustment, plus focus ownership/scrolling fixes. Complete
  keyboard review, spoken VoiceOver, and broader narrow-layout acceptance remain.
- Actual marker import/re-export in Resolve, Final Cut Pro, and Avid, including
  fractional rates, drop-frame boundaries, inclusive ranges, and source identity.
- Oldest-supported Apple Silicon UHD/HDR playback, reflected loupe/scopes,
  and long-file thumbnail performance profiling.
- Release signing/notarization/update-feed validation, representative-media
  smoke tests, refreshed screenshots/demo, publication, and hands-on editor beta.
- Complete Full Keyboard Access and spoken VoiceOver checks for the revised
  native 7.1 correction text. Phase 52 verifies native text wrapping,
  accessibility-tree content, measurement activation, and Command-I reopening.
  The diagnosed rear-weight discrepancy is corrected in Phase 51; unknown or
  other layouts do not receive that correction.
- Broader WAVE format support: compressed encodings, RIFX extensible/BWF variants,
  legacy iXML encodings, further structures and ADM interpretation remain outside the
  bounded reader. Phases 62 and 66 add bounded UTF-8 and UTF-16 iXML recording labels;
  Phase 68 adds bounded track names/indexes and native UTF-16 inspector checks;
  Phase 73 adds bounded UTF-32LE/BE recording labels and tracks;
  native UTF-32 inspector and producer-authentic recorder acceptance remain. Phase 59 adds
  classic RIFX metadata and corrected offline analysis/waveforms; RIFX playback
  and trim export remain explicitly unavailable pending a verified decoder fix.
  Phase 54 verifies
  RIFF/RF64/BW64 metadata and corrected 7.1 loudness. Phase 56 adds bounded
  Broadcast WAVE recording tags; native validation is recorded with that phase.
- Peak/true-peak meters and live momentary/short-term loudness,
  calibration/ballistics/presets, programme LRA/true-peak and broader transient
  reference accuracy, and representative multichannel profiling. Phase 55 adds
  three original ITU programme integrated-loudness references. Phase 57 adds
  a separately prepared official eight-channel gain reference. Phase 60 adds
  an independent PCM LRA comparison for the authentic ITU programmes; published
  EBU programme LRA targets remain open. Phase 64 adds an independent true-peak
  FIR comparison for those three original programmes; published programme
  true-peak targets and broader authentic coverage remain open.
  Selected absolute-level,
  gating, and true-peak numerical references are covered by Phase 45; Phase 47
  adds synthetic LRA and calibration at 44.1/48/96 kHz. Phase 48 adds independent
  front/side/LFE references for 2.1, 3.0, 5.1(side), and part of 7.1. Phase 51
  adds corrected 7.1 references across all conventional speakers and three rates.
  Phase 52 adds 12 analytical transient true-peak references at those rates;
  Phase 53 adds 18 cases across two further pulse families and stereo placement.
- Verified 1:1 source-pixel inspection, whole-viewport zoom/pan after loupe
  acceptance, and time-localized mismatch markers after a detection model is
  defined. See `PRODUCT_ROADMAP.md` for milestone sequencing.
- Broader keyboard/VoiceOver acceptance of historical review migration and copy
  reopening, plus broader disk-full/permission-denied save-failure acceptance.
  Phase 71 adds explicit Retry Save, real filesystem permission-denied recovery
  coverage and injected disk-full regressions. Phase 72 adds native permission
  failure/retry for note creation and deletion plus actual bounded HFS+ exhaustion
  coverage. Phase 74 adds actual bounded APFS exhaustion and recovery, plus
  an HFS+ recheck. Complete keyboard/VoiceOver and native disk-full interaction
  remain open.
  Phase 70 completes native corrupt-copy and migration-destination-conflict
  errors and successful retries with original-file preservation. Phase 69 completes
  focused native preview layout, save/adoption, copy reopening and EDL naming;
  a pending text edit also reaches the migrated copy and CSV in the final build;
  Phase 63 continues to preserve historical coordinates during ordinary loading.

## Delivery order

1. Phase 10 correctness fixes and regression tests.
2. Phase 11 task isolation and off-main-actor rerendering.
3. Phase 11 bounded PCM aggregation and profiling.
4. Phase 12 operation ownership.
5. Phase 13 update-state improvements and incremental cleanup.
6. Phase 14 AVFoundation audio-track routing correctness.
7. Phase 15 track-discovery and selection lifecycle isolation.
8. Phase 16 playback-observer lifecycle isolation.
9. Phase 17 MPV-publisher lifecycle isolation.
10. Phase 18 scope-capture lifecycle isolation.
11. Phase 19 metadata-inspector analysis isolation.
12. Phase 20 update-request coalescing.
13. Phase 21 auxiliary-waveform startup ownership.
14. Phase 22 queued playback-timer isolation.
15. Phase 23 dropped-file load ownership.
16. Phase 24 deferred UI-work ownership.
17. Phase 25 media-operation feedback ownership.
18. Phase 26 SwiftMediaMetadata 3.0.0 migration.
19. Phase 27 playback-preparation ownership.
20. Phase 28 metadata-copy feedback ownership.
21. Phase 29 AVFoundation frame-boundary seek precision.
22. Phase 30 reflected QuickTime playback orientation.
23. Phase 31 AVFoundation live-loupe frame acquisition.
24. Phase 32 MPV native surface sizing.

25. Phase 33 structured comparison reviews.

26. Phase 34 review-sidecar relinking and export consistency.

27. Phase 35 timeline viewport and report provenance.

28. Phase 36 bounded timeline thumbnails.
29. Phase 37 review report coordinate integrity.

30. Phase 38 thumbnail and editor-marker source integrity.

31. Phase 39 primary drawable ownership across comparison transitions.

32. Phase 40 selected-range loudness analysis.
33. Phase 41 long-file thumbnail profiling.
34. Phase 42 audio QC edge cases and accessible monitoring controls.

35. Phase 43 stable MPV drawable sizing during playback.
36. Phase 44 multichannel loudness profiling.

37. Phase 45 native loudness cancellation and numerical references.
38. Phase 46 metadata memory diagnosis and candidate dependency fix.
39. Phase 47 loudness range references across sample rates.
40. Phase 48 independent channel-layout loudness references.
41. Phase 49 native review feedback and accessible finding identity.

42. Phase 50 broader true-peak references and 7.1 measurement qualification.

43. Phase 51 corrected conventional 7.1 loudness weighting.

44. Phase 52 transient true-peak references and native loudness layout.

45. Phase 53 bounded WAVE metadata and broader transient references.

46. Phase 54 large WAVE containers and contextual review controls.

47. Phase 55 original ITU programme loudness references.

48. Phase 56 Broadcast WAVE recording metadata.
49. Phase 57 official eight-channel loudness evidence.
50. Phase 58 narrow comparison controls and native relink edge cases.

51. Phase 59 big-endian WAVE metadata and safe offline decoding.
52. Phase 60 independent programme LRA comparison.
53. Phase 61 comparison toolbar keyboard ownership and focus visibility.
54. Phase 62 bounded iXML recording labels.
55. Phase 63 exact frame rates from decimal metadata.
56. Phase 64 independent authentic-programme true-peak comparison.
57. Phase 65 expanded metadata camera and library fixture acceptance.
58. Phase 66 bounded UTF-16 iXML recording labels.
59. Phase 67 deliberate historical review timebase migration.
60. Phase 68 bounded iXML recording track labels.
61. Phase 69 review transition persistence and native migration acceptance.

62. Phase 70 review failure/retry regressions and JXL gate diagnosis.
63. Phase 71 explicit review save recovery.
64. Phase 72 review save lifecycle and real filesystem recovery.

65. Phase 73 bounded UTF-32 iXML recording metadata.
66. Phase 74 real APFS review save recovery.
