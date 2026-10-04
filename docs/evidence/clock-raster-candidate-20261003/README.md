# Comparison clock and decoder-raster continuation — 2026-10-03

Canonical optimized Release verification passes at clean implementation commit
`179aaaea442968f7fe4f0bad2167d1ec5701ace0` with fresh DerivedData and the
validated exact published package cache. Code changes were committed at
`4c7e0ef8744aeb7979c9fa0123d360dd3b5a7702`; the second commit corrects the
aggregate test floor after accounting for a renamed resize regression.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 838 total: 829 passed, nine named opt-in skips |
| Required regressions | All 84 aggregate identities passed |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Release static analysis | Passed |
| Source release preflight | All 61 checks passed |
| Script validators | Passed, including candidate/release regression-list parity |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, runtime warnings, sleep | Zero |

Comparison synchronization now reads A/B/A after transport work, accounting for
secondary property-read latency and rejecting nonfinite derived drift. Three
new deterministic tests cover delayed synchronized clocks, real signed drift
with alignment/reverse clocks, and invalid/extreme inputs. A separate focused
Release run passes 38 mapping/lifecycle tests without skips or runtime warnings.
This does not establish an improvement over the earlier measured UHD drift;
repeat the scope/loupe/native comparison matrix before claiming acceptance.

The decoder consumer now requires BGRA, bounded axes/pixel count/stride and exact
buffer size before copying. All eight focused decoder tests pass, including two
new malformed/oversized response regressions and valid padded-row acceptance.
The shipping MPVKit still has no decoder-raster provider; source-pixel inspection
remains an engineering gate. No provider patch, package pin or activation changed.

Candidate and release scripts also require the merged split-mono programme and
settled resize/surface-recovery regressions. One existing resize test was renamed,
so these contribute seven new tests, plus five new clock/protocol tests: the
previous 826 aggregate floor becomes 838. The first run passed the same 829 tests
and nine skips but rejected the erroneously set 839 floor; its environment,
summary and rejection are retained as `initial-*`. It stopped before isolated
transport/analysis and is not canonical passing evidence.

Full result bundles, logs and build products remain at
`/private/tmp/aagedal-2-plan-candidate-final-20261003`. Temporary storage is not
a durable binary archive. Artifact hashes are retained in
[artifact-identities.json](artifact-identities.json). Existing compilation notices
include skipped AppIntents extraction and an unrelated weak-variable mutability
warning; there are no XCTest runtime warnings. The later documentation commit
does not replace matching-HEAD release consumption. No release was published.

Remaining manual/native checks are listed in
[manual completion](../../RELEASE_2_MANUAL_COMPLETION.md): real-device audio,
visual drift, resizing/fullscreen, keyboard review, editor round trips, long
meter observation and signed distribution. Spoken VoiceOver and base-M1
qualification remain explicitly open/deferred.
