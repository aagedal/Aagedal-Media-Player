# Optimized candidate verification — 2026-09-30

The canonical `scripts/verify-release-candidate.sh` passed at clean source
commit `2d314c8b47c090555a99f19bc6dd890c40053d75`, including the final failed-profile
session cleanup. The exact `Package.resolved` SHA-256 was
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.
Package-cache revisions were validated before and after the run.

| Gate | Result |
| --- | --- |
| Script validators | All self-contained regressions and syntax checks pass |
| Optimized Release aggregate | 702 passed, eight allowlisted explicit skips, zero failures or runtime warnings (710 total) |
| Isolated mixed-backend transport | Both AVFoundation/MPV directions pass, zero skips or runtime warnings |
| Release static analysis | `ANALYZE SUCCEEDED` |
| Source release preflight | All 61 checks pass for version 1.6.1 (163) |
| Final identity | HEAD, clean checkout, resolved packages and cache revisions revalidated |

The run used fresh DerivedData, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a),
and normal build/test/signing-service access. Full logs, build products and
`.xcresult` bundles remain at `/private/tmp/aagedal-candidate-2d314c8-20260930`
and may be removed by the operating system. Machine-readable summaries/details,
validator results, environment and preflight evidence are copied here;
`evidence-sha256.json` records their hashes and those of external Xcode logs.

An earlier run against `c09e8aa` was interrupted after a later agent changed
the profiling test source. It supplies no passing candidate claim; this complete
replacement verifies the final implementation commit.

The eight optional skips are not acceptance passes. Generated selected-track
engineering smoke is recorded [separately](../live-meter-selected-tracks-20260929/README.md),
including unresolved audio-only mono/CoreAudio failures. This run does not
establish representative live-meter accuracy, MPV 1:1 source pixels, editor
round trips, native focus or spoken VoiceOver, base-M1 performance, representative
smoke, signing/notarization, or distribution. The evidence-report commit follows
the verified implementation, so its changed checkout does not inherit this
exact-source result.
