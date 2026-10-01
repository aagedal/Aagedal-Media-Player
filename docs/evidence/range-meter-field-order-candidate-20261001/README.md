# Integrated Review, decoder shutdown and Premiere scan-order candidate — 2026-10-01

Canonical optimized Release verification passes at clean implementation commit
`aa4e617e8848ffd1496e7bf537d72031eecab164`, with fresh DerivedData and the
validated unchanged offline package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 781 total: 772 passed, nine named opt-in skips |
| Six new Review/decoder/Premiere regressions | Passed, required by exact identity |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Release static analysis | Passed |
| Source-tree release preflight | All 61 checks passed |
| Complete script-validator suite | Passed, including 22 Premiere and 18 release-script checks |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, XCTest runtime warnings, sleep | Zero |

[Proof](proof-summary.json), complete test summaries/details, compressed logs,
environment/power receipts and [source hashes](source-sha256.json) retain the
accepted result. Full xcresult bundles and built products remain at
`/private/tmp/aagedal-range-meter-field-order-canonical-20261001`; temporary
storage is not a durable binary archive. The package lockfile remains at
SHA-256 `6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

The candidate includes passive erased-range correction, prompt release of
paced PCM on timestamp failure/cancellation with original diagnostics, and
known Premiere source/sequence field order plus clip-override validation.
The final deterministic decoder harness passes; both tests reject the old
implementation with bounded cleanup. See [focused and baseline evidence](../range-meter-field-order-20261001/README.md).

Native Premiere import/marker/render/re-export, keyboard/spoken accessibility,
public dependency publication/repins, audible/device/surround, hardware/soak/
base-M1 and signing/notarization/distribution gates remain open. Avid remains
optional for 2.0. No remote release was published. Subsequent evidence retention
does not replace matching-HEAD release consumption; the accepted implementation
source above remains explicit.
