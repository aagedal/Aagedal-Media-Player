# Review correction focus arbitration

Date: 2026-09-30. This is focused working-tree engineering evidence, including
parallel implementation changes. It is separate from clean-candidate verification.

## Source finding and correction

Action preflight checks empty edited note text before pending range drafts.
When the range field owns focus, selecting that text correction resigns the
range field. Previously its focus-loss handler immediately validated a changed
range draft. A malformed endpoint then set a range error and requested range
focus again, competing with the chosen text correction. A valid endpoint could
also commit during focus handoff despite preflight blocking the action on text.

An explicit text correction now keeps the unrelated range draft pending during
that focus handoff. Range error and disclosure callbacks also respect the text
correction. Ordinary range focus-loss validation resumes when the text correction
clears. Accepted note-text commitment explicitly clears its own text correction,
while retaining a separate range correction and its draft/error.

Three regressions cover correction priority and pending-draft preservation,
normal changed/unchanged/empty range focus-loss behavior, and preservation of a
separate range correction after accepted text commitment. All nineteen focused
optimized Release tests across `CompareReviewTextCommitTests` and
`CompareSessionLifecycleTests` pass without skips or failures. The repository
XCTest evidence validator reconciles summary and detailed outcomes, requires all
three new cases, and reports no runtime warnings. Swift frontend parsing and
`git diff --check` also pass.

The initial sandboxed build could not write Xcode package/compiler caches; the
normal-cache retry passed before final cleanup changes. The next build caught a
parallel MPV screenshot value-type actor-isolation issue before tests ran. Its
owner corrected that issue, and the final nineteen-test run above passed. Earlier
attempts remain separate logs/results under `/private/tmp/aagedal-review-focus-20260930*`.
The passing run's summary is [test-summary.json](test-summary.json), with paths
and source/package hashes in [verification.json](verification.json).

## Native acceptance remains open

A single `cua.getState()` inventory with a requested twenty-second timeout
returned in 7.636 seconds. It reported no native apps and explicitly reported
that the Mac was locked and automatic unlock could not unlock it. The exact
observation is retained in [native-inventory.json](native-inventory.json).
No app-selection call, keyboard interaction or preference change followed.

The source finding has not been reproduced or verified through native focus
interaction. Complete structured-control traversal, repeated blocked-action
focus/scroll/disclosure checks, keyboard export, same-source reload/retry,
Full Keyboard Access, spoken VoiceOver and the broader backend/window/layout
matrix remain open. Manual unlock is required before native acceptance can
continue; the automated policy checks do not establish spoken or native behavior.
