# Integrated Review navigation candidate — 2026-10-02

Canonical optimized Release verification passes at clean implementation commit
`a4971ab812af1d87ef5bc9e930a67b11ec60d045`, with fresh DerivedData and the
unchanged pinned offline package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 818 total: 809 passed, nine named opt-in skips |
| Eight new focus identities | All pass, required by exact identity |
| Isolated mixed-backend transport | Both directions pass without skips |
| Release static analysis | Passed |
| Source release preflight | All 61 checks passed |
| Script validators | Passed, including 47 Premiere checks |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, runtime warnings, sleep | Zero |

Both release paths require 65 identical test identities, including the eight
focus regressions and the preceding four merged-deletion checks. Detailed
summaries, complete test trees, environment/power records and compressed logs
are retained here. Full result bundles/build products remain at
`/private/tmp/aagedal-review-navigation-canonical-20261002`; temporary storage
is not a durable binary archive. Package.resolved remains SHA-256
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

[Focused/native receipts](../review-focus-navigation-20261002/README.md)
distinguish passing command/filter/export/reopen/multi-field focus and simulated
external-client merge observations from full keyboard/VoiceOver and actual
two-window acceptance. Native observations use focused build products, not this
fresh canonical binary. This is source/test acceptance, not dependency repin,
hardware or distribution acceptance. Later documentation retention does not
replace matching-HEAD release consumption.
