# Review range-correction ownership — 2026-09-30

## Concrete source defect and correction

Action preflight can select an invalid range in finding A while another finding
B has a changed range draft or an earlier range error. The range focus-loss
policy previously received only the selected field, so `.rangeEnd` allowed B's
blur callback to validate and save its draft, or refocus B after a failed
validation. B's error-change, row-appearance and disclosure-expansion callbacks
also treated any selected range as permission to take focus. This could displace
the correction chosen by action preflight. Phase 175 restricted passive text
callbacks by finding identity; the analogous range path still lacked that guard.

Range callbacks now receive the complete correction request and accept passive
work only for its selected finding and range field. The same policy controls
blur commits and passive error/disclosure focus. Explicit Return, Apply and
current-frame actions continue to handle the field the user invokes. Editing the
selected correction clears its request, restoring ordinary range blur behavior.

One new regression, `testRangeCorrectionDefersOtherFindingRangeBlurAndPassiveFocus`,
covers both valid and invalid unrelated range drafts, preserves the chosen
request and draft/error state, allows the selected range's passive focus, and
restores ordinary callbacks after the selected range is edited. Existing text
priority and normal range-validation checks use the complete request as well.
Swift frontend parsing and `git diff --check` passed. Canonical optimized Release
XCTest verification will be retained by the root's integrated run; this receipt
does not independently claim an XCTest result.

## Native acceptance remains blocked

The computer-use inventory succeeded and reported the player not running.
Selecting the existing Release candidate with a requested 20-second tool timeout
returned no initial accessibility state. The root agent cancelled the call after
639.7 seconds; the tool reports that cancellation as “aborted by user.” No retry, keyboard input, settings change, or interaction with a
hosted test app followed. This is a native app-binding limitation, not a failed
keyboard acceptance result.

Repeated correction focus, structured text/range editing, keyboard-only
navigation/export, Full Keyboard Access and spoken VoiceOver acceptance remain
open. No VoiceOver claim is inferred from an accessibility tree. The complete
native receipt and source hashes are in [verification.json](verification.json).
