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
a roughly 2.3 GiB transient parent resident-memory spike. That gate remained open
at this phase and was closed by the 3.0.1 integration in Phase 98. See
`docs/AUDIO_LOUDNESS_PERFORMANCE.md`.

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
- [x] Add an opt-in production `MetadataService` profiler that observes memory
  before the uncached load, verifies cached-result parity and caller release,
  and validates fresh-process artifacts for each supplied long input.
- [x] Integrate the reviewed 3.0.1 dependency release and repeat production-path
  long-input memory profiling (completed in Phase 98).
- [ ] Complete remaining fixture recovery, JXL expectation reconciliation, and
  broader camera/container error-semantics coverage.

Acceptance: the source of the memory spike, the candidate fix and its 3.0.1
production integration are established. The payload-copy memory gate is closed;
the distinct metadata compatibility gate remains open. See
`docs/METADATA_MEMORY_PERFORMANCE.md`.

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

Status: Focused acceptance expansion complete on 2026-09-09; Phase 98 later
closed dependency integration while the compatibility gate remains open.

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
upstream reconciliation and broader native RTMD acceptance is still relevant.
The production pin was unchanged during this phase and was updated in Phase 98. See
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
The production dependency pin remained unchanged during this diagnostic and was
updated in Phase 98. See
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

## Phase 75 — Native UTF-32 inspector acceptance

Status: Complete on 2026-09-10 within the focused synthetic scope below.

- [x] Open UTF-32LE and UTF-32BE recording fixtures in the Phase 73 Release app
  through its native file picker and inspect the Unicode labels and track indexes.
- [x] Verify readable labels/indexes and producer-value explanation by native
  scrolling/screenshots, with complete values in the accessibility tree.
- [x] Confirm unchanged stereo PCM16/48 kHz/two-second metadata and Left/Right
  waveform labels, with no source-byte changes.
- [x] Retain a deterministic, collision-refusing fixture generator and confirm
  its output is byte-identical to the native fixtures.

See `docs/WAVE_METADATA.md` for build, exact observations, hashes and reproduction.
This closes the stalled native UTF-32 inspector check, not producer-authentic
recorder, BOM-less native, Full Keyboard Access or spoken VoiceOver acceptance.
No app code changed; the existing 528-test integrated baseline remains the
app verification evidence. The fixture generator was run and its hashes checked.

The programme-reference follow-up also rechecked primary EBU/ITU documentation
and the official EBU v5 download. The archive still returns HTTP 403; original
programme LRA bytes remain unavailable. Published programme true-peak targets
remain a separate gap. `docs/AUDIO_PROGRAMME_REFERENCES.md` now records precise
acceptance prerequisites without treating independent calculations as published
targets.

## Phase 76 — Native APFS disk-full edit and deletion recovery

Status: Complete on 2026-09-10 within the focused native scope below.

- [x] Add a reusable disposable 128 MiB APFS native fixture harness with
  canonical-root, image/device/volume/token/capacity and descriptor safeguards.
- [x] Observe actual native edit failure, error retention across popover
  reopening, failure on retry while full, and successful retry after release.
- [x] Observe actual native deletion failure and successful retry after release,
  preserving the exact recovered sidecar bytes until retry succeeds.
- [x] Verify source bytes, finding identity/coordinates/classification and
  document fields, plus absence of partial files; retain original/recovered/
  deleted sidecar evidence outside the volume.
- [x] Detach and remove the owned disk image after closing test media.
- [x] Pass 17 focused harness safety/proof tests and all 61 release-preflight
  checks; independently review the harness safeguards and verification.

See `docs/COMPARE_REVIEW_NATIVE_DISK_FULL_CHECK_2026-09-10.md` for exact native
observations, reproduction, evidence and limits. No app code changed; no new
full-suite run is claimed. Complete Full Keyboard Access/spoken VoiceOver,
broader narrow-window layouts and native disk-full copy/relink/migration flows
remain separate acceptance work.

## Phase 77 — Bounded RIFX iXML metadata

Status: Complete on 2026-09-10 within the bounded scope below. All 530 Release
tests, static analysis and 61 release-preflight checks pass.

- [x] Read optional recording labels and explicit track indexes/names in classic
  RIFX using the existing bounded XML reader, with container and XML byte order
  handled independently.
- [x] Cover all five supported UTF encodings, metadata after audio, duplicate,
  malformed and hostile payloads, the exact payload cap and invalid chunk lengths.
- [x] Keep RIFX BWF/extensible and playback/export restrictions intact; independently
  review the parser change and tests.
- [x] Extend the deterministic UTF-32 fixture generator with a RIFX option,
  preserving default RIFF bytes; verify chunk/format endianness, XML and hashes.
- [x] Pass the integrated Release suite, static analysis and release preflight.

See `docs/WAVE_METADATA.md` for reproduction and limits. Producer-authentic
RIFX and native RIFX iXML inspector acceptance remain open. Native app inspection
stalled during this continuation, so no additional native acceptance is claimed.

The separate metadata dependency check reconfirmed all 50 CLI tests with no
failures or skips and all nine validator regressions. This was a fresh offline
Release run against pinned sources; production dependencies remain unchanged.
See `docs/METADATA_REAL_MEDIA_VALIDATION.md` for evidence and remaining gates.

The first integrated app run passed 529 tests but was not accepted: Xcode
reported that the host exited with code 0 before completing
`testAVFoundationPairAlignsBySourceTimecodeAndSharesTransport`. That unchanged
test then passed in isolation in 10.285 seconds. All 59 WAVE tests passed in
the first run, and the APFS harness detached/removed its fixture. The interrupted
run and isolated result are retained at `/tmp/aagedal-rifx-ixml-integrated-20260910`
and `/tmp/aagedal-rifx-av-isolated-20260910.xcresult`; the host exit remains
unexplained and is not counted as a passing run.

The fresh complete rerun passes **530 Release tests with zero failures and zero
skips**, including all 59 WAVE tests, both original ITU reference sets and actual
APFS exhaustion/recovery, in 115.313 seconds (115.550 including suite overhead).
The harness verified its completion proof, detached the volume and removed the
image. Evidence: `/tmp/aagedal-rifx-ixml-integrated-final-20260910/Tests.xcresult`,
its `run.log`, `tests.json`, environment/volume records and successful cleanup
status. The build and 61-check preflight logs are
`/tmp/aagedal-rifx-ixml-build-20260910.log` and
`/tmp/aagedal-rifx-ixml-preflight-20260910.log`. Release static analysis passes;
its log is `/tmp/aagedal-rifx-ixml-analyze-20260910.log`.

## Phase 78 — Classic RIFX Broadcast WAVE interoperability

Status: Complete on 2026-09-11 within the bounded scope below. All 534 Release
tests, static analysis and 61 release-preflight checks pass.

- [x] Extend bounded `bext` reading to classic RIFX using libsndfile's
  container-endian convention, preserving low/high DWORD time-reference order.
- [x] Cover recording-field parity, version gates, signed/sentinel loudness,
  malformed/duplicate chunks, iXML coexistence and sparse 1 GiB history bounds.
- [x] Independently review the parser against primary libsndfile source.
- [x] Verify library-produced fixture interoperability and the integrated Release
  suite, static analysis and release preflight.

Actual libsndfile 1.2.2 output confirms the time-reference word order and all
fixed recording/loudness fields. A 772-byte committed fixture is read by a
normal regression test; a header-backed generator and independent byte checks
retain reproducibility without adding a production dependency.

The integrated run passes **534 tests with zero failures and zero skips**,
including all 63 WAVE tests, both official ITU reference sets and actual APFS
exhaustion/recovery, in 115.446 seconds (115.700 including suite overhead).
The harness verifies its completion proof, detaches the volume and removes
its fixture. Evidence: `/tmp/aagedal-rifx-bwf-integrated-20260911/Tests.xcresult`,
`run.log`, `tests.json`, `summary.json`, environment/volume records and
successful cleanup status. Final build, analysis, preflight and fixture
reproduction logs are `/tmp/aagedal-rifx-bwf-build-final-20260911.log`,
`/tmp/aagedal-rifx-bwf-analyze-20260911.log`,
`/tmp/aagedal-rifx-bwf-preflight-20260911.log` and
`/tmp/aagedal-rifx-bwf-fixture-20260911.log`.

RIFX extensible formats and playback/export remain unsupported. This is a
bounded interoperability extension; producer-authentic recorder and native
RIFX inspector acceptance remain open. The native iXML attempt on September 11
could not reliably enter the fixture path in the file picker, so it supplies
no additional native acceptance evidence.

## Phase 79 — Native inspector correctness and review publication recovery

Status: Complete on 2026-09-11 within the focused scope below. All 535 Release
tests, static analysis and 61 release-preflight checks pass.

- [x] Verify native RIFX UTF-32LE/BE iXML recording labels and track indexes.
- [x] Verify native library-produced RIFX Broadcast WAVE fields and embedded
  loudness, with unchanged fixture hashes.
- [x] Extend real disk-full recovery coverage to exclusive relink and
  historical-timebase migration publication, including failed-output cleanup,
  original-byte preservation and same-proposal retries.
- [x] Pass the 534-test integrated Release suite on APFS with both official
  ITU reference sets; detach and remove the owned image.
- [x] Verify responsive playback failure layout beside the metadata inspector,
  preserving space for toolbar/transport and complete native video framing.
- [x] Verify native inspector-transition MPV refresh with playing/paused intent
  and the exact paused frame retained after reopening.
- [x] Pass single-source reload transport regressions for both backends,
  including superseded/stopped and explicit pause-during-reload coverage.
- [x] Pass final-build integrated HFS+ recovery, static analysis and preflight.

See `docs/WAVE_METADATA.md` and
`docs/COMPARE_REVIEW_PUBLICATION_DISK_FULL_CHECK_2026-09-11.md` for observations,
reproduction, evidence and acceptance limits. Native review publication
disk-full interaction and spoken VoiceOver remain separate work.
The responsive canvas, transport-clearance and inspector refresh check is
recorded in `docs/INSPECTOR_CANVAS_LAYOUT_CHECK_2026-09-11.md`.

Final Release evidence: `/tmp/aagedal-inspector-final-hfs-20260911/Tests.xcresult`
and adjacent logs/summary report 535 passes, no failures and no skips, including
both official ITU reference sets and all ten new transport regression outcomes.
The HFS+ harness verifies its completion proof, detaches and removes the image.
Build, analysis and preflight logs are `/tmp/aagedal-inspector-final-build-20260911.log`,
`/tmp/aagedal-inspector-final-analyze-20260911.log` and
`/tmp/aagedal-inspector-final-preflight-20260911.log`.

## Phase 80 — Comparison reload transport and position ownership

Status: Completed on 2026-09-11. Inspector-driven and explicit paired reloads
now retain playing/paused intent and the requested source-A position while the
decoders are preparing. This does not change the existing reload behavior of
returning shuttle/reverse playback to forward 1×.

- [x] Honor an explicit Pause during a comparison reload without cancelling
  the readiness work needed to finish source B's setup.
- [x] Retain intent and nonzero position across overlapping refreshes, including
  the interval where a newly constructed MPV decoder publishes a zero clock.
- [x] Bind readiness completion to both source preparation identities, so a
  superseded decoder cannot resume a replacement source.
- [x] Start comparison correction from requested playing intent; asynchronous
  backend playing notifications must not leave B paused after A resumes.
- [x] Finish readiness for paused pairs as well as playing pairs.
- [x] Distinguish a primary reload timeout from B's readiness failure, preserve
  a ready B, and invalidate late primary backend selection before reporting it.
- [x] Pass 24 real-decoder comparison cases across MPV/MPV, AVFoundation/AVFoundation
  and both mixed directions, plus 12 single-source cases. Cases cover paused,
  playing, Pause during reload, overlapping reloads, and superseded preparations.
- [x] Pass ten comparison lifecycle tests, including a suspended primary
  preparation completing after its reload timeout.

The focused Release run passes all 12 test methods in
`/tmp/aagedal-reload-ownership-second-tests-20260911.log`. The initial regression
run exposed a real asynchronous playing-state handoff failure; the final
implementation resumes both sources and verifies their clocks advance.
Native inspector geometry, EOF, Full Keyboard Access and spoken VoiceOver
acceptance are not implied by these decoder checks.

Integrated Release verification passes all 537 tests with zero failures and
zero skips, including both official ITU reference sets and real APFS review
save/publication recovery. Evidence: `/tmp/aagedal-reload-final-apfs-20260911/Tests.xcresult`
and adjacent `summary.json`, logs, completion proof and successful detach status.
Static analysis passes in `/tmp/aagedal-reload-analyze-20260911.log`; release
preflight passes all 61 checks in `/tmp/aagedal-reload-preflight-20260911.log`.

## Phase 81 — Live Audio QC measurement contract

Status: Design prerequisite completed on 2026-09-11. No meter implementation,
reference-accuracy, native accessibility or hardware acceptance is claimed.

- [x] Define decoded source-PCM provenance independently of monitor volume,
  mute/solo, A/B monitoring and downstream output gain.
- [x] Specify per-channel sample/true peak and aggregate Momentary/Short-term
  windows, units, calibration references, maxima and display ballistics.
- [x] Define EBU production and ATSC exchange presets as reference guides,
  including the current ATSC dialogue-assessment limitation; do not present
  full-mix live readings as compliance or full EBU Mode.
- [x] Specify pause, seek, loop, speed, reload, EOF, replacement and cancellation
  behavior, plus bounded worker/PCM ownership and explicit overrun failure.
- [x] Define numerical, real-source, lifecycle, release-floor performance and
  keyboard/VoiceOver evidence required before accepting the actual live path.

See `docs/LIVE_AUDIO_METER_DESIGN.md`. Official EBU R 128 v5, Tech 3341 v4,
ITU-R BS.1770-5 and ATSC A/85:2026-07 sources were checked for the contract;
product budgets and display choices are explicitly distinguished from standards.
This closes only the roadmap's design checkbox and leaves live meters open.

A separate attempt at native structured-review keyboard validation could not
proceed because app-control initialization stalled. No new native acceptance
is claimed. Multi-row offscreen traversal and complete classification/range
editing, filtering/navigation and export remain to be verified with the
keyboard, followed by Full Keyboard Access and spoken VoiceOver.

## Phase 82 — Programme loudness for split-mono deliverables

Status: Completed on 2026-09-11 in response to the request for overall LUFS
from files containing eight separate mono tracks. Native accessibility and
production-scale multitrack profiling remain separate acceptance work.

- [x] Add Programme Loudness above the individual audio-stream sections, with
  explicit Stereo or 5.1 speaker assignments and unassigned tracks excluded.
- [x] Measure the assembled multichannel signal rather than averaging track
  LUFS, downmixing or guessing a layout from silent tracks.
- [x] Preserve file-relative timing across delayed/shorter channels, with finite
  silence padding and exact Whole File/In–Out measurement provenance.
- [x] Cancel on mapping, scope, media or inspector lifecycle changes and reject
  stale completion; retain independent per-track jobs and retryable failures.
- [x] Include a separate programme result, ordered audio-track assignments and
  selected range in copied metadata JSON.
- [x] Validate numerical stereo/surround references, LFE and surround weighting,
  opposite polarity, loud/silent spare tracks, differing rates, delayed/shorter
  channels, malformed input, cancellation and real metadata/controller export.
- [x] Fix the discovered bundled-FFmpeg probing failure for valid negative-
  polarity 96 kHz float WAVE inputs using header-verified WAVE demuxer selection;
  retain the existing validated RIFX sample-decoder correction.

The focused run passes all 19 programme/controller/RIFX test methods in
`/tmp/aagedal-programme-focused-final-20260911.log`. A further end-to-end test
uses an actual MOV with video followed by eight mono audio tracks, the real
metadata loader, default controller mapping and exported JSON. It confirms
that the metadata library's audio-relative track indices remain correct with
a preceding video stream. See `docs/PROGRAMME_LOUDNESS.md` and
`docs/WAVE_METADATA.md`.

Final Release verification passes all 552 tests with zero failures and zero
skips, including both official ITU reference sets and real APFS review recovery.
The image completion proof and successful detach are retained beside
`/tmp/aagedal-programme-release-apfs-20260911/Tests.xcresult` and `summary.json`.
Build and static-analysis logs are `/tmp/aagedal-programme-release-build-20260911.log`
and `/tmp/aagedal-programme-release-analyze-20260911.log`. All 61 release-preflight
checks pass in `/tmp/aagedal-programme-preflight-20260911.log`.

## Phase 83 — Bounded live-meter calculation and display foundation

Status: Calculation, lifecycle and application integration implemented on
2026-09-12, with worker-side admission bounding added on 2026-09-13 and the
live-path acceptance work below still open. This does not complete Audio QC.

- [x] Add a serial source-PCM measurement core with explicit rate/speaker order,
  bounded 250 ms blocks, fixed filter history and sixty energy buckets.
- [x] Compute per-channel sample/4× reconstructed true peaks, ungated 400 ms
  Momentary and 3 s Short-term loudness, and independent segment maxima.
- [x] Publish source-sample peak/loudness endpoints separately, reject gaps,
  duplicate positions, malformed blocks and invalid PCM, and invalidate failed
  segments instead of concealing missing samples.
- [x] Drain EOF reconstruction without extending loudness windows or replacing
  the final valid peak with silence. Cover exact and partial publication buckets.
- [x] Add source-time peak decay/hold, final-peak revision, separate maxima,
  EBU/ATSC/custom reference guides and exact unrounded ceiling comparisons.
- [x] Cover calibration at all three initial sample rates, independent FFmpeg
  time-varying M/S comparisons, LFE/surround roles, polarity/intersample and
  signed above-full-scale transient peaks, block boundaries, reset and errors.
- [x] Add a bundled-FFmpeg source decoder with explicit stream identity and gain
  controls, versioned provenance, bounded Float32 framing, cancellation, EOF and
  actionable malformed/truncated-PCM failures.
- [x] Add reusable accessible meter presentation state and controls for A/B,
  peak/loudness readings, exact reference-guide wording, diagnostics and
  finite-value-validated persisted reference preferences.
- [x] Add a window-scoped lifecycle coordinator with monotonically changing
  generations, stale-result rejection, one-slot post-DSP UI coalescing,
  cancellation/retry/EOF ownership and clean discontinuity restart causes.
- [x] Pace source decoding at native 1× with catch-up capped at 1×, and preserve
  one decoder/DSP generation across pause and buffering through race-safe
  process suspension. Cancellation still terminates a stopped process.
- [x] Bind selected-track metadata to an immutable A/B meter source identity,
  retaining FFmpeg audio-stream order, exact source-sample start positions,
  explicit speaker maps and actionable unsupported-format failures.
- [x] Add typed player clock/transport/scrub/EOF and discontinuity events, plus
  coordinator restart, unsupported-speed and ±250 ms drift policies with
  200/100 ms ahead suspend/resume hysteresis.
- [x] Add the owning window session/subscriptions, source-readiness seam and
  active-player command routing. Start/retry/reset at the current player clock
  and tear down decoder work when the panel or player window closes.
- [x] Mount and connect the activating meter panel, including A/B selection,
  reference controls, clear/reset/retry actions and status diagnostics.
- [x] Enforce an exact worker-side PCM admission bound no more than 250 ms ahead
  of the playback clock, including pause/resume, cancellation wake-up and actual
  bundled-FFmpeg pipe backpressure.
- [x] Replace input-only seeking with bounded precise preroll and prove exact
  generated AAC, ALAC and MP4 AC-3 intervals without unexpected decoder gain.
- [ ] Validate the timestamp-verified decoder on representative real
  compressed sources.
- [ ] Complete real-path accuracy, routing invariance, spoken accessibility and
  release-floor performance.

The final combined Release run passes 578 tests with zero failures and zero skips,
including the official ITU offline references and real APFS recovery, with
verified image detach. Evidence is retained in
`/tmp/aagedal-meter-programme-final-apfs-20260912/Tests.xcresult` and `summary.json`.
That retained candidate passed all 61 preflight checks. A then-current preflight
inside the restricted workspace sandbox stopped at strict bundled-FFmpeg
code-signature verification. Phases 85–86 later established that this was a
sandbox trust-service limitation and verified the unchanged tracked FFmpeg
outside the sandbox. Those later checks do not establish candidate evidence for
an unverified newer commit; the canonical post-commit verifier remains the
authoritative candidate gate.

The decoder/presentation/lifecycle continuation includes paced bundled-FFmpeg
decode, coordinator ownership, suspend/cancellation and panel-session coverage.
The mounted panel deliberately qualifies provenance until decode completion and
does not mark live metering as release accepted: representative compressed-source
and production-path acceptance remain open.
The integrated continuation passes the full 649-test Debug suite with no failures
and one expected opt-in real-volume-exhaustion skip.

See `docs/LIVE_AUDIO_METER_DSP.md`. A preliminary optimized standalone host
check processed ten seconds of eight-channel 96 kHz PCM in about 0.13 seconds;
this excludes decoder/UI costs and does not satisfy base-M1 acceptance.

## Phase 84 — Programme analysis teardown, profiling and long-range integrity

Status: Implemented on 2026-09-12, with remaining performance acceptance below.

- [x] Cancel programme analysis when its owning controller is released. The new
  regression fails before the fix and passes afterward, independently of SwiftUI
  inspector-disappearance callbacks.
- [x] Add an opt-in production profiler for eight mono tracks assembled as
  Stereo and 5.1, with whole/early/late intervals, source mapping, input hashes,
  measured readings and separately sampled parent/FFmpeg RSS.
- [x] Validate retained result structure and reject performance acceptance when
  system sleep occurs inside the profiling interval. Preserve interrupted
  diagnostics without presenting them as clean timing evidence.
- [x] Reproduce a long-range correctness fault in the shared-input graph: the
  eight-hour 5.1 last-30-second selection silently retained only FL, returning
  −21.1 LUFS instead of −13.4 LUFS despite successful process exit.
- [x] Give every assigned channel an independent demux input inside one
  cancellable FFmpeg process, retaining duration limits, header-derived input
  options, original timestamps, speaker order and existing interval behavior.
  The same eight-hour input now retains all six channels and the expected
  reading. Focused programme/controller/RIFX regressions pass.
- [x] Add a compact late-range 5.1 regression with initial silence, distinct
  FL/FR/FC/SL/SR energy, an LFE-only peak marker and louder unassigned tracks.
  It proves that every assigned role contributes through the production service
  without making routine tests decode an eight-hour PCM timeline.
- [ ] Complete representative deliverable and base-M1 performance acceptance.
  Independent one/eight-hour process checks reduce memory, but per-input
  container indexes still grow with source packet count. The first eight-hour
  production run was interrupted by lid-closed system sleep and is excluded
  from comparative timing. The compact regression covers late-range channel
  contribution and the argument regression locks independent demux inputs, but
  it does not recreate the packet-count scale trigger; hash-pinned before/after
  eight-hour process evidence is retained.

The corrected production one-hour run passes all six layout/scope workloads
and the new no-sleep acceptance check: 5.1 whole-file child RSS falls from
565.20 MiB to 125.89 MiB, and the late interval from 522.88 MiB to 121.83 MiB,
with expected readings retained. Evidence is in
`/tmp/aagedal-programme-profile-20260912-separate-1h`. These development-host
results do not close representative-media or base-M1 acceptance.

See `docs/PROGRAMME_LOUDNESS_PERFORMANCE.md` for measured results, recipes,
input hashes, sleep qualifications and the remaining acceptance boundaries.
Final verification passes all 578 Release tests with no failures or skips,
including both official ITU reference sets and real APFS recovery; the disposable
image detached successfully. Twelve programme/shared-validator and power-event
Python tests pass. Xcode static analysis and all 61 release-preflight checks pass.
Evidence:
`/tmp/aagedal-meter-programme-final-apfs-20260912/Tests.xcresult`, `summary.json`,
`/tmp/aagedal-meter-programme-analyze-20260912.log`, and
`/tmp/aagedal-meter-programme-final-preflight-20260912.log`.

The production metadata-memory dependency issue remains separate and unresolved.

## Phase 85 — Timestamp-verified live-meter transport

Status: Decoder protocol and focused regressions implemented on 2026-09-13;
representative real-media and production-path acceptance remain open.

- [x] Encode source PCM once and tee each FFmpeg packet to raw Float32 stdout
  plus a same-process `framecrc` timestamp record on stderr.
- [x] Require a `1/sampleRate` time base, declared sample rate, PTS/DTS within
  one millisecond of decoded continuity, exact frame/byte counts and matching
  Adler-32 before admitting PCM. Normalize only bounded container timestamp
  quantization; material gaps still fail closed.
- [x] Bound steady-state unmatched timestamp and PCM data to 250 ms so callback
  reordering applies pipe backpressure rather than playback-duration memory growth;
  termination releases waiters to reconcile the OS-bounded final pipe tail.
- [x] Drain the timestamp side channel before final stdout callbacks at process
  termination, and wake both sides on cancellation or framing failure.
- [x] Preserve exact generated AAC, ALAC and MP4 AC-3 seek/gain behavior, and
  prove that an actual compressed timestamp gap fails instead of concatenating
  discontinuous PCM.
- [ ] Validate representative real compressed sources and the complete mounted
  playback acceptance matrix, including routing, drift, accessibility and the
  release-floor performance run.

The focused timestamp processor, cross-pipe shutdown and compressed-gap regressions
pass. A reported extracted stream's eight-frame timestamp overlap now has an
exact regression and is normalized within the one-millisecond container-jitter
bound; retesting that source remains representative-media acceptance. The full
649-test Debug suite passes with the one expected opt-in real-volume-exhaustion
skip, and static analysis passes. The complete 61-check release preflight also
passes for 1.6.1 (163) outside the restricted workspace sandbox. Strict
verification there confirms the expected Developer ID team, Hardened Runtime,
and secure timestamp; the sandbox-only `invalid signature` result is not an
artifact failure.

## Phase 86 — Ordered meter clears and packaged-artifact verification

Status: Engineering complete on 2026-09-13; candidate distribution and
representative-media acceptance remain open.

- [x] Carry a monotonic Clear Maxima revision through the playback owner,
  worker gate, DSP and presentation reducer without restarting source-time
  loudness windows or peak ballistics.
- [x] Reject stale pre-clear numerical maxima while still accepting their
  current readings, and use worker-authored maxima after the clear so an
  in-flight or exact-bucket EOF snapshot cannot restore earlier peaks.
- [x] Cover clear ordering, stale callbacks, silent `-.infinity` maxima,
  subsequent rebasing and exact-bucket EOF with focused regressions.
- [x] Move final subprocess callback-barrier draining to a utility queue so
  timestamp-side-channel ordering no longer triggers priority-inversion
  diagnostics.
- [x] Re-extract the exact final distribution ZIP and require app preflight,
  stapler validation and Gatekeeper assessment before Sparkle signing or
  appcast publication.
- [x] Confirm all 61 source-tree release-preflight checks outside the restricted
  sandbox and distinguish its unavailable signing trust services from an
  actual tracked-binary defect.

The final optimized run passes 649 tests with one expected opt-in
real-volume-exhaustion skip (650 total), with no failures. Xcode static analysis
passes. Candidate archive, Developer ID signing, notarization, final ZIP
validation, representative smoke tests and publication have not been performed.

## Phase 87 — Reproducible candidate verification and mixed-backend pause ownership

Status: Engineering complete on 2026-09-13; optional inputs and distribution
acceptance remain explicit open gates.

- [x] Replace silent early returns in all six environment-dependent acceptance
  tests with descriptive `XCTSkip` results, so an ordinary green suite cannot
  be mistaken for having exercised external ITU media, production profiles or
  long-file thumbnail inputs.
- [x] Cover live-meter panel reuse, parent/child detachment, single close
  notification and decode-worker cancellation when the owning player closes.
- [x] Add one clean-checkout candidate verifier that records the source commit,
  `Package.resolved` hash, host and Xcode versions, then retains optimized
  Release test, static-analysis and preflight artifacts in a caller-selected
  directory.
- [x] Require both verification and release archives to honor only the versions
  in `Package.resolved`.
- [x] Keep the real mixed AVFoundation/MPV transport sample clear of fixture EOF,
  tolerate only bounded asynchronous state publication, and repeat exact paired
  alignment after both decoders acknowledge Pause.
- [x] Run the canonical verifier from a fresh DerivedData directory at commit
  `5ea936e8cc979c113e7084938a5fad1f2c58af13`: 645 tests pass and seven are
  explicitly skipped (652 total), Release static analysis succeeds, and all 61
  source-tree release-preflight checks pass for 1.6.1 (163).

Evidence is retained in `/tmp/aagedal-candidate-5ea936e`, including
`environment.txt`, `Tests.xcresult`, `tests.log`, `analyze.log` and
`preflight.log`. This closes repeatable candidate-checkout verification; it does
not claim that the six optional input families, real-volume APFS exhaustion,
representative-media smoke tests or final distribution have been accepted.

## Phase 88 — Live-meter source transitions and production-path integration

Status: Engineering complete on 2026-09-13; representative real-media and
native acceptance remain open.

- [x] Reapply the authoritative transport snapshot immediately after every
  seek, frame-step, scrub, loop-wrap or geometry-reload restart so a paused or
  buffering discontinuity cannot leave its replacement decoder running.
- [x] Use the secondary URL emitted by Combine when comparison source B changes,
  avoiding stale `@Published` `willSet` state during dynamic addition/removal.
- [x] Verify that selecting a distinct B stream restarts measurement exactly
  once, monitoring A/B selection, volume, mute and channel routing do not alter
  the measured source, and removing B cancels it and falls back to A.
- [x] Exercise the shipping metadata, player, window-session, bundled FFmpeg,
  DSP and presentation path with generated compressed ALAC 5.1, proving all six
  source channels and decoder provenance remain independent of monitor routing.
- [x] Expose shown/hidden and selected state for the compact Comparison Controls
  and Comparison Review toolbar toggles.
- [ ] Repeat live-meter correctness, drift, cancellation and accessibility
  acceptance with representative real programme material on the release-floor
  Mac.

The combined session/coordinator/production-path batch passes 23 focused tests.
The generated compressed case uses the typed player-completion boundary instead
of a one-second wall-clock playback race, so concurrent DSP load cannot make the
test confuse host starvation with a source-integration failure. The full Debug
suite passes 648 tests with seven explicit optional-input skips (655 total), and
Xcode static analysis passes.

## Phase 89 — Live-meter replacement recovery ownership

Status: Focused lifecycle hardening implemented on 2026-09-13; representative
real-media and native acceptance remain open.

- [x] Prevent Retry and Reset from reviving the coordinator's retained old URL
  or audio-stream request while replacement metadata and track selection are
  unresolved.
- [x] Cover a primary-media replacement followed by immediate Retry/Reset,
  proving no request starts until the new source-readiness revision arrives.
- [x] Cover an unsupported selected-track replacement followed by Retry/Reset,
  then prove selecting a later supported track starts only that stream.

All six `LiveAudioMeterSessionTests` pass in a focused Debug run. This closes a
stale-request lifecycle defect found during local contract auditing; it does
not validate representative compressed media, playback drift, release-floor
performance, keyboard operation, or spoken VoiceOver.

## Phase 90 — Distinct live-meter accessibility identity

Status: Automated semantics hardening implemented on 2026-09-13; spoken
VoiceOver acceptance remains open.

- [x] Include the channel identity in every sample-peak and true-peak
  accessibility label so multichannel rows no longer expose repeated,
  ambiguous names such as only “Sample peak” or “True peak”.

This improves the mounted meter's accessibility tree without claiming the
remaining keyboard traversal or spoken VoiceOver release gate.

The combined continuation passes the full Debug suite with 653 tests passed,
seven explicit optional-input skips, and no failures (660 total). A subsequent
focused invariant run adds the guarded unavailable-selection regression; the
fast release-helper gate passes 99 Python validator tests plus the mocked
comparison-profiler matrix. A clean-checkout optimized Release verifier remains
the candidate gate after these changes are committed.

## Phase 91 — Direct review entry and current candidate evidence

Status: Focused keyboard workflow implemented on 2026-09-13; broader native
accessibility acceptance remains open.

- [x] Add typed active-window Review commands that reveal Comparison Review and
  focus either the new-note draft or note filter.
- [x] Preserve the existing popover toggle and previous/next finding commands.
- [x] Cover the typed focus payload with a focused six-test Debug suite and a
  full application compile.
- [x] Confirm in a native MPV/MPV comparison that `Command-Option-N` and
  `Command-Option-F` focus their named text fields.
- [x] Run the canonical optimized verifier on exact code commit
  `43abae5cad3261f484dad239c54cb4cc9ea78e44`: 655 tests pass with seven
  explicit skips (662 total), static analysis and all 61 preflight checks pass,
  and the fast helper gate passes 99 Python cases plus the mocked comparison
  profiler matrix.

The retained candidate evidence is in
`/tmp/aagedal-candidate-43abae5-20260913-retry`. The first full run encountered
two intermittent MPV integration-test failures: one test runner exited cleanly
before executing a loupe test, and one transport assertion timed out. Both tests
passed in a sequential isolation run and the fresh canonical retry passed the
complete suite. Repeatability remains part of the final-candidate gate. The
native check establishes direct field focus, not complete Full Keyboard Access
or spoken VoiceOver acceptance.

## Integrated continuation verification — 2026-09-13

The live-meter decoder now runs at source-rate pace, preserves one controlled
decoder/DSP generation across pause and buffering, and binds exact selected A/B
audio-stream identity into source-sample-aligned decode requests. Player
controllers publish typed transport/discontinuity events and the coordinator
now applies tested clock drift, ahead hysteresis, restart and speed policies;
the owning window session, source-readiness seam, activating panel and
active-player command routing are now integrated. Worker-side PCM admission is
hard bounded to 250 ms beyond the playback clock. Bounded precise seeking also
preserves generated AAC, ALAC and AC-3 sample intervals and gain. Phase 85 now
verifies every PCM packet against its same-process timestamp, size and
checksum. Phase 88 verifies the complete shipping path on generated compressed
ALAC 5.1, including six-channel peaks, provenance, paused discontinuities and
A/B monitoring independence; representative real-source validation remains.
The new production-path metadata profiler observes RSS before the first uncached load,
checks cache parity and caller release, and validates one fresh XCTest host per
input; its 61-second ALAC end-to-end run validates the harness, not the long-file
memory gate.

The metadata harnesses now also accept an exact candidate checkout plus a
required full lowercase commit SHA, fail closed when provenance differs, and
retain the existing patch-validation mode. This makes a future reviewed
upstream revision reproducible without changing the shipping dependency; no
reviewed public candidate is currently available to pin. Direct active-window
Review commands now toggle Comparison Review and navigate previous/next matching
notes without toolbar traversal. They do not replace native Full Keyboard Access
or spoken VoiceOver acceptance.

The September 13 canonical clean-checkout run at
`3fdba621bb731aab234350df842e63fa0b4f405d` passes 654 Release tests with seven
explicit skips (661 total): six inputs are opt-in and the bounded real-volume
exhaustion check also remains opt-in. Release static analysis passes. New focused
Phase 85–87 regressions also pass without Thread Performance Checker warnings.
All 61 release-preflight checks pass outside the restricted workspace sandbox,
including strict verification of the bundled FFmpeg signature. The verifier
records the exact commit and resolved-package hash and retains the result bundle
and logs; release archives now use the same resolved-package constraint.
Candidate archive, signing, notarization, packaging, and distribution acceptance
remain open.

## Phase 92 — Live-meter EOF ownership and review accessibility hooks

Status: Focused engineering complete on 2026-09-13; full native accessibility
and representative-media acceptance remain open.

- [x] Latch playback EOF until the active source decoder finishes draining so
  trailing pause or buffering publications cannot suspend valid PCM or FIR-tail
  completion.
- [x] Treat decoder EOF as terminal for live readings when a selected audio
  stream ends before its containing video, preserving the final snapshot,
  provenance and clean drift state while the visual clock continues.
- [x] Reset EOF ownership on a new measurement generation or invalidation and
  cover both EOF orderings with deterministic coordinator regressions.
- [x] Add stable accessibility identifiers across comparison-review entry,
  filtering, navigation, note editing, classifications, range controls and
  export/copy menus.
- [x] Expose the complete active-sidecar path and explicit frequently-updated
  loading, export and error status semantics while hiding decorative status
  imagery from the accessibility tree.

All 19 focused live-meter coordinator tests pass, including the two new EOF
regressions. A Debug application build and the 11 focused Review command and
navigation tests pass. These hooks make repeatable native automation more
practical; they do not claim Full Keyboard Access or spoken VoiceOver acceptance.

## Phase 93 — Fail-closed candidate evidence and publication identity

Status: Release-tool engineering complete on 2026-09-13. The optimized verifier
is the authoritative post-commit candidate gate; final distribution remains a
separate signed/notarized release operation.

- [x] Export machine-readable XCTest summary/detail evidence and reject
  failures, expected failures, runtime warnings, a drop below the recorded test
  floor, non-descriptive skips and skips outside the seven named opt-in cases.
- [x] Keep the broad suite process-isolated while moving the two historically
  order-sensitive mixed-backend transport tests into a separately retained,
  fresh serial result bundle that must pass both directions.
- [x] Refuse candidate evidence inside the source checkout and recheck HEAD,
  `Package.resolved` and checkout cleanliness after verification.
- [x] Require release execution to consume both validated result bundles from
  a completed candidate matching the exact source commit and package hash.
- [x] Require release version/build arguments to equal committed Xcode project
  metadata instead of allowing an artifact to diverge from its source.
- [x] Fail closed when GitHub CLI is unavailable, verify an existing release's
  commit and draft state before replacing an asset, and require the exact ZIP
  to exist before changing the tracked appcast.

The fast helper gate passes 112 Python cases plus the mocked comparison-profiler
matrix. The new split was exercised in Debug: the 662-test aggregate passes
with 655 passed, seven named skips, no failures or runtime warnings, and both
excluded mixed-backend transport tests pass together in a fresh serial runner.
An intentionally attempted one-host serial run reproduced resource/order
failures in both transport directions, confirming that whole-suite serialization
is not a valid stabilization strategy. Candidate evidence is valid only when the
optimized Release verifier completes against the exact clean commit being shipped.

## Phase 94 — Decoded speaker identity and stale speed recovery

Status: Focused engineering complete on 2026-09-13; representative-media and
spoken accessibility acceptance remain open.

- [x] Require FFmpeg's frame-timestamp stream to declare its decoded channel
  layout before accepting PCM, with exact identity for supported weighted
  layouts and matching channel-count qualification for unknown layouts.
- [x] Reject missing, unrecognized, count-mismatched, and semantically
  contradictory layouts instead of trusting source metadata alone.
- [x] Keep explicit nonstandard one/two-channel maps on numbered peak-only
  meters, while retaining conventional mono/stereo fallback only when layout
  metadata is absent.
- [x] Prevent returning from unsupported playback speed from reviving the old
  retained URL or stream after source/audio-track replacement.
- [x] Expose stable native-automation identities for live-meter controls,
  status, provenance, actions, and dynamic readings; mark changing values as
  frequently updated.

All 60 focused decoder, playback-source, coordinator, session, and generated
compressed production-path tests pass in Debug. The real bundled FFmpeg path
now proves stereo, `5.1(side)`, and `7.1` layout headers. This does not replace
representative programme, release-floor, Full Keyboard Access, or spoken
VoiceOver acceptance.

## Phase 95 — Candidate-result and publication integrity

Status: Release-helper engineering complete on 2026-09-13; a final signed and
notarized distribution has not been produced.

- [x] Reconcile every detailed XCTest case and status with the candidate
  summary instead of validating only skip details.
- [x] Require exactly the two named mixed-backend transport tests in their
  isolated result bundle and reject unknown result states.
- [x] Reject draft or prerelease GitHub releases from stable appcast
  publication and verify the uploaded asset's state, name, byte size, and
  GitHub-computed SHA-256 against the local ZIP.
- [x] Validate configured Homebrew tap cleanliness before publication, recheck
  it before editing, and require exactly one version and checksum declaration.
- [x] Add self-contained regression coverage for result reconciliation,
  release-asset validation, and exact cask rewriting.

The focused helper suites and shell syntax checks pass. Final candidate
verification and the signed/notarized distribution gate remain post-commit
work against the exact source identity.

## Phase 96 — HDR scope safety and waveform source integrity

Status: Focused engineering complete on 2026-09-15; representative visual and
release-floor acceptance remain open.

- [x] Reject malformed RGB scope storage, non-finite pixels, invalid output
  dimensions, allocation overflow, and non-finite or implausible HDR peak scales
  before rendering or publishing a new graticule.
- [x] Cover RGBY parade placement and PQ, HLG, and linear HDR transfer behavior
  with deterministic raw-buffer regressions.
- [x] Give auxiliary waveform work a complete source identity across URL, mode,
  stream selection, layout, split-mono ordering/labels, and duration so same-file
  metadata changes replace stale generation instead of being deduplicated.
- [x] Reject invalid duration and source parameters before floating-point to
  integer conversion in the UI and native waveform generator.

All 29 focused waveform and scope tests pass, including five waveform-source
and nine new scope/HDR regressions. This is deterministic correctness and crash
resistance evidence; it does not replace the representative raster/color/loupe
matrix or base-M1 performance gate.

## Phase 97 — Representative live-meter evidence harness

Status: Harness engineering complete on 2026-09-15; authentic-media, trusted-
reference, soak, native accessibility, and base-M1 acceptance remain open.

- [x] Add an explicit opt-in production-path profile for external media with
  exact path/hash identity and selected codec, layout, stream, sample-rate, and
  playback-backend evidence.
- [x] Retain paced source-frame progress, publication cadence, clock drift,
  decoded-ahead high-water, app/child RSS, monitor-routing invariance, and
  bounded FFmpeg cancellation evidence.
- [x] Exercise a second near-EOF segment and require authoritative final DSP
  state plus exact frame-CRC timestamp interval and disabled decoder processing.
- [x] Let a cold production decoder catch up from bounded initial process
  startup latency before enforcing the steady-state 250 ms freshness limit.
- [x] Preserve the single first-packet AAC priming offset exposed by common
  edit lists as explicit timestamp-authorized source silence while continuing
  to reject genuine initial delays and midstream timestamp gaps.
- [x] Export durable XCTest attachments and fail closed on missing, duplicated,
  mutated, malformed, incomplete, unsupported, or unbounded evidence.
- [x] Keep the profiler named and skipped in ordinary candidate runs, document
  the authentic-media matrix and limitations, and include its self-contained
  validator regressions in the release-helper gate.

The harness makes the remaining production acceptance repeatable and auditable.
A 30-second generated video/AAC engineering smoke passes MPV playback, the
bundled FFmpeg/DSP path, monitor-routing mutation and resume, bounded
cancellation, and exact near-EOF drainage with the final schema. This proves
that the plumbing runs, but only the
documented producer-authentic matrix, trusted reference comparison, long-play
observation, and base 2020 M1 MacBook Air run can close the release gate.

## Phase 98 — SwiftMediaMetadata 3.0.1 production memory integration

Status: Completed on 2026-09-15. Broader authentic-media and release-floor
acceptance remains part of the candidate matrix, not the resolved payload-copy
defect.

- [x] Raise the package minimum and exact resolution to SwiftMediaMetadata 3.0.1
  at release commit `8662054299a3e13c49c65f74c564360559d1bf7f`.
- [x] Confirm package resolution selects 3.0.1 without a local dependency patch.
- [x] Run the shipping `MetadataService` path in fresh Release XCTest hosts for
  duration-correct one-hour and eight-hour six-channel ALAC regression containers.
- [x] Verify exact cache parity and source duration/size while retaining sampled
  and process-lifetime peak RSS evidence.
- [x] Confirm lifetime peak growth stays in the few-MiB startup-variance range
  rather than scaling with the 290 MB and 2.32 GB sparse-payload inputs.
- [x] Pass the dependency's Release suite with 1,668 passes, 48 named
  external-fixture/opt-in skips, and no failures; pass all 84 focused app
  metadata regressions with no skips, failures, expected failures, or runtime
  warnings.
- [x] Pass all 27 synthetic RTMD/container cases in both the 3.0.0 baseline and
  exact 3.0.1 release: 54 isolated executions with no mismatches or errors and
  complete source/fixture provenance.
- [x] Revalidate the exact 3.0.1 release against twelve unchanged
  producer-authentic Sony/raw/action-camera inputs. All exporter results match
  3.0.0, including complete parity for both Sony A1 RTMD/IMU controls up to
  5,568 frames and 222,720 samples per motion stream.

The specific multi-gigabyte top-level `mdat` copy is no longer a production
release blocker. The inputs deliberately use sparse enlarged payload declarations,
so producer-authentic long-memory workloads, base-M1 execution and longer-running
combined workloads remain separate acceptance items. See
`docs/METADATA_MEMORY_PERFORMANCE.md`.

## Phase 99 — Deferred playback-window publication

Status: Completed on 2026-09-15.

- [x] Defer the owning-window callback until after SwiftUI's representable update.
- [x] Coalesce repeated mount/update callbacks and deliver each newly observed
  replacement window once.
- [x] Pass eight coordinator tests, three window-manager tests, the closing/
  re-registration lifecycle check and a hosted app-command smoke without the
  previous SwiftUI publish-during-update warning.
- [x] Recheck the production metadata profiler and confirm the warning is absent.

Acceptance: window publication no longer mutates observable coordinator state
during SwiftUI view reconciliation, while first and replacement windows retain
their registration behavior.

## Phase 100 — Live-meter asynchronous test synchronization

Status: Completed on 2026-09-15.

- [x] Replace scheduler-yield-count polling in the controlled live-meter decoder
  and coordinator assertions with monotonic two-second deadlines and short
  suspensions.
- [x] Reproduce the full-suite-only attachment timeout from the failed canonical
  run and retain its exact XCTest diagnostics.
- [x] Pass the formerly failing malformed-snapshot/cancellation Release test in
  all twenty repeated executions.

Acceptance: coordinator tests wait for asynchronous task attachment, publication
and cancellation by elapsed time rather than assuming a fixed number of scheduler
turns under parallel suite load.

## Phase 101 — Malformed compressed live-meter gap ownership

Status: Generated-media engineering regression complete on 2026-09-15.

- [x] Pass generated compressed AAC through MetadataService, PlayerController,
  LiveAudioMeterSession and the bundled FFmpeg/DSP path with a timestamp gap.
- [x] Clear the last measured snapshot and provenance, surface an actionable
  Unavailable reason, and retain Retry after the malformed packet sequence.
- [x] Pass three focused Debug regressions for the full ownership path.
- [ ] Repeat on producer-authentic malformed media with trusted measurement
  comparisons and the release-floor long-play profile.

Acceptance: the generated-path regression is closed; authentic malformed-media
and performance acceptance remain release gates.

## Phase 102 — Offline clean-checkout candidate verification

Status: Completed for exact commit `d3b7030` on 2026-09-15.

- [x] Fail closed on any absent, mismatched or dirty pinned package checkout in
  the opt-in offline cache before using it in the isolated candidate verifier.
- [x] Pass the complete script-validator gate, 678 optimized Release tests with
  eight named skips, two isolated mixed-backend transport tests, static analysis
  and all 61 source-tree preflight checks.
- [x] Recheck HEAD, Package.resolved and package checkouts and retain the exact
  `.xcresult`, log and environment identity evidence outside the source tree.

Acceptance: the verifier records `status=passed` for the exact clean checkout
at `/private/tmp/aagedal-improvement-candidate-offline-20260915`. A later
candidate needs its own exact-HEAD run before release execution.

## Phase 103 — Resolve marker round-trip acceptance

Status: Partial editor result recorded on 2026-09-15; acceptance remains open.

- [x] Export the unchanged generated eight-finding 29.97 drop-frame review
  through native Save panels and verify exact EDL/CSV bytes and input hashes.
- [x] Import via Resolve Studio 21.1.0.14's timeline-marker EDL workflow and
  retain built-in marker API and native re-export evidence.
- [ ] Repeat in a fresh correct-start timeline to isolate the adjacent-frame
  collision; preserve all findings or document an explicit format limitation.
- [ ] Complete Final Cut Pro and Avid import/re-export acceptance separately.

The corrected-start Resolve import retained six of eight in-range findings:
five surviving anchors and both three-frame durations were exact, while an
adjacent finding moved one frame early and first/duplicate-frame findings were
lost. Seven negative markers from a first wrong-start import also remained in
the disposable project. See `docs/COMPARE_MODE_INTERCHANGE.md`; this phase
cannot count as accepted interoperability or a completed 2.0 gate.

## Phase 104 — Resolve same-frame export integrity

Status: Completed on 2026-09-19; editor acceptance remains separate.

- [x] Reject Resolve EDL exports with multiple findings at one source-A start
  frame, including a point/range collision, with a CSV/PDF recovery message.
- [x] Preserve all finding coordinates and content without merging or shifting
  notes; keep distinct adjacent and overlapping-range anchors exportable.
- [x] Document the limitation and the separate-copy workflow for the remaining
  adjacent-frame editor investigation.
- [x] Pass all 29 focused exporter regressions, including lossless CSV/PDF fallback.
  Final Debug evidence: `/tmp/aagedal-resolve-guard-20260919-final.xcresult`
  and the sibling `.log`; `git diff --check` also passes.

Acceptance: this closes the known silent same-frame export risk at the app
boundary. Phase 105 subsequently completes the focused correct-start Resolve
round trip. The wider Resolve matrix and Final Cut Pro/Avid acceptance remain open.

## Phase 105 — Repeatable Resolve round-trip comparison

Status: Validation tooling and focused seven-finding native round trip completed
on 2026-09-19; the wider editor acceptance matrix remains open.

- [x] Add a strict original/re-export EDL comparator with exact rational DF
  conversion, duration/content/color checks and duplicate multiplicity.
- [x] Retain input hashes and missing/unexpected records in a new JSON report;
  reject malformed records and never filter negative or extra editor events.
- [x] Reproduce the retained actual editor failure: eight expected findings,
  thirteen returned events, three missing exact records and eight unexpected.
- [x] Pass six focused regressions and the complete script-validator suite;
  evidence: `/tmp/aagedal-marker-validator-suite-20260919.log` and
  `/tmp/aagedal-resolve-retained-roundtrip-20260919.json`.
- [x] Prepare a fresh 29.97 DF Resolve timeline with the correct source start
  and a separate seven-finding diagnostic EDL omitting only Fixture 5.
- [x] Verify the user’s native import through the actual Resolve marker API:
  all seven positions, durations and exact texts match. Adjacent-frame
  displacement does not reproduce in the fresh correct-start timeline.
- [x] Complete native marker re-export and compare the returned EDL: all seven
  anchors, durations, colors and exact texts match, with no missing or extra
  events. Post-export media and original sidecar hashes remain unchanged.
- [x] Add the retained successful native round trip as a regression alongside
  the historical failure: all seven focused tests and the complete
  script-validator suite pass. Latest log:
  `/private/tmp/aagedal-roundtrip-validators-20260919.log`.

Acceptance: file comparison is now repeatable and checks the real retained
failure. The clean seven-finding native round trip passes without an exporter
coordinate change; complete editor compatibility still requires the remaining
rate/source-identity matrix. Native export and comparison evidence are retained
in `docs/evidence/resolve-markers-20260919`; same-frame findings remain rejected.

## Phase 106 — Current-source Resolve evidence and repeatable review copies

Status: Acceptance tooling and 59.94 DF fixture preparation completed on
2026-09-19; native editor acceptance remains open.

- [x] Add opt-in fixture provenance to the Resolve comparator: verify unchanged
  media/review hashes, exact fixture rate, selected review count, current sidecar
  source paths, and the appended A/B URLs in every original/returned marker.
- [x] Retain manifest and input hashes in successful evidence; reject changed
  files, stale URLs, moved fixtures, missing provenance and evidence overwrites.
- [x] Generate an explicit separate seven-finding Resolve review with only
  Fixture 5 omitted. Preserve the original eight-finding review and record the
  omitted ID and both review hashes, across all three existing fixture rates.
- [x] Pass 13 focused helper regressions and the complete script-validator suite
  (the suite run preceded the final additional CLI regression, which also passes).
  Suite log: `/private/tmp/aagedal-phase106-script-validators-20260919.log`.
- [x] Generate real 59.94 DF media and both review variants with bundled FFmpeg
  at `/private/tmp/aagedal-resolve-5994-20260919`; Foundation canonicalization
  and manifest publication complete successfully.
- [x] Export the selected copy through the app and complete a fresh correct-start
  59.94 DF native import/re-export with current editor media identity evidence
  (completed in Phase 107).

Acceptance: the next rate/source-provenance check is reproducible without manual
sidecar surgery. File verification does not establish that an editor loaded the
expected media, nor does generated fixture preparation close a round-trip gate.
See `docs/COMPARE_MODE_INTERCHANGE.md` for the workflow.

## Phase 107 — Native Resolve 59.94 DF import and media identity

Status: Native app export, editor import/re-export, and repeatable native-record
validation completed on 2026-09-19.

- [x] Open the prepared 59.94 DF pair through the app, preserve the eight-finding
  original, activate the seven-finding copy and export its EDL through native UI.
- [x] Create a fresh Resolve Studio 21.1.0.14 project/timeline with the correct
  59.94 DF rate and `00:00:58;00` start before the user's native marker import.
- [x] Verify all seven actual API marker anchors, one-/three-frame durations,
  colors and exact Unicode/classification/current-URL text, including first,
  adjacent, final, minute and ten-minute boundary frames.
- [x] Capture the actual V1 source path, source rate/start/frame count and full
  untrimmed timeline placement. Confirm unchanged media and both review hashes.
- [x] Add a read-only Lua snapshot helper and optional `--native-snapshot`
  validation requiring fixture provenance. Reject wrong media, timeline settings,
  clip trimming/shifts, marker loss/extras and altered text/duration/color.
- [x] Pass 17 focused helper tests and the complete script-validator suite;
  log: `/private/tmp/aagedal-phase107-script-validators-20260919.log`.
- [x] Compare the user's native marker re-export with the original EDL: all seven
  exact records pass with no missing/extra events. Retain both exports and the
  combined native/file-provenance report; post-export fixture hashes match.

Acceptance: current-source 59.94 DF native import/re-export passes. Evidence is
retained in `docs/evidence/resolve-markers-5994-20260919`; 23.976, same-frame
limitations and other editors are not silently treated as accepted.

## Phase 108 — Native Resolve 23.976 relative-time round trip

Status: Native app export, editor import/re-export and source identity verified
on 2026-09-19.

- [x] Generate exact `24000/1001` movies without embedded timecode, preserving
  the full eight-finding review and separate seven-finding unique-anchor copy.
- [x] Load the pair and selected copy through native app UI, export Resolve EDL,
  and verify all seven relative anchors/durations against the review, non-drop
  frame mode, exact rate provenance, current URLs and unchanged input hashes.
- [x] Create a separate Resolve Studio 21.1.0.14 project and zero-start 23.976
  timeline; capture actual source-A identity, 14,625-frame untrimmed placement
  and empty marker state before import.
- [x] Retain the native export, app binary identity, reviews, manifest and
  pre-import snapshot in `docs/evidence/resolve-markers-23976-20260919`.
- [x] Pass 18 focused Resolve helper regressions, including actual retained
  23.976 relative-time records and rejection of wrong start, rate and DF mode.
  The complete script-validator suite also passes; log:
  `/private/tmp/aagedal-phase108-roundtrip-script-validators-20260919.log`.
- [x] Verify the user's native marker import through a read-only snapshot: all
  seven anchors, durations, colors and exact texts match; current source-A
  identity and untrimmed placement pass, with unchanged input hashes.
- [x] Verify the user's native re-export: all seven exact EDL records pass,
  with no missing or extra events, matching native source identity and fresh
  unchanged fixture hashes. Retain the re-export and combined validation report;
  include the actual 23.976 round trip in the focused helper regressions.

Acceptance: current-source 23.976 relative-time native import/re-export passes.
Same-frame findings remain unsupported in Resolve EDL; other-editor acceptance
and the wider release gates remain separate. The retained README documents the
exact capture and comparison steps.

## Phase 109 — Native Final Cut marker loss and overlap export integrity

Status: Native failure reproduced and export guard verified on 2026-09-19;
Final Cut interoperability remains open.

- [x] Export all eight original 23.976 findings through the native app and
  validate against Final Cut’s bundled FCPXML 1.9 DTD.
- [x] Import into a disposable Final Cut Pro 12.3 library and re-export the
  event as FCPXML 1.14. Retain unchanged input/output and media/review hashes.
- [x] Identify three dropped findings inside inclusive ranges (eight in, five
  out), plus re-export whitespace normalization and defaulted clip raster.
- [x] Reject overlapping FCPXML marker intervals with an actionable CSV/PDF
  alternative. Preserve review content and allow adjacent disjoint intervals.
- [x] Pass focused exporter tests covering collisions, inclusive endpoints,
  nested ranges, preserved reports and non-overlapping adjacent markers.
- [ ] Resolve/qualify browser-clip raster, duration rounding and native
  re-export whitespace fidelity; repeat non-overlapping native round trips
  and the remaining Final Cut rate/source-timecode matrix.

Acceptance: the exporter no longer offers a known-lossy overlapping-marker
file as a successful export. This is an integrity safeguard, not successful
Final Cut interoperability. See
`docs/evidence/fcp-markers-23976-20260919/README.md`.

## Phase 110 — Final Cut one-frame markers and complete grouped findings

Status: Implemented and focused native round trip verified on 2026-09-19.

- [x] Replace overlap rejection with one-frame marker anchors; retain each
  inclusive range in note text and validate original range arithmetic.
- [x] Group same-frame findings deterministically with a count/title and
  individually labelled complete note/classification/source context.
- [x] Pass 31 exporter tests, including the retained eight-finding regression;
  optionally retain production-exporter fixture output without overwriting.
- [x] Import that unmodified output into a fresh Final Cut Pro 12.3 library and
  natively re-export. All eight findings survive in seven markers, with correct
  anchors and complete content subject to XML attribute whitespace normalization.
- [x] Verify unchanged original media/reviews and the imported source-A copy.
- [ ] Complete remaining FCP rate/raster/duration/whitespace acceptance and
  repeat native player UI export; rebuilt player showed a blank content view
  when loading the fixture, so this run used the production exporter in XCTest.

Acceptance: focused finding-loss fix passes; ranges remain textual and same-frame
findings share a marker. Exact tab/newline preservation is not claimed. See
`docs/evidence/fcp-grouped-markers-23976-20260919/README.md`.

## Phase 111 — Explicit Final Cut source raster

Status: Implemented; 33 focused exporter tests and DTD validation pass on 2026-09-19.

- [x] Carry source A's coded raster and valid pixel aspect ratio in the immutable
  export snapshot and emit FCPXML format width/height and paspH/paspV. The native
  Phase 109 re-export showed that frame duration alone defaulted the browser
  clip to 1280×720 despite the actual 160×90 source.
- [x] Omit incomplete/nonpositive raster pairs and invalid pixel aspect ratios;
  do not substitute display dimensions or invent source geometry.
- [x] Correct the optional retained-fixture exporter test's raster metadata to
  match the original 160×90 media rather than the test helper's 1920×1080 default.
- [x] Pass all 33 focused exporter regressions and validate the generated fixture
  against Final Cut's bundled FCPXML 1.9 DTD. Evidence:
  `/private/tmp/aagedal-phase111-tests-fixed.xcresult`,
  `/private/tmp/aagedal-phase111-tests-fixed.log`, and
  `/private/tmp/aagedal-phase111-raster.fcpxml`.
- [ ] Repeat native player UI export and Final Cut import/re-export to verify
  browser-clip raster, including portrait/anamorphic/rotated sources. Duration
  rounding, whitespace fidelity and the remaining rate matrix stay open.

Acceptance: source geometry is explicit in the export. Native raster preservation
is not established by exporter tests or DTD validation alone.

## Phase 112 — Native Final Cut raster and repeatable comparison

Status: Focused native raster acceptance and eight comparator regressions pass
on 2026-09-19; full Final Cut acceptance remains open.

- [x] Import the unchanged Phase 111 production-exporter fixture into a fresh
  Final Cut Pro 12.3 library and retain its native 1.14 re-export.
- [x] Verify 160 × 90 browser raster, exact rate/source start/NDF display, all
  seven anchors and eight findings, allowing only the documented XML attribute
  whitespace normalization for the separate content comparison.
- [x] Verify imported source-media bytes and unchanged original media/sidecars.
- [x] Add a repeatable rational-time/content/raster comparator to the script
  regression gate. Exact whitespace and duration differences return nonzero;
  absent media verification never implies source identity acceptance.
- [x] Diagnose the retained duration difference: the test snapshot's 610 seconds
  exports 14,626 frames, while the generated source and native result have 14,625.
- [ ] Repeat with accurate metadata through the native player UI and complete
  portrait/anamorphic/rotated sources, remaining rates and whitespace acceptance.

Evidence: `docs/evidence/fcp-raster-markers-23976-20260919/README.md`.
The raster result does not close duration, native player or wider editor gates.

## Phase 113 — Native Final Cut duration integrity

Status: Implemented and focused native round trip verified on 2026-09-19.

- [x] Repeat the eight-finding export through the native player UI with actual
  media metadata; reproduce 14,626 exported frames for the 14,625-frame source.
- [x] Prefer a positive metadata frame count that agrees within one frame of
  the playback-duration estimate, with a known video rate. Preserve the existing
  fallback for unavailable/invalid/disagreeing counts and the finding extent.
- [x] Rebuild and export through the player UI, then import into a new Final Cut
  Pro 12.3 library and retain the unmodified native re-export. Both durations now
  equal 14,625 frames; raster, rate, start, seven anchors and eight findings match.
- [x] Verify unchanged media/sidecar hashes and retain pre-fix/fixed/returned XML,
  source/build provenance, 35 passing exporter tests and nine Python regressions.
- [ ] Close exact note whitespace, other rates, portrait/anamorphic/rotated
  sources and the broader editor matrix. This single-source result does not
  establish VFR, keyboard-only or spoken accessibility acceptance.

Evidence: `docs/evidence/fcp-native-duration-23976-20260919/README.md`.
Final Cut's literal attribute whitespace remains the only comparator difference
for this case; its nonzero result is retained rather than waived.

## Phase 114 — Native Final Cut 59.94 drop-frame acceptance

Status: Focused native timing, geometry and finding preservation verified on 2026-09-19.

- [x] Export the original eight-note 59.94 DF review through the native player UI,
  import into a fresh Final Cut Pro 12.3 library, and retain its native re-export.
- [x] Verify 60000/1001 rate, 160 × 90 raster, square pixels, DF display, source
  start at 00:00:58;00, and exact 36,563-frame asset/browser duration.
- [x] Preserve seven anchors and all eight findings, including same-frame grouping,
  dropped-label/ten-minute boundaries and the final source frame.
- [x] Verify imported media bytes and unchanged original media/sidecar hashes;
  add retained-evidence regression checks against the original review texts.
  All ten Python comparator regressions pass.
- [ ] Close exact note whitespace, remaining rates, portrait/anamorphic/rotated
  sources and the broader editor/accessibility matrix.

Evidence: `docs/evidence/fcp-native-markers-5994-20260919/README.md`.
Only exact whitespace differs; the comparator still exits 1. This phase uses
the existing Phase 113 build and makes no new app implementation changes.

## Phase 115 — Final Cut asset-format verification and real geometry fixtures

Status: Focused production/exporter checks complete; native rotated anamorphic
format divergence recorded on 2026-09-19 and geometry acceptance remains open.

- [x] Exercise ten actual portrait, anamorphic, rotated and reflected fixtures
  through production metadata and FCPXML export, checking coded raster/PAR,
  exact rate, duration, media URL and first/adjacent/final frame markers.
- [x] Import the unchanged rotated anamorphic export in Final Cut Pro 12.3 and
  retain its native 1.14 re-export with verified identical source-media bytes.
- [x] Fix a comparator false positive: Final Cut keeps the browser-clip format
  but swaps the asset raster from 240 × 180 to 180 × 240. Independently compare
  asset raster, PAR and frame duration; the retained case now correctly exits 1.
- [x] Pass 36 focused Debug tests, twelve Python comparator regressions, the
  script-validator gate and DTD validation of all ten generated exports.
- [ ] Establish correct native display aspect and the appropriate treatment of
  editor-normalized rotated/anamorphic asset formats; complete the other native
  geometry cases and repeat through the player UI.

Evidence: `docs/evidence/fcp-rotated-anamorphic-20260919/README.md`.
The native test uses one source for both review sides and three plain point
findings. It does not close grouped/range/whitespace or broader editor gates.
No shipping app behavior changes in this phase.

## Phase 116 — Oriented Final Cut browser-clip geometry

Status: Quarter-turn export correction implemented on 2026-09-19; native
browser proportions improved, with asset-PAR interpretation still open.

- [x] Investigate Phase 115's rotated anamorphic display in Final Cut Pro 12.3.
  A diagnostic oriented format displays the expected portrait proportions.
- [x] Swap exported raster dimensions and invert pixel aspect ratio together
  for 90/270-degree source rotation, including negative/wrapped rotations.
- [x] Pass 37 focused Debug tests, including ten real geometry fixtures;
  thirteen Python comparator regressions, script validators, DTD checks and
  Xcode static analysis also pass.
- [x] Retain native diagnostic import/re-export and verify identical media
  bytes, all three point findings, timing and browser format. Production XML
  is structurally identical to the diagnostic apart from event/clip names.
- [ ] Resolve the remaining native asset-PAR rewrite (3:4 to 4:3), verify
  timeline conform/display geometry, and repeat through the rebuilt player UI.
  Complete the other native geometry cases before closing the broader gate.

Evidence: `docs/evidence/fcp-oriented-anamorphic-20260919/README.md`.
The strict comparator deliberately still exits 1 for `assetPixelAspect`.

## Phase 117 — Native Final Cut timeline and independent source geometry

Status: Focused native comparison and reusable event selection complete on
2026-09-19; calibrated geometry acceptance remains open.

- [x] Place the Phase 116 oriented diagnostic and an independently imported,
  byte-identical media copy in a new 1080 × 1920 / 24 fps native timeline.
- [x] Inspect default Fit/100% transform behaviour: both paths show the same
  portrait content with surrounding margins. Retain the unmodified event XML
  and verify both native asset media hashes against the original fixture.
- [x] Establish that both native assets share 180 × 240 / 4:3-pixel geometry;
  browser formats differ. Keep the strict asset-PAR mismatch visible.
- [x] Extend the comparator with explicit unique returned browser-clip selection
  for multi-clip events, preserving strict default behaviour and rejecting
  missing/ambiguous selections. Timeline markers cannot mask browser losses.
- [x] Pass 15 Python regressions including retained native timeline structure,
  and the complete script-validator suite.
- [ ] Measure rendered/timeline geometry, repeat through the rebuilt player UI,
  and complete remaining native geometry/editor cases before closing the gate.

Evidence: `docs/evidence/fcp-timeline-anamorphic-20260919/README.md`.
The observed matching padding suggests native source handling is involved; it
does not establish correct geometry or justify waiving `assetPixelAspect`.
No shipping app implementation changed in this phase.

## Phase 118 — Calibrated native Final Cut rendered geometry

Status: Native rendered-output measurement complete on 2026-09-19; incorrect
Fit padding confirmed and broader geometry acceptance remains open.

- [x] Export the complete Phase 117 portrait timeline through Final Cut Pro
  12.3 as 1080 × 1920 / 24 fps ProRes 422 and retain render/source hashes.
- [x] Measure three diagnostic review instances and the independent source
  import. All four sampled RGB frames are identical: correctly oriented 9:16
  content occupies 813 × 1444 pixels with black margins on all four sides.
- [x] Add a repeatable saturated-quadrant render diagnostic that distinguishes
  aspect/orientation from default Fit bounds, retaining threshold sensitivity,
  source render identity and decoder provenance. The native result exits 1.
- [x] Pass seven focused regressions and the complete script-validator suite;
  retain full-resolution review/reference PNGs and measurement JSON.
- [ ] Isolate native anamorphic conform behavior, repeat fresh production player
  UI export, and complete other geometry/editor cases. Do not waive the separate
  asset-PAR mismatch or compensate exporter scale without establishing cause.

Evidence: `docs/evidence/fcp-rendered-anamorphic-20260919/README.md`.
This closes the calibrated measurement task from Phase 117, not the geometry
acceptance gate. No shipping app implementation changed.

## Phase 119 — Native Final Cut conform isolation

Status: Four-control native render and diagnostic correction complete on
2026-09-19; rotated anamorphic Fit and asset-PAR acceptance remain open.

- [x] Render original rotated anamorphic, unrotated anamorphic, rotated
  square-pixel and baked square-pixel controls in one native portrait timeline.
  Preserve input/native XML, source hashes, measurements and decoded PNGs.
- [x] Confirm only the rotated anamorphic combination fails Fit in this matrix;
  the original still measures 813 × 1444 inside 1080 × 1920.
- [x] Correct axis-dependent aspect tolerance exposed by the wide control;
  record perpendicular pixel residuals and retain the independent Fit check.
- [x] Pass ten geometry regressions and the complete script-validator suite.
- [ ] Repeat fresh production UI export and broader native geometry cases;
  resolve Fit padding and asset PAR without speculative scale compensation.

Evidence: `docs/evidence/fcp-conform-isolation-20260919/README.md`.
Derived controls are diagnostic transcodes, not source-identity acceptance.
No shipping app behavior changed.

## Phase 120 — Fresh production UI Final Cut anamorphic export

Status: Rebuilt-player browser export/import/re-export repeat complete on
2026-09-19; native asset PAR and rendered Fit acceptance remain open.

- [x] Rebuild and relaunch the production Debug player, open the actual rotated
  anamorphic fixture in comparison, create a native review note and export XML.
- [x] Import the unmodified UI export into a separate Final Cut Pro 12.3 library
  and retain the native General/1.14 event re-export and production sidecar.
- [x] Verify browser raster/PAR, exact 48-frame duration, frame-zero finding
  text/timing and byte-identical native media. Strict asset-PAR comparison still
  fails (3:4 → 4:3); no waiver or scale compensation is introduced.
- [x] Pass sixteen round-trip regressions, the complete script-validator suite
  and FCPXML 1.9 DTD validation of the fresh UI export.
- [ ] Resolve native Fit padding and asset PAR; repeat rendered measurement
  through the fresh UI export and complete the broader native geometry matrix.

Evidence: `docs/evidence/fcp-production-ui-anamorphic-20260919/README.md`.
This closes the fresh UI browser round-trip repeat from Phases 116–119, not
rendered geometry acceptance. No shipping Swift implementation changed.

## Phase 121 — Fresh production UI native rendered geometry

Status: Fresh UI rendered-output repeat complete on 2026-09-19; Fit padding
and native asset-PAR acceptance remain open.

- [x] Place the Phase 120 production UI review in a native 1080 × 1920 / 24 fps
  project and export ProRes 422, retaining the unmodified native event XML.
- [x] Measure four frames across two complete timeline instances at three
  thresholds: all reproduce 813 × 1444 content and fail expected Fit bounds.
- [x] Verify exact browser finding text/timing, duration and unchanged source
  bytes; independently retain the asset-PAR mismatch (3:4 → 4:3).
- [x] Pass ten geometry and sixteen FCPXML diagnostic regressions.
- [ ] Establish an evidence-backed handling of native rotation/PAR conform,
  then complete broader native geometry acceptance.

Evidence: `docs/evidence/fcp-production-ui-render-20260919/README.md`.
This closes Phase 120's fresh-UI render-repeat task, not the geometry gate.
No shipping Swift implementation changed. Further identical Fit repeats are
not the next task; the unresolved native conform behavior needs a resolution.

## Phase 122 — Contain Final Cut rotated anamorphic conform failures

Status: Export restriction implemented and 39 focused Debug checks pass with
zero failures or skips on 2026-09-19.

- [x] Reject Final Cut XML for source A combining quarter-turn rotation and valid
  non-square PAR, including negative/wrapped angles and missing raster dimensions.
  Explain the known padding problem and recommend CSV/PDF to retain findings.
- [x] Keep square-pixel rotations, unrotated/180° anamorphic sources and source-B-only
  rotated anamorphic geometry outside the restriction. No media conversion,
  speculative scale adjustment or comparator waiver is introduced.
- [x] Update the real ten-fixture production-metadata/exporter matrix to expect the
  demonstrated failure to be rejected and verify that its findings survive CSV.
- [x] Verify 38 exporter regressions and the production ten-fixture geometry
  matrix (39 tests total). CSV/PDF text survives rejected exports; square-pixel
  rotations and source-B-only anamorphic geometry remain exportable.
- [ ] Resolve native conform behavior before lifting this restriction; complete
  broader native rotations/reflections and producer-authentic geometry acceptance.

The guard is based on Phases 118–121's retained native rendered evidence,
including identical padding from an independent source import. This is an
explicit unsupported export combination, not a fix to the native editor's
rendering. Historical XML and failing comparator evidence remain unchanged.
Verification: `/private/tmp/aagedal-phase122-final-tests.xcresult` and
`/private/tmp/aagedal-phase122-final-tests.log`; xcresult reports 39 passes,
zero skips/failures and no runtime warnings. The first executable test run
exposed missing video metadata in a new test helper invocation; correcting that
fixture setup produced the final passing run. No native UI/editor repeat,
whole-suite run or release-floor acceptance is claimed for this guard.

## Phase 123 — Native Final Cut whitespace re-import diagnosis

Status: Native second-generation round trip confirms formatting loss on
2026-09-20; export disclosure and retained-evidence regression implemented.

- [x] Inspect the original native import: tabs, newlines and grouped finding
  separation remain intact in Final Cut Pro 12.3's browser Notes column.
- [x] Re-import its unmodified XML into a new isolated library. Verify that
  native notes now replace those characters with spaces; retain another native
  XML export proving the spaces persist in the serialized marker attributes.
- [x] Compare both generations: original-to-second fails only exact note
  whitespace; first-to-second matches parsed content. Verify source media bytes
  and all four original fixture hashes remain unchanged.
- [x] Explain the limitation in the Final Cut export save panel with CSV/PDF
  guidance, textual ranges and same-frame grouping. Preserve correct XML
  escaping and strict comparator failure for formatting loss.
- [x] Add a regression against the retained native second-generation export;
  all 17 focused Python comparator tests and the full script-validator suite
  pass. The Debug app build succeeds. The save-panel copy is compile-verified;
  native player-panel and spoken accessibility checks remain separate.
- [ ] Resolve exact native whitespace round trips before claiming lossless
  editor interchange; broader editor and geometry acceptance remains open.

See [native whitespace evidence](docs/evidence/fcp-whitespace-reimport-20260920/README.md).

## Phase 124 — Current optimized candidate verification

Status: Canonical clean-checkout verifier passed on 2026-09-20 at
`f8d8d0ec870ccc84e8ce8c58c951f9c076f89e86`.

- [x] Run self-contained script validators and fresh optimized Release tests
  against the exact source and pinned, validated package cache.
- [x] Validate all 698 aggregate outcomes: 690 passed and eight explicit
  allowlisted skips, with zero failures or runtime warnings.
- [x] Pass both mixed-backend transport directions in the separate serial run.
- [x] Pass Release static analysis and all 61 source-tree release-preflight checks.
- [x] Revalidate unchanged HEAD, package hash, package checkouts and clean source
  state before recording success; retain compact evidence in the repository.

See [candidate evidence](docs/evidence/release-candidate-20260920/README.md).
This closes the current optimized regression repeat through Phase 123, not
the skipped external-input gates or native/editor/distribution acceptance.
Release execution still requires verification of its final exact clean commit.

## Remaining work after this continuation

- Repeat the now-integrated SwiftMediaMetadata 3.0.1 production profile with
  producer-authentic long media and on the release-floor base M1. Synthetic
  containers, selected real Sony/raw media, and the exact 3.0.1 library suite
  pass. The September 9 fixture expansion exercises the original twenty skips:
  fourteen pass, five still lack their exact ARW/XMP originals, and one JXL
  expectation fails identically in baseline/candidate and needs reconciliation.
  Phase 70 proves successful byte-preserving writes with its genuine bare
  codestream too; both the mislabeled fixture and obsolete throw assertion
  need upstream reconciliation.
  All 50 upstream CLI
  tests pass without skips, reconfirmed on September 10; nine validator
  regressions enforce complete pinned-suite evidence. The
  isolated candidate reduced the eight-hour peak from about 4.3 GiB to 20 MiB;
  Phase 98 integrates the upstream 3.0.1 release and records only few-MiB
  fresh-host variance rather than payload-sized growth on sparse regression inputs.
  September 8 adds a longer Sony clip, ProRes RAW HQ, ARRIRAW, and X-OCN LT
  parity; September 9 adds GoPro/DJI/Sony FX6 exporter parity. See Phases 46,
  65, and 98.

- Prioritize the candidate blockers in `docs/RELEASE_2_READINESS.md` before
  optional additions; its release assessment does not narrow roadmap scope.
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
  Phase 79 verifies a narrow playback-error panel with visible transport controls
  and MPV inspector-toggle framing with playing/paused intent preserved.
  Stacked-action layouts, final-build EOF and broader comparison/native-backend
  inspector transitions remain separate acceptance checks.
- Resolve has focused passing round trips at 29.97 DF, 59.94 DF and 23.976;
  the latter two retain current-source provenance. Same-frame findings remain
  explicitly rejected. Final Cut’s first native round trip loses overlapping
  findings; Phase 110 replaces the guard with native-verified one-frame/grouped
  markers preserving all findings, with remaining raster, duration and whitespace issues. Complete Final Cut Pro and Avid acceptance separately,
  including fractional rates, DF boundaries, inclusive ranges and source identity.
- Oldest-supported Apple Silicon UHD/HDR playback, reflected loupe/scopes,
  and long-file thumbnail performance profiling.
- Release signing/notarization/update-feed validation, representative-media
  smoke tests, refreshed screenshots/demo, publication, and hands-on editor beta.
- Complete Full Keyboard Access and spoken VoiceOver checks for the revised
  native 7.1 correction text. Phase 52 verifies native text wrapping,
  accessibility-tree content, measurement activation, and Command-I reopening.
  The diagnosed rear-weight discrepancy is corrected in Phase 51; unknown or
  other layouts do not receive that correction.
- Broader WAVE format support: compressed encodings, RIFX extensible variants,
  legacy iXML encodings, further structures and ADM interpretation remain outside the
  bounded reader. Phases 62 and 66 add bounded UTF-8 and UTF-16 iXML recording labels;
  Phase 68 adds bounded track names/indexes and native UTF-16 inspector checks;
  Phase 73 adds bounded UTF-32LE/BE recording labels and tracks;
  Phase 75 verifies native UTF-32 inspector labels and track indexes;
  Phase 77 adds bounded RIFX iXML labels/tracks and reproducible UTF-32 fixtures;
  Phase 78 adds bounded classic RIFX Broadcast WAVE interoperability; Phase 79
  verifies native RIFX UTF-32 iXML and library-produced BWF inspectors.
  Producer-authentic recorder, broader native encoding/container and spoken
  VoiceOver acceptance remain. Phase 59 adds
  classic RIFX metadata and corrected offline analysis/waveforms; RIFX playback
  and trim export remain explicitly unavailable pending a verified decoder fix.
  Phase 54 verifies
  RIFF/RF64/BW64 metadata and corrected 7.1 loudness. Phase 56 adds bounded
  Broadcast WAVE recording tags; native validation is recorded with that phase.
- Validate the implemented peak/true-peak meters and live momentary/short-term
  loudness against representative media and the Phase 81
  calibration/ballistics/preset contract;
  Phase 83 implements and tests the bounded DSP/display foundation. The bounded,
  source-rate-paced decoder, lifecycle owner and selected-track request mapping
  now exist. Typed playback events plus coordinator clock/drift and ahead
  hysteresis policies are tested; the owning meter-window session and activating
  UI and hard 250 ms worker admission bound are integrated. Bounded precise seek
  passes generated AAC/ALAC/AC-3 checks; Phase 85 verifies raw PCM packets
  against same-process decoder timestamps, sizes and checksums. Representative
  sources and live reference validation remain;
  Phase 84 adds production programme profiling and fixes silent long-range
  channel loss plus excessive shared-demux buffering; representative-media and
  release-floor memory acceptance remain.
  Programme LRA/true-peak and broader transient
  reference accuracy remain open, along with representative multichannel
  profiling. Phase 55 adds
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
  an HFS+ recheck. Phase 76 verifies native APFS edit/deletion out-of-space
  errors, retained state and successful retries, with exact file preservation
  and cleanup. Phase 79 extends real APFS/HFS+ publication failure/retry coverage
  to relink and historical-timebase migration. Complete keyboard/VoiceOver, broader narrow layouts and native
  copy/relink/migration disk-full interaction remain open.
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
67. Phase 75 native UTF-32 inspector acceptance.
68. Phase 76 native APFS disk-full edit and deletion recovery.
69. Phase 77 bounded RIFX iXML metadata.

70. Phase 78 classic RIFX Broadcast WAVE interoperability.
71. Phase 79 native inspector correctness and review publication recovery.

72. Phase 80 comparison reload transport and position ownership.

73. Phase 81 live Audio QC measurement contract.

74. Phase 82 programme loudness for split-mono deliverables.

75. Phase 83 bounded live-meter calculation and display foundation.

76. Phase 84 programme analysis teardown, profiling and long-range integrity.

77. Phase 85 timestamp-verified live-meter transport.

78. Phase 86 ordered meter clears and packaged-artifact verification.

79. Phase 87 reproducible candidate verification and mixed-backend pause ownership.

80. Phase 88 live-meter source transitions and production-path integration.

81. Phase 89 live-meter replacement recovery ownership.

82. Phase 90 distinct live-meter accessibility identity.

83. Phase 91 direct review entry and current candidate evidence.

84. Phase 92 live-meter EOF ownership and review accessibility hooks.

85. Phase 93 fail-closed candidate evidence and publication identity.

86. Phase 94 decoded speaker identity and stale speed recovery.

87. Phase 95 candidate-result and publication integrity.

88. Phase 96 HDR scope safety and waveform source integrity.

89. Phase 97 representative live-meter evidence harness.

90. Phase 98 SwiftMediaMetadata 3.0.1 production memory integration.

91. Phase 99 deferred playback-window publication.

92. Phase 100 live-meter asynchronous test synchronization.

93. Phase 101 malformed compressed live-meter gap ownership.

94. Phase 102 offline clean-checkout candidate verification.

95. Phase 103 Resolve marker round-trip acceptance.

96. Phase 104 Resolve same-frame export integrity.

97. Phase 105 repeatable Resolve round-trip comparison.
98. Phase 106 current-source Resolve evidence and repeatable review copies.
99. Phase 107 native Resolve 59.94 DF import and media identity.
100. Phase 108 native Resolve 23.976 relative-time round trip.

101. Phase 109 native Final Cut marker loss and overlap export integrity.

102. Phase 110 Final Cut one-frame markers and complete grouped findings.

103. Phase 111 explicit Final Cut source raster.
104. Phase 112 native Final Cut raster and repeatable comparison.

105. Phase 113 native Final Cut duration integrity.

106. Phase 114 native Final Cut 59.94 drop-frame acceptance.
107. Phase 115 Final Cut asset-format verification and real geometry fixtures.

108. Phase 116 oriented Final Cut browser-clip geometry.

109. Phase 117 native Final Cut timeline and independent source geometry.

110. Phase 118 calibrated native Final Cut rendered geometry.

111. Phase 119 native Final Cut conform isolation.

112. Phase 120 fresh production UI Final Cut anamorphic export.

113. Phase 121 fresh production UI native rendered geometry.

114. Phase 122 Final Cut rotated anamorphic export restriction.

115. Phase 123 native Final Cut whitespace re-import diagnosis and export disclosure.

116. Phase 124 current optimized candidate verification.
