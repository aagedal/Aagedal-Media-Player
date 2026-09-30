# Awake optimized candidate verification — 2026-09-30

The canonical `scripts/verify-release-candidate.sh` passed at clean commit
`61b2d0e9a4001a320cd1bb9e4cb44e245570cbf1`. The exact `Package.resolved`
SHA-256 was `6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.
The pinned package cache was validated before and after the run.

| Gate | Result |
| --- | --- |
| Script validators | All self-contained regressions and syntax checks pass |
| Optimized Release aggregate | 705 passed, eight documented optional skips, zero failures/runtime warnings (713 total) |
| New loupe track/composition cases | All three passed in the aggregate |
| Isolated mixed-backend transport | Both required directions passed, zero skips/runtime warnings |
| Release static analysis | `ANALYZE SUCCEEDED` |
| Source-tree preflight | All 61 checks passed for 1.6.1 (163) |
| Power interval | 13:21:51–13:27:04 Europe/Oslo; full wake at start, no sleep |
| Final identity | Exact HEAD, clean checkout, resolved packages and cache revisions revalidated |

The runner used fresh DerivedData, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a),
and normal build/test/signing service access. It held scoped macOS power
assertions and released them on exit. Its no-sleep check passed before final
source identity and `status=passed` were recorded. Each isolated transport test
had a 120-second execution allowance; synchronization tolerances were unchanged.

This replaces the earlier [sleep-interrupted attempt](../release-candidate-sleep-interrupted-20260930/README.md),
whose aggregate passed but both transport checks failed during long system
sleeps. The failed attempt is retained as diagnosis and supplies no candidate
pass. No transport code or tolerances were changed in response to it.

Full logs, build products and result bundles remain at
`/private/tmp/aagedal-candidate-61b2d0e-awake-20260930` and may be removed by the
operating system. Copied machine-readable summaries/details, environment,
validator results, power events and preflight are retained here;
`evidence-sha256.json` records their hashes and those of external Xcode logs.

The eight optional skips are not acceptance passes. Native mono/stereo audio
output remains [unresolved](../../LIVE_AUDIO_METER_NATIVE_OUTPUT_DIAGNOSIS_2026-09-30.md).
MPV source pixels, representative-media/reference accuracy, native keyboard and
spoken VoiceOver, editor/hardware/performance and distribution gates remain open.
The bounded native Review inventory returned that the Mac was locked and
could not be automatically unlocked; no app identity or interaction was verified.
This evidence-report commit follows the verified commit, so later release
execution still requires fresh exact-HEAD candidate verification.
