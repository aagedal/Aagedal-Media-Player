# Aagedal Media Player Improvement Plan

This plan is based on a read-only source, build, and static-analysis audit performed on 2026-08-29. The app built successfully in Debug configuration and passed Xcode static analysis. The work below is therefore ordered around behavioral correctness, user-data safety, regression prevention, and maintainability.

## Priorities

1. Establish deterministic builds and automated regression coverage.
2. Correct SMPTE timecode behavior, especially 29.97/59.94 drop-frame handling.
3. Make screenshots and exports collision-safe, atomic, and visibly fallible.
4. Unify ffmpeg process execution, progress, and cancellation.
5. Bound scope and waveform CPU/memory work.
6. Complete playback error propagation and audio controls.
7. Improve accessibility and everyday playback usability.
8. Simplify large stateful components after tests protect existing behavior.
9. Harden CI and release preflight validation.

## Phase 1 — Regression safety net

Status: In progress — the test/CI foundation was implemented on 2026-08-29; generated media fixtures remain.

### Test infrastructure

- [x] Add an `Aagedal Media Player Tests` unit-test target.
- [x] Add focused tests for timecode formatting/parsing, metadata ratios, version comparison, and numeric defaults.
- [x] Extract pure logic from UI/service types where needed for direct testing.
- [ ] Add media-fixture support for generated test clips without committing large binaries.
- [ ] Add fixtures for common rates, drop-frame boundaries, rotation/PAR, HDR, multichannel audio, subtitles, chapters, and long-GOP trimming.

### Deterministic builds and CI

- [x] Track `Package.resolved`, or pin every package to an exact revision.
- [x] Add a macOS CI workflow that builds, tests, and analyzes the app.
- [ ] Verify the workflow from a clean package cache.
- [x] Document the local build/test commands in `README.md` or contributor guidance.

### Acceptance criteria

- A fresh checkout resolves the same package revisions as a release build.
- `xcodebuild test` runs at least one real unit-test bundle.
- Core pure-logic tests run without requiring media playback or network access.
- CI blocks changes that fail build, tests, or static analysis.

## Phase 2 — SMPTE timecode correctness

- Introduce a rational `TimecodeRate` model containing actual rate, nominal FPS, and drop-frame rules.
- Implement correct 29.97 and 59.94 drop-frame frame-number conversion.
- Replace repeated floating-point calculations with integer/rational frame arithmetic.
- Consolidate absolute, relative, frame-only, source-offset, copy, and paste parsing in one engine.
- Define and test trim-out inclusive/exclusive-frame semantics.
- Reject invalid dropped labels at minute boundaries.
- Add golden tests around minute, ten-minute, hour, and 24-hour wrap boundaries.

Acceptance: formatting and parsing round-trip exactly for every supported rate and source offset.

## Phase 3 — Screenshot and export data safety

- Create a reusable output coordinator that generates collision-free filenames.
- Write to a temporary sibling and atomically move the completed file into place.
- Remove partial output after failure and cancellation.
- Never overwrite automatically outside an explicit save-panel confirmation or preference.
- Show screenshot/export errors in the app instead of logging them only.
- Add completion actions such as Reveal in Finder, Open, and Copy Path.
- Clarify that stream-copy trims may be keyframe-aligned; add an exact re-encode option.
- Validate container/codec compatibility before starting stream copy.

Acceptance: automatic exports cannot silently replace existing user files, and failures leave no partial media behind.

## Phase 4 — Unified subprocess execution

- Replace the separate ffmpeg runners with one cancellation-aware process service.
- Continuously drain stdout and stderr with bounded diagnostic retention.
- Terminate child processes from Swift task cancellation handlers.
- Fix cancellation-before-process-attachment races.
- Parse progress through a persistent line buffer.
- Add cancellation support to LUFS and waveform generation.
- Consider streaming PCM aggregation instead of loading the full temporary raw file.

Acceptance: closing or cancelling a feature promptly ends its child process with no hangs or orphans.

## Phase 5 — Scope and waveform performance

- Add a latest-frame-wins scope worker with one computation in flight.
- Drop superseded frames and prevent stale results from replacing newer output.
- Cancel workers when scopes close, media changes, or playback tears down.
- Add signposts for capture, compute, dropped frames, and memory pressure.
- Profile all supported resolution/frame-rate combinations.
- Replace forced metadata casts in HDR frame capture with safe type handling.

Acceptance: long scope sessions maintain bounded CPU, memory, and task counts.

## Phase 6 — Playback state, errors, and volume

- Replace overlapping preparation/readiness/error booleans with a typed playback phase.
- Forward MPV initialization, load, and end-file errors into the controller/UI.
- Add Retry, Reveal File, and diagnostic actions to playback failures.
- Add mute and volume controls plus keyboard shortcuts and persistence.
- Apply volume/mute consistently to MPV and AVPlayer.
- Surface buffering/busy state.

Acceptance: every backend failure reaches an actionable UI state, and audio controls behave identically across backends.

## Phase 7 — Accessibility and playback usability

- Make the custom timeline keyboard- and VoiceOver-adjustable.
- Add labels, values, hints, and selected states to icon-only controls.
- Preserve visible focus rings and test Full Keyboard Access.
- Announce export completion, cancellation, and failure.
- Improve audio-only presentation, preferably with an automatic waveform option.
- Handle multi-file drops consistently with Finder open events.
- Evaluate folder navigation or a lightweight queue after the core work is stable.

Acceptance: primary playback, seeking, track selection, and export workflows work without a pointing device.

## Phase 8 — Architecture cleanup

- Split `PlayerController` into playback coordination, backend adapters, track selection, trim/export, and screenshot components.
- Split window/file-open coordination and overlays out of `ContentView`.
- Replace stringly typed NotificationCenter command payloads with typed commands or focused scene actions.
- Centralize settings keys and defaults in a typed settings store.
- Replace clusters of status booleans with enums.
- Move export command construction into pure, tested builders.

Acceptance: state transitions have a single owner and pure behavior can be tested without constructing views or decoders.

## Phase 9 — Release engineering

- Reconcile the shared scheme with the documented requirement to disable Metal API Validation for MoltenVK.
- Review disabled Main Thread Checker and performance diagnostics settings.
- Add release preflight checks for version/build monotonicity, changelog/appcast consistency, signatures, URLs, and the bundled ffmpeg hash/architecture.
- Decide whether the app is intentionally Apple-Silicon-only and either document that prominently or evaluate universal artifacts.
- Document why App Sandbox and library validation exceptions are required, and periodically reassess their scope.

Acceptance: releases fail early on inconsistent metadata or artifacts and have an auditable, reproducible dependency set.

## Recommended delivery sequence

1. Phase 1 foundation.
2. Phase 2 timecode and Phase 3 export safety.
3. Phase 4 subprocesses and Phase 5 performance.
4. Phase 6 playback state and Phase 7 accessibility/usability.
5. Phase 8 architecture cleanup and Phase 9 release hardening throughout subsequent releases.
