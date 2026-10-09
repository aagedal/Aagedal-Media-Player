# Integrated loudness and current release regressions — 2026-10-09

The new integrated live-loudness field was omitted from snapshot validation.
NaN and positive infinity could reach presentation while the other loudness
fields were rejected. It now follows the same validation as momentary and
short-term readings: invalid values fail the generation, clear its snapshots
and cancel the worker. Negative-infinite silence and absent warmup readings
remain valid.

Focused optimized Release verification passes all 142 tests in the coordinator,
DSP, decoder, meter session, loudness analysis, programme loudness and loupe
state suites, with zero failures, skips or runtime warnings. The new regression
checks both NaN and positive infinity, snapshot removal and worker cancellation;
the existing silence regression now also checks integrated negative infinity.
The standard build emits the AppIntents metadata-extraction notice because this
app has no AppIntents dependency.

Both canonical verification and release consumption now require twelve recent
loupe/meter/graph/grouping test identities and at least 849 aggregate tests.
All 19 release-script checks, the complete script-validator suite, shell syntax
checks and all 61 release-preflight checks pass. Signature verification requires
execution outside this workspace sandbox; the ordinary sandboxed preflight
reported a signature failure, while its unchanged unsandboxed repeat passes.

Pinned package checkouts were copied to a temporary cache and checked against
Package.resolved before the focused build. The first sandboxed Xcode attempt
stopped at compiler-cache permissions; the completed run used standard Xcode
permissions with automatic package resolution disabled.

Retained summary, details and source hashes identify this focused batch.
The full result bundle and logs remain at
`/private/tmp/aagedal-2-plan-focused-retry-20261009.xcresult`,
`/private/tmp/aagedal-2-plan-focused-retry-20261009.log`,
`/private/tmp/aagedal-2-plan-script-tests-20261009.log` and
`/private/tmp/aagedal-2-plan-preflight-unsandboxed-20261009.log`.
Temporary storage is not a durable archive. No new matching-HEAD full canonical,
shipping MPV source-pixel, native meter/device or sustained-soak acceptance is
claimed.
