# Phase 124 — Current optimized candidate verification

The canonical `scripts/verify-release-candidate.sh` completed successfully on
2026-09-20 against clean commit `f8d8d0ec870ccc84e8ce8c58c951f9c076f89e86`.
This includes the Final Cut duration, geometry restriction, grouped findings,
and whitespace-disclosure changes through Phase 123.

| Gate | Result |
| --- | --- |
| Script validators | All self-contained Python regressions, syntax checks, and mocked comparison-profiler checks pass |
| Optimized Release aggregate | 690 passed, eight explicitly allowlisted skips, zero failures or runtime warnings (698 total) |
| Isolated mixed-backend transport | Both AVFoundation/MPV directions pass, zero skips or runtime warnings |
| Release static analysis | `ANALYZE SUCCEEDED` |
| Source release preflight | All 61 checks pass for version 1.6.1 (163) |
| Final identity | HEAD, resolved-package hash, clean source checkout, and pinned clean package-cache checkouts revalidated |

The run used macOS 27.0 (26A428), Xcode 27.0 (27A266a), fresh DerivedData,
and the verifier's validated local package-cache route. Xcode ran with normal
hosted-test, cache, and signing trust-service access. The build emits the
standard App Intents metadata-extraction warning because this app has no
AppIntents.framework dependency; no XCTest runtime warnings were reported.

The original full logs, fresh build products, and both `.xcresult` bundles are at
`/private/tmp/aagedal-phase124-candidate-20260920`. This directory retains copies
of the machine-readable summaries/details, validator outputs, preflight,
environment identity, and helper-test log. `evidence-sha256.json` records SHA-256
hashes of those files and the external Xcode logs. Temporary full artifacts may
be removed by the operating system; the copied evidence remains in this repository.

The eight skipped tests require opt-in disk exhaustion, official audio references,
or representative live-meter, loudness, metadata-memory, programme, and thumbnail
profiling inputs. Their explicit reasons are retained in `test-details.json`.
They are not acceptance passes. No editor, spoken VoiceOver, base-M1 performance,
representative-media smoke, archive, notarization, or distribution gate was run.

This result applies to the exact source commit above. Recording this report
changes the checkout; a later release must run the verifier again against its
final clean commit rather than reuse this evidence as a different revision's pass.
