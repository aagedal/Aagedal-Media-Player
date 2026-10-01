# Integrated passive Review and publication-integrity candidate — 2026-10-01

Canonical optimized Release verification passes at clean implementation commit
`bac4b10a3aaaa8d7a72487d157ecb3e84dcea640`, using fresh DerivedData and the
validated unchanged offline package cache.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 775 total: 766 passed, nine named opt-in skips |
| Three new passive Review regressions | Passed, required by exact identity |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Release static analysis | Passed |
| Release preflight | All 61 checks passed |
| Complete script-validator suite | Passed, including 19 Premiere and 18 release-script checks |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, XCTest runtime warnings, sleep | Zero |

[Proof summary](proof-summary.json), exact test summaries/details, compressed
logs, environment, power receipts and [source hashes](source-sha256.json)
retain the accepted result. Full xcresult bundles and built products remain at
`/private/tmp/aagedal-passive-review-canonical-20261001`; temporary storage is
not a durable binary archive. The unchanged package lockfile SHA-256 is
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

The implementation uses live correction ownership for all passive Review text
and range exit callbacks, rejects disabled/ambiguous Premiere playback evidence,
and binds release signing/publication checks to the original packaged ZIP hash.
See [focused engineering receipts](../passive-review-release-integrity-20261001/README.md).
Publication checks cannot undo a completed upload and establish identity at
boundaries, rather than atomicity against concurrent transient swaps.

A [native Premiere attempt](native-premiere-attempt.md) reached a disposable
project and the Import picker but failed path navigation; the delegated follow-up
binding returned no UI state and was canceled. No native interchange acceptance
or returned XML is inferred.

Native editor/accessibility, public dependency publication/repins,
audible/device/surround, hardware/soak/base-M1 and signing/notarization/distribution
gates remain open. Avid is optional for 2.0. Subsequent evidence retention does
not replace matching-HEAD release consumption; the accepted source commit above
stays explicit. No remote release was published during this continuation.

Later validation on October 1 reused this temporary `DerivedData` for the
range/decoder/field-order continuation. Its current built products therefore
no longer represent `bac4b10`; the original result bundles and retained
summaries/logs above remain the evidence for that historical source. The new
canonical candidate uses a separate output directory.
