# Passive Review callbacks and publication integrity — 2026-10-01

All 28 focused optimized Release Review text/correction tests pass, including
three new regressions. Detailed XCTest validation reports no skips, failures
or runtime warnings. All 61 source preflight checks pass with normal codesign
access. The complete script-validator suite passes; after raising the candidate
gate, all 18 release-script and 14 XCTest-evidence checks pass again.

Passive text blur/removal and range blur now read the draft owner's current
correction and the controller's current saved note. This prevents a callback
captured before another disappearing field selects a correction from saving
unrelated drafts or displacing focus. Tests cover both callback orderings,
unavailable editing, rejected updates, retry and duplicate blur/removal saves.
Native keyboard/Full Keyboard Access/spoken VoiceOver remains unverified.

The Premiere XML comparator rejects disabled or ambiguously enabled sequences,
tracks and clips, an extra generator on V1, and DTD/entity declarations encoded
as UTF-16/32. All 19 comparator regressions and ten existing engineering XML
self-comparisons pass. File self-comparison does not establish native acceptance.

Release preparation retains the ZIP's original SHA-256 immediately after
packaging and checks its size/hash before Sparkle signing, GitHub mutations,
remote validation and appcast replacement. Executable shell simulations prove
same-size replacement before upload cannot mutate GitHub and replacement during
upload cannot publish either appcast branch. No remote publication was performed.

The initial sandboxed Xcode attempt failed before compilation on package/cache
writes; the preserved unrestricted retry passes. Sandboxed codesign likewise
rejected the unchanged bundled FFmpeg; normal read-only preflight passes.
Full bundles/build products remain in temporary storage at
`/private/tmp/aagedal-passive-review-focused-20261001` and the previously used
`/private/tmp/aagedal-premiere-canonical-20261001/DerivedData`.

Candidate/release gates now require 775 aggregate tests, all three new exact
Review identities and both isolated mixed-backend transport directions.
These focused receipts do not replace canonical committed-source verification
or close editor, accessibility, dependency publication, hardware or distribution
acceptance. Source hashes retain the exact tested implementation.
