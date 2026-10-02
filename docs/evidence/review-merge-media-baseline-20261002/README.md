# Review merged deletion and Premiere media baseline — 2026-10-02

Review now retires drafts and correction ownership for findings removed by a
successful same-sidecar merge. Surviving drafts and window-level notices remain;
temporary empty notes during unavailable editing preserve reload input. All
46 focused optimized Release text-commit tests pass, with no skips, failures or
runtime warnings, including four new reconciliation regressions. Complete
script-validator checks pass, including 47 Premiere checks.

Premiere comparison can consume a pre-import media-byte receipt, bound to the
original XML hash and canonical source path. The retained reproduction replaces
media in place: post-only hashing returns `exact-match`; baseline checking returns
`differences` with `sourceMediaMatchesBaseline=false`. These are synthetic parser
checks; no fresh native Premiere acceptance is inferred.

The native observation uses the preceding verified Release app at implementation
commit `af0fd03f1a83ec9e9442832266c42d37f159f024`, before this reconciliation change.
Keyboard comparison setup, finding creation/editing, inclusive 0–24 range entry,
filtering and CSV export pass. The filtered-out finding remains in the CSV with
exact 24/1 rates, A frame 0, B frame 24, complete source URLs and edited text.
Both generated media hashes remain unchanged. Opening the classification/range
disclosure used one accessibility click: this is partial keyboard acceptance,
not complete structured-control traversal, Full Keyboard Access or spoken
VoiceOver. A fresh continuation app reopens the saved review and retains a rejected
range. A simulated external deletion in the isolated sidecar does not reach a
production merge: correction focus prevents redirecting input to the add-note
field. The attempt is inconclusive and the test sidecar is restored from its
backup; see [attempt receipt](native-continuation-attempt.json). The actual
two-window merged-deletion scenario still needs native acceptance. See [observed actions and identities](native-observation.json),
[CSV](native-keyboard-range-review.csv) and [sidecar](native-review-sidecar.json).

Focused xcresult and fresh build products remain at
`/private/tmp/aagedal-2-reconcile-focused-20261002.xcresult` and
`/private/tmp/aagedal-2-reconcile-focused-20261002`; temporary storage is not a
binary archive. Detailed summaries and compressed logs are retained here.
Canonical clean implementation verification is recorded separately after commit.
No dependency repin, hardware acceptance or distribution is claimed.
