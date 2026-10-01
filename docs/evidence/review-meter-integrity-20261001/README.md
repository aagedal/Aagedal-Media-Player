# Review correction and live-meter integrity — 2026-10-01

Two concrete workflow/measurement defects are fixed:

- Ordinary Review text or range validation could select a finding after a
  search filter removed its row. The stable popover now reveals the selected
  hidden finding on correction, reopening or editing restoration, retaining
  every draft. Visible, missing and unavailable targets keep the exact query.
- Current Momentary/Short-term loudness was not checked at the snapshot
  handoff. NaN and positive infinity now clear measurements, fail the owning
  generation and cancel its worker. Nil warm-up and negative-infinity silence
  remain valid, including after Clear Maxima.

The incremental optimized Release [summary](focused-test-summary.json) and
[details](focused-test-details.json) pass all 50 tests: 22 Review text/correction
and 28 Coordinator checks, including four new regressions. There are no skips,
failures, expected failures or runtime warnings. The focused run reuses earlier
DerivedData; it does not supply a clean-checkout candidate result.
[Script self-tests](script-tests.log.gz) pass the complete validator gate.
[Native preflight](preflight-native.log) passes all 61 checks. The initial
[restricted-sandbox attempt](preflight.log) reported a bundled FFmpeg signature
failure; native access passes against the unchanged tracked binary.
The candidate verifier and release consumer now require 760 aggregate tests
and explicitly require all four new regressions, plus both isolated transport
checks. Canonical committed-source verification follows separately.

The independent [dependency inventory work](../coreaudio-stage-inventory-20261001/README.md)
rejects formerly accepted undeclared stage entries and nonregular manifests,
with unchanged authentic retained stage/workspace identities.

A native [Avid First attempt](avid-attempt.json) opens a new disposable project
and reaches the EDL file picker, but path navigation and clipboard entry do not
complete. The separate marker-text importer is not reached. No editor gate is
closed, and the observation is not evidence of importer unavailability.
The disposable project is retained at the recorded temporary path.

Native SwiftUI focus timing, complete keyboard/Full Keyboard Access/spoken
VoiceOver, editor round trips, audible/device/surround, hardware/soak/base-M1,
public dependency compilation/publication/repin and distribution remain open.
