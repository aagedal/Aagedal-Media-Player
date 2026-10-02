# Integrated merged Review deletion and media baseline candidate — 2026-10-02

Canonical optimized Release verification passes at clean implementation commit
`316e1bfdb6de7f1f5a7d697a09e259f7185357d3`, using fresh DerivedData and the
unchanged pinned offline package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 810 total: 801 passed, nine named opt-in skips |
| Four reconciliation identities | Passed, required by exact identity |
| Isolated mixed-backend transport | Both directions pass; no skips |
| Release static analysis | Passed |
| Source release preflight | All 61 checks passed |
| Script validators | Passed, including 47 Premiere checks |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, runtime warnings, sleep | Zero |

Complete detailed test reports, environment, power and compressed verification
logs are retained here. Full xcresult bundles and build products remain at
`/private/tmp/aagedal-review-merge-baseline-canonical-20261002`; temporary storage
is not a durable binary archive. Package.resolved remains SHA-256
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

[Focused/native receipts](../review-merge-media-baseline-20261002/README.md)
retain partial keyboard acceptance and the inconclusive native merge attempt.
The later native investigation identifies repeated invalid-range validation
reacquiring focus and overriding deliberate entry navigation. This accepted
batch precedes that additional focus fix; final continuation evidence must name
its own implementation commit. No dependency publication/repin, hardware,
complete spoken accessibility or distribution acceptance is inferred.
Documentation retention does not replace matching-HEAD release consumption.
