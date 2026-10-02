# Review ranges, suspended meter clocks and Premiere source selectors — 2026-10-02

Explicit range Apply/Return now resolves the current finding and live typed
draft. An untouched or retired row cannot replay an old endpoint over a
same-sidecar merge. Rejected input remains available for correction and retry.

Paused/buffering meter clocks are validated before suspension returns. Lost
clocks clear readings, invalidate the generation and cancel the worker; valid
contiguous suspension retains readings and held maxima until resume. The new
tests cover startup and established PCM, non-finite/negative/overflow-scaled
positions, queued clock rejection and explicit retry.

The independent Premiere comparator rejects unsupported or ambiguous connected
video tracks, field offsets and auxiliary timecode sources. It accepts explicit
defaults equivalent to omitted selectors. All five retained native receipts keep
their prior differences; their absent media bytes are not re-proved.

| Gate | Result |
| --- | --- |
| Optimized Release Review text/range checks | 41 passed |
| Optimized Release meter coordinator checks | 32 passed |
| Seven new app identities | Passed, checked individually |
| Corrected focused skips/runtime warnings | Zero |
| Preceding meter implementation | Both clock-loss tests failed |
| Premiere Python checks | 37 passed |
| Complete script-validator suite | Passed |
| Source-tree release preflight | All 61 checks passed with normal macOS security access |

[Proof](proof-summary.json), complete summaries/details, compressed logs and
[source hashes](source-sha256.json) retain these results. The
[Premiere reproduction](premiere-baseline-reproduction.json) records three
false exact-match results from the preceding comparator and their rejection.
The original meter source was restored only for the baseline run, then replaced
with the fixed source before corrected testing; both source hashes are retained.

Full xcresult bundles and build products remain under
`/private/tmp/aagedal-review-clock-source-focused-20261002`, using the verified
unchanged package cache at `/private/tmp/aagedal-itu-live-dd-20260930/SourcePackages`.
Temporary storage is not a durable binary archive. Focused results do not supply
clean-commit canonical verification; candidate/release consumption requires 802
aggregate tests and the seven new exact app identities, plus both isolated
mixed-backend transport directions.

No new native editor/accessibility, public dependency publication/repin,
audible/device/surround, sustained/base-M1 or signing/notarization/distribution
acceptance is claimed. Avid remains optional for 2.0. No release was published.
