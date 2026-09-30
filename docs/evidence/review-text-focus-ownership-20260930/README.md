# Review passive text commitment and correction ownership — 2026-09-30

## Source finding

Action preflight selects the first empty finding before any pending range. Range
focus-loss validation already respected a selected text correction, but every
text field still called `commit()` on blur and disappearance. Empty or rejected
text immediately refocused that row, including a different finding from the one
selected by preflight. A valid unrelated text draft could also save during a
handoff to a range correction despite the blocked action.

Each row now receives the globally selected correction request, while its actual
focus request remains restricted to its own finding. Passive text commitment and
fallback text-error focus are permitted only when no correction is selected or
the request selects that row's text. Other drafts and existing errors remain
pending. Correcting the selected field restores ordinary blur validation.
Explicit Return still commits the field the user is editing.

Two regressions exercise empty text in a different finding, and valid pending
text in both the same and a different finding during a range correction. They
check selected-request retention, prevention of partial updates, and resumption
after the selected field is edited. There are now 13 Review text-commit tests,
23 across that suite and session lifecycle. This contribution adds two aggregate
tests; the root coordinates the final release-candidate floor with other changes.

Swift frontend parsing and `git diff --check` pass. All 34 focused optimized
Release checks pass (13 Review text and 21 meter coordinator), with no skips,
failures or runtime warnings. Detailed validation requires both new Review
regressions and the new meter diagnostic regression. The final integrated
candidate run remains separate; these tests do not establish native focus or
spoken behavior. Full results remain in
`/private/tmp/aagedal-2-continuation-focused-20260930/Corrected.xcresult`.

## Native attempt and limitation

One `cua.getState()` call with a requested 20-second timeout returned in 0.7876
seconds. The inventory contained native apps, marked the player as not running,
and reported no lock error. This alone did not establish an available interactive
player window.

One `cua.getApp()` call selected the identified candidate at
`/private/tmp/aagedal-authentic-continuation-fixed-candidate-20260930/DerivedData/Build/Products/Release/Aagedal Media Player.app`.
It requested a 20-second timeout but returned no initial app state. The root
interrupted the blocked attempt; the tool recorded an abort after 351.6 seconds.
The tool's generic “aborted by user” label does not indicate a new user request.
No retry, keyboard input, native acceptance step or accessibility preference
change followed. The native UI reservation was released to the meter agent.

No correction focus, keyboard-only traversal, Full Keyboard Access or spoken
VoiceOver acceptance is claimed. Accessibility inventory does not constitute
spoken VoiceOver evidence. The source finding remains independently identified,
without a native reproduction in this continuation.
