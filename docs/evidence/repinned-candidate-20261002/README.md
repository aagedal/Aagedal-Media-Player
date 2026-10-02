# Repinned dependency candidate — 2026-10-02

Canonical optimized Release verification passes at clean source commit
`53d055b7f1839f5a6c209e9441c1c4e764592f15`, using fresh DerivedData and the
freshly resolved published package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 818 total: 809 passed, nine named opt-in skips |
| Isolated mixed-backend transport | Both directions pass without skips |
| Release static analysis | Passed |
| Source release preflight | All 61 checks passed |
| Script validators | Passed, including offline CoreAudio build regressions |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, runtime warnings, sleep | Zero |

MPVKit is pinned to `1d44b9a0aa9e8faa5b8bf222173f6cc2930ed233` and
SwiftMediaMetadata to exact 3.0.2 (`9e8e912deb8d941da66a4b76854a90e3e9f01e3f`).
Package.resolved SHA-256 is
`91ff8b51c0b73b91f653360fc8f1252944f6a5eaf513ea83c9c08871fe525d05`.

The first run at `7c95d27` is rejected as candidate evidence: this worktree
lacked ignored generated fixtures and consequently skipped required tests.
After regenerating them with `scripts/generate-test-fixtures.sh`, this separate
new canonical run passes all required identities. No required skip was waived.

Full result bundles/build products remain at
`/private/tmp/aagedal-repinned-candidate-fixtures-20261002`; temporary storage
is not a durable binary archive. These receipts establish source/test and
published dependency integration acceptance. Native editor, spoken accessibility,
hardware/device, source-pixel and distribution acceptance remain separate.
Later documentation retention does not replace matching-HEAD release consumption.
