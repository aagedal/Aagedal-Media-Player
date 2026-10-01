# Integrated Premiere and Review candidate — 2026-10-01

Canonical optimized Release verification passes at clean commit
`f0486a58632e05bc95de979237e85e4108c0ec50`, using fresh DerivedData and the
validated unchanged offline package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 772 total: 763 passed, nine named opt-in skips |
| Nine new Premiere/Review regressions | Passed, required by exact identity |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Release static analysis | Passed |
| Release preflight | All 61 checks passed |
| Complete script-validator suite | Passed, including 14 Premiere checks |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, XCTest runtime warnings, sleep | Zero |

[Proof summary](proof-summary.json), exact test summaries/details, compressed
logs, environment, power receipts and [source hashes](source-sha256.json)
retain the accepted result. Full xcresult bundles and built products remain at
`/private/tmp/aagedal-premiere-canonical-20261001`; temporary storage is not a
durable binary archive. The package lockfile SHA-256 remains
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

The implementation adds Premiere FCP7 XML sequence-marker export and saves
Review range drafts when fields disappear. The preceding 90 focused Release
checks and ten production-metadata XML/CSV pairs are retained in the
[engineering record](../premiere-review-engineering-20261001/README.md).
Native Premiere binding returned no UI state before cancellation. File
self-comparisons do not establish an editor round trip.

Native Premiere/other editor acceptance, keyboard/Full Keyboard Access/spoken
VoiceOver, audible/device/surround, hardware/soak/base-M1, public dependency
publication/repins and signing/notarization/distribution remain open. Avid is
optional for 2.0. Subsequent evidence retention does not replace matching-HEAD
release consumption; the accepted source commit above stays explicit.
