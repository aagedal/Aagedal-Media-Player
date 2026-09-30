# Review current-frame range correction

Date: 2026-09-30.

## Demonstrated source defect

A finding already has inclusive endpoint 90. The user enters an invalid endpoint
and then chooses **End at current frame** while source A remains at frame 90.
`updateReviewRange` correctly returns success without mutating the note or its
timestamp. Previously, the view only cleared the range error on that success;
the typed draft was refreshed by `onChange(of: note.primaryEndFrame)`. Because the
saved endpoint did not change, that callback had nothing to observe. The invalid
draft survived the explicit correction and blocked the next report action.

The current-frame action now synchronizes the draft directly from the controller's
accepted endpoint, including this unchanged-endpoint path. It clears that range's
error and correction request. Failed actions retain the typed input, and correcting
a range does not dismiss a separate note-text correction.

## Regression coverage

- `CompareReviewTextCommitTests.testCurrentRangeActionReplacesInvalidDraftEvenWhenSavedEndpointIsUnchanged`
  checks that an unchanged saved endpoint replaces invalid input, removes the
  pending edit, and clears its range correction.
- `CompareReviewTextCommitTests.testCurrentRangeActionRetainsFailedInputAndUnrelatedTextCorrection`
  checks rejected actions and preservation of a separate text correction.
- `CompareSessionLifecycleTests.testReviewClassificationAndRangeEditsPreserveCoordinatesAndPersist`
  now exercises draft correction through the real controller's successful
  same-endpoint `updateReviewRange` path. The complete finding, including its
  timestamp, stays unchanged while the invalid draft and blocking state clear.

`git diff --check` and Swift frontend parsing pass. The optimized Release
run passes all sixteen tests across `CompareReviewTextCommitTests` and
`CompareSessionLifecycleTests`, including both new draft tests and the real
controller persistence case, with no skips or failures. The retained summary
is [test-summary.json](test-summary.json); full logs and result bundle remain
at `/private/tmp/aagedal-review-correction-release-20260930.log` and
`/private/tmp/aagedal-review-correction-release-20260930.xcresult`.
The complete canonical candidate verification remains separate.

## Native acceptance remains open

Computer-use inventory returned promptly. Selecting the cached isolated app at
`/private/tmp/aagedal-2-review-drafts/Build/Products/Debug/Aagedal Media Player.app`
did not return before the call was cancelled after 740.2 seconds, despite its
requested 30-second timeout. No retry was attempted. The available inventory does
not establish whether the desktop was unlocked or whether the app launched.

No keyboard action, structured-control traversal, focus correction, native export,
Full Keyboard Access or spoken VoiceOver check completed in this continuation.
The source regression establishes the unchanged-endpoint correction behavior; it
does not close the broader native Review acceptance gate.
