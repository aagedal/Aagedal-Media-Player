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
