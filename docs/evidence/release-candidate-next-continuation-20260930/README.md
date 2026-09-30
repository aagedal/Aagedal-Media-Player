# Integrated 2.0 continuation — 2026-09-30

The canonical optimized Release verifier passes for clean implementation commit
`4c91fe3e27b7d1af52adb94bc7c8ed0d76142443`, using fresh DerivedData, the validated
unchanged offline package cache and existing generated fixtures. No previous
build products or build database are reused.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 750 total: 741 passed, nine named opt-in skips |
| Three Review / two PDF regressions | All passed; required-test detailed validation |
| Isolated mixed-backend transport | Two passed, no skips |
| Release static analysis | Passed |
| Release preflight | All 61 checks passed |
| Script validators | Passed, including reconstruction audit regressions |
| Final source/package/cache identity | Passed |
| Sleep, test failures, expected failures, runtime warnings | Zero |

[Proof summary](proof-summary.json), exact result summaries/details, compressed
logs, power/environment receipts and [source hashes](source-sha256.json) retain
the accepted run. Complete `.xcresult` bundles and built products remain at
`/private/tmp/aagedal-2-plan-next-canonical-20260930`; temporary storage is not a
durable binary archive. The package lockfile SHA-256 is
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

The separate [focused Review/PDF check](../review-pdf-availability-20260930/README.md)
passes sixty Release tests and visually checks all three PDF fixture pages.
The [reconstruction audit](../coreaudio-reconstruction-audit-20260930/README.md)
passes 11,089 declared source files and twenty cached inputs. The
[lossless DTS preparation](../live-meter-dts-lossless-preparation-20260930/README.md)
qualifies unchanged codec payload/PCM on a new source clock and passes a separate
twenty-second production observation using independently identified retained
GPL/Metal candidate binaries. It is not attributed to this canonical app build.

This batch fixes unavailable Review focus/blur and PDF identity without closing
native keyboard/Full Keyboard Access/spoken VoiceOver, original-container DTS,
public dependency publication/repin, audible/device/surround/soak/base-M1,
remaining editor or distribution acceptance. Subsequent evidence/documentation
commits retain this result; normal release consumption still requires evidence
matching its exact HEAD and package identity.
