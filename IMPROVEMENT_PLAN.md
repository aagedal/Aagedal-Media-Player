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

Status: Completed on 2026-08-31.

### Test infrastructure

- [x] Add an `Aagedal Media Player Tests` unit-test target.
- [x] Add focused tests for timecode formatting/parsing, metadata ratios, version comparison, and numeric defaults.
- [x] Extract pure logic from UI/service types where needed for direct testing.
- [x] Add media-fixture support for generated test clips without committing large binaries.
- [x] Add fixtures for common rates, drop-frame boundaries, rotation/PAR, HDR, multichannel audio, subtitles, chapters, and long-GOP trimming.

### Deterministic builds and verification

- [x] Track `Package.resolved`, or pin every package to an exact revision.
- [x] Add a macOS CI workflow that builds, tests, and analyzes the app. Removed by project decision on 2026-08-31.
- [x] Verify build, tests, and analysis from a clean package cache.
- [x] Document the local build/test commands in `README.md` or contributor guidance.

### Acceptance criteria

- A fresh checkout resolves the same package revisions as a release build.
- `xcodebuild test` runs at least one real unit-test bundle.
- Core pure-logic tests run without requiring media playback or network access.
- Local release verification blocks changes that fail build, tests, or static analysis.

## Phase 2 — SMPTE timecode correctness

Status: Completed on 2026-08-31.

- [x] Introduce a rational `TimecodeRate` model containing actual rate, nominal FPS, and drop-frame rules.
- [x] Implement correct 29.97 and 59.94 drop-frame frame-number conversion.
- [x] Replace repeated floating-point calculations with integer/rational frame arithmetic.
- [x] Consolidate absolute, relative, frame-only, source-offset, copy, and paste parsing in one engine.
- [x] Define and test trim-out inclusive/exclusive-frame semantics.
- [x] Reject invalid dropped labels at minute boundaries.
- [x] Add golden tests around minute, ten-minute, hour, and 24-hour wrap boundaries.

Acceptance: formatting and parsing round-trip exactly for every supported rate and source offset.

## Phase 3 — Screenshot and export data safety

Status: Completed on 2026-08-31.

- [x] Create a reusable output coordinator that generates collision-free filenames.
- [x] Write to a temporary sibling and atomically move the completed file into place.
- [x] Remove partial output after failure and cancellation.
- [x] Never overwrite automatically outside an explicit save-panel confirmation or preference.
- [x] Show screenshot/export errors in the app instead of logging them only.
- [x] Add completion actions such as Reveal in Finder, Open, and Copy Path.
- [x] Clarify that stream-copy trims may be keyframe-aligned; identify H.264/H.265 re-encode modes as exact options.
- [x] Validate container/codec compatibility before starting stream copy.

Acceptance: automatic exports cannot silently replace existing user files, and failures leave no partial media behind.

## Phase 4 — Unified subprocess execution

Status: Completed on 2026-08-31.

- [x] Replace the separate ffmpeg runners with one cancellation-aware process service.
- [x] Continuously drain stdout and stderr with bounded diagnostic retention.
- [x] Terminate child processes from Swift task cancellation handlers.
- [x] Fix cancellation-before-process-attachment races.
- [x] Parse progress through a persistent line buffer.
- [x] Add cancellation support to LUFS and waveform generation.
- [x] Evaluate streaming PCM aggregation. Retain the downsampled temporary PCM design for now: it bounds long-file decode size while keeping native multi-channel rendering simple; revisit streaming if Phase 5 profiling identifies memory pressure.

Acceptance: closing or cancelling a feature promptly ends its child process with no hangs or orphans.

## Phase 5 — Scope and waveform performance

Status: Completed on 2026-09-01. Scope work is bounded and cancellation-aware, and an optimized reproducible profiling matrix now covers every supported resolution and 5–30 fps update-rate combination.

- [x] Add a latest-frame-wins scope worker with one computation in flight.
- [x] Drop superseded frames and prevent stale results from replacing newer output.
- [x] Cancel workers when scopes close, media changes, or playback tears down.
- [x] Add signposts for capture, compute, dropped frames, and memory pressure.
- [x] Profile all supported resolution/frame-rate combinations. The reproducible matrix and initial hardware baseline are documented in `docs/SCOPE_PERFORMANCE.md`.
- [x] Replace forced metadata casts in HDR frame capture with safe type handling.

Acceptance: long scope sessions maintain bounded CPU, memory, and task counts.

## Phase 6 — Playback state, errors, and volume

Status: Completed on 2026-08-31.

- [x] Replace overlapping preparation/readiness/error booleans with a typed playback phase.
- [x] Forward MPV initialization, load, and end-file errors into the controller/UI.
- [x] Add Retry, Reveal File, and diagnostic actions to playback failures.
- [x] Add mute and volume controls plus keyboard shortcuts and persistence.
- [x] Apply volume/mute consistently to MPV and AVPlayer.
- [x] Surface buffering/busy state.

Acceptance: every backend failure reaches an actionable UI state, and audio controls behave identically across backends.

## Phase 7 — Accessibility and playback usability

Status: In progress — timeline accessibility, control semantics, status announcements, unified multi-file opening, automatic audio-only waveform presentation, folder navigation, and focus-aware keyboard control navigation are implemented; manual Full Keyboard Access validation remains.

- [x] Make the custom timeline keyboard- and VoiceOver-adjustable.
- [x] Add labels, values, hints, and selected states to icon-only controls.
- [ ] Preserve visible focus rings and test Full Keyboard Access. Every playback control now reports focus, plain-style controls draw explicit focus rings, focused controls suppress auto-hide, and the current key handler is propagated through both playback backends so Space reaches the focused control instead of toggling playback. A live MPV check confirmed timeline/timecode traversal, the visible timecode focus ring, and focused Space activation; Tab/Shift-Tab reveals only the active window's overlay without intercepting traversal. End-to-end validation with macOS Keyboard Navigation enabled for all controls remains.
- [x] Announce export completion, cancellation, and failure.
- [x] Improve audio-only presentation with an automatic waveform option and retryable failure state.
- [x] Handle multi-file drops consistently with Finder open events.
- [x] Add lightweight previous/next navigation across supported media files in the current folder, with per-window menu commands and keyboard shortcuts.

Acceptance: primary playback, seeking, track selection, and export workflows work without a pointing device.

## Phase 8 — Architecture cleanup

Status: Completed on 2026-09-01. Settings, command construction, typed app commands and operation states were centralized, while media operations, track selection, playback backends, per-window file opening, command routing, and overlay ownership were extracted from the two largest stateful components.

- [x] Split `PlayerController` into playback coordination, backend adapters, track selection, trim/export, and screenshot components.
  - [x] Extract trim points, screenshot capture, and trim-export lifecycle into a focused media-operations coordinator.
  - [x] Extract audio, subtitle, and chapter discovery, selection, and backend application into a focused track-selection controller.
  - [x] Extract AVFoundation and MPV adapters for player ownership, shared transport/audio operations, seeking, teardown, and testable backend routing.
- [x] Split window/file-open coordination and overlays out of `ContentView`.
- [x] Replace stringly typed NotificationCenter command payloads with typed commands or focused scene actions.
- [x] Centralize settings keys and defaults in a typed settings store.
- [x] Replace clusters of status booleans with enums.
- [x] Move export command construction into pure, tested builders.

Acceptance: state transitions have a single owner and pure behavior can be tested without constructing views or decoders.

## Phase 9 — Release engineering

Status: Completed on 2026-09-01. The release pipeline now fails before publishing inconsistent metadata or artifacts and records the architecture and security decisions that must be revisited when dependencies or file access change.

- [x] Reconcile the shared scheme with the documented requirement to disable Metal API Validation for MoltenVK.
- [x] Review disabled Main Thread Checker and performance diagnostics settings. Both checkers are enabled; only the MoltenVK-specific Metal validation exception remains.
- [x] Add release preflight checks for version/build monotonicity, changelog/appcast consistency, signatures, URLs, and the bundled ffmpeg hash/architecture.
- [x] Decide whether the app is intentionally Apple-Silicon-only and either document that prominently or evaluate universal artifacts. Releases are intentionally arm64-only until all native dependencies and playback paths can be validated as universal builds.
- [x] Document why App Sandbox and library validation exceptions are required, and periodically reassess their scope.

Acceptance: releases fail early on inconsistent metadata or artifacts and have an auditable, reproducible dependency set.

## Recommended delivery sequence

1. Phase 1 foundation.
2. Phase 2 timecode and Phase 3 export safety.
3. Phase 4 subprocesses and Phase 5 performance.
4. Phase 6 playback state and Phase 7 accessibility/usability.
5. Phase 8 architecture cleanup and Phase 9 release hardening throughout subsequent releases.
