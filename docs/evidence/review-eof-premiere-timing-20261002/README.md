# Review deletion, live-meter EOF clocks and Premiere timing — 2026-10-02

This continuation fixes three demonstrated gaps in the 2.0 inspection workflow.

- A deletion queued before a pending save disabled editing could discard the
  saved row's unsaved text/range input. The controller now reports acceptance;
  rejected deletion keeps drafts, errors, correction focus and departure
  validation. An accepted deletion retires only its finding's input. New-note
  feedback also retires synchronously with input, preventing a delayed observer
  from clearing newer export preflight guidance.
- Playback EOF bypassed clock validity while the paced decoder drained. Invalid
  EOF clocks and clock loss during drainage now clear readings/provenance and
  cancel the worker. Valid EOF drainage and decoder-completed readings retain
  their existing behavior. Both new regressions fail on the preceding
  coordinator; the fixed checks cover NaN, infinities, negative time, frame
  overflow, gate release and trailing-event non-revival.
- Premiere round-trip validation accepted freeze frames, slipped sources,
  multiclips and contradictory native tick endpoints as exact matches. Eight
  retained baseline mutations reproduce that result; the corrected comparator
  rejects each. Explicit moving/zero-offset defaults remain accepted. All five
  retained native receipts keep their earlier comparison results; this is
  stricter verification, not new editor import acceptance.

## Verification

All **94 focused optimized Release tests** pass with no skips or runtime
warnings: Review draft ownership, asynchronous review-controller save actions,
and live-meter coordination. Detailed evidence includes all four new exact
regression identities. All **43 Premiere checks**, **18 release-script checks**
and **61 source preflight checks** pass. The complete script-validator gate is
run separately and retained before commit. Candidate and release consumption
now require 806 aggregate tests plus both isolated transport directions, with
all four new exact identities required.

Full result bundles, built products and uncompressed logs remain under
`/private/tmp/aagedal-review-keyboard-continuation-20261002`. The focused build
uses the unchanged pinned cache at
`/private/tmp/aagedal-itu-live-dd-20260930/SourcePackages`; its DerivedData was
reused for this engineering check. A fresh canonical committed-source run
follows separately. Temporary storage is not a durable binary archive.

## Native attempt and remaining gates

The rebuilt Release player opened with its current Review menu and controls.
The native Open dialog and Go To path chooser were accessible, but automated
confirmation/cancellation repeatedly returned the chooser to its root path
instead of reliably opening the fixture or dismissing. Text entry also required
explicit focus after an initial truncated path, and clipboard insertion timed
out. The app was closed through its native Quit menu. No review was created or
exported in this attempt, and no new keyboard, Full Keyboard Access or spoken
VoiceOver acceptance is inferred. These observations do not distinguish an
input-automation limitation from a native interaction problem.

Public dependency publication/repin, wider editor acceptance, audible/device/
surround, sustained/base-M1 and distribution gates remain open. Avid remains
optional for 2.0. No release or dependency was published.
