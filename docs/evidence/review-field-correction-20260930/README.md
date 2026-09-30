# Review field-specific correction priority — 2026-09-30

## Source findings and correction

After export preflight selects an empty note's text for correction, editing its
range or receiving a saved-endpoint update used to clear the text correction
because both draft bindings dismissed notices using only the finding ID. The
reverse happened when editing text while a range correction remained pending.
Losing that request also removed its focus-loss priority while the unrelated
invalid draft still needed correction.

Draft setters now dismiss only a correction for the field being edited. Range
input, Clear range's saved-endpoint synchronization, and edits to another finding
retain the chosen text correction. Editing text retains a pending range
correction. Correcting the requested field still clears its notice normally.

The audit also found that a range field in a different finding received no text
correction priority: focus requests were correctly restricted to their target
finding, but that filtered request was also used for blur validation. Every row
now receives the globally selected correction field for range blur/error/disclosure
arbitration, while its actual focus request remains restricted to the target.
Thus selecting empty text in finding A cannot validate and refocus an unrelated
range draft in finding B during the handoff.

Two focused regressions cover same- and different-finding edits, preservation of
text priority during range blur, and clearing only the requested correction.
Swift frontend parsing and `git diff --check` pass. All 21 focused optimized
Release text-commit/session-lifecycle checks pass with no skips, failures or
runtime warnings. Detailed result validation explicitly requires both new
regressions. The root ran these checks after producer-media profiles released
the native host. Source hashes and verification outcomes are retained in
[verification.json](verification.json); full output remains at
`/tmp/aagedal-review-field-correction-20260930.log`.

## Native acceptance remains open

A single computer-use inventory returned in 2.2114 seconds with native apps,
the player marked not running, and no lock error. This inventory alone does not
establish that an interactive desktop or player window was available.

Selecting the current shipping-pin Release app did not return an initial UI
state. Although a 30-second timeout was requested, the call was aborted after
572.2 seconds. No retry, keyboard input, preference change, or native acceptance
step followed. The UI reservation was released for the queued producer-media
profiles immediately after the abort became observable.

No correction focus, repeated blocked export, range-field Tab, Full Keyboard
Access, or spoken VoiceOver acceptance is claimed. The source regressions must
remain separate from those native gates.
