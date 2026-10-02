# Integrated range, clock and Premiere source-selection candidate — 2026-10-02

Canonical optimized Release verification passes at clean implementation commit
`744444969bb6d7cbbf9a4b554d874f44388452e1`, using fresh DerivedData and the unchanged verified offline package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 802 total: 793 passed, 9 named opt-in skips |
| Seven new Review/meter regressions | Passed, required by exact identity |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Release static analysis | Passed |
| Source-tree release preflight | All 61 checks passed |
| Complete script-validator suite | Passed, including 37 Premiere and 18 release-script checks |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, runtime warnings, sleep | Zero |

[Proof](proof-summary.json), complete summaries/details, compressed logs,
[source hashes](source-sha256.json) and [receipt hashes](evidence-sha256.json)
retain the accepted result. Full xcresult bundles and built products remain at
`/private/tmp/aagedal-review-clock-source-canonical-20261002`; temporary storage is not a durable binary archive.
The package lockfile remains at SHA-256
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

The accepted implementation preserves merged Review endpoints on queued range
Apply/Return, clears and cancels invalid paused/buffering meter clocks, and
rejects unsupported Premiere connected-source/timecode selectors. The preceding
meter failures and comparator false exact-match reproductions remain in
[focused receipts](../review-clock-source-20261002/README.md).

No new native editor/accessibility, public dependency publication/repin,
audible/device/surround, sustained/base-M1 or signing/notarization/distribution
acceptance is claimed. Avid remains optional for 2.0. No release was published.
Later documentation retention does not replace matching-HEAD release consumption;
the accepted implementation commit remains explicit above.
