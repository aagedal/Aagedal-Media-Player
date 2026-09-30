# Integrated resource and Review continuation verification — 2026-09-30

The canonical optimized Release verifier passes for clean implementation commit
`dfc9137fe39e4c93ed01f63cbe81717dec01902e`. A source-only detached clone uses
entirely fresh DerivedData, the validated unchanged package cache, and existing
schema-5 generated fixtures whose complete copied identities are recorded.
No prior build database or build products are copied.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 740 total: 731 passed, nine allowlisted opt-in skips |
| New Review range correction regression | Passed; exact required-test validation |
| Isolated mixed-backend transport | Two passed, no skips |
| Static analysis | `ANALYZE SUCCEEDED` |
| Source release preflight | All 61 checks passed |
| Script-validator gate | Passed |
| XCTest failures / expected failures / runtime warnings | Zero |
| Verification sleep | None observed |
| Final source and pinned package cache | Clean and unchanged |

[Proof summary](proof-summary.json), complete test details/summaries, exact
required-regression validation, analysis/preflight/validator logs, power
receipts and [source/fixture identity](source-and-fixture-identity.json) retain
the accepted run. Apps, DerivedData and complete result bundles remain under
`/private/tmp/aagedal-2-plan-resource-verification-20260930`; their external
file hashes are retained. Temporary storage is not a durable artifact archive.

The host is an arm64 MacBook Pro on macOS 27.0.1 (26A434) with Xcode 27.0
(27A266a). Shipping dependency revisions and app version 1.6.1 (163) remain
unchanged. The separate authentic bounded-MXF resource and GPL/Metal native
profiles retain their own candidate source and binary identities.

## Script-only independent-review follow-up

Independent review subsequently identifies and corrects two reimport-validator
gaps: malformed numeric arguments could preserve stale passing receipts, and
native lifetime peak did not cover all sampled resident observations. Commit
`61ce66f0c8b847b6b03818f723d653eb92906e0d` changes validation scripts/tests and
their documentation only. Thirteen focused regressions pass, and stricter
validation of the same original three-by-thirty authentic dataset produces
byte-identical resource receipts under unchanged budgets.

[Final source identity](final-script-and-app-source-identity.json) proves all
app/XCTest Swift sources and the package lockfile match the canonical Release
run. The final script-validator gate is retained separately in
`final-script-validator-tests.log.gz`; no additional app rebuild is attributed
to that script-only commit. The original canonical receipt is preserved.

Documentation retention follows both implementation commits. Release
consumption still requires the normal matching-HEAD checks. These development
results do not close public dependency publication/repin, native keyboard and
spoken accessibility, irregular DTS source timestamps, supported-macOS/base-M1,
30-minute/audible/device/surround, remaining editor or distribution gates.
