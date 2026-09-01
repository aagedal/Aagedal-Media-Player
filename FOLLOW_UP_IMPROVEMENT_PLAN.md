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

## Delivery order

1. Phase 10 correctness fixes and regression tests.
2. Phase 11 task isolation and off-main-actor rerendering.
3. Phase 11 bounded PCM aggregation and profiling.
4. Phase 12 operation ownership.
5. Phase 13 update-state improvements and incremental cleanup.
