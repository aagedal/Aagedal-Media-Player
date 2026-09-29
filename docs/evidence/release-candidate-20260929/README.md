# Current optimized candidate verification — 2026-09-29

The canonical `scripts/verify-release-candidate.sh` completed against the
clean source commit `2730a4b6d122e19a4ae3aadc4df73ae61d6c71e6` after
Phases 140–143. The verifier used the exact `Package.resolved` SHA-256
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`
and validated the local package-cache revisions before and after the run.

| Gate | Result |
| --- | --- |
| Script validators | All self-contained regressions and syntax checks pass |
| Optimized Release aggregate | 699 passed, eight allowlisted explicit skips, zero failures or runtime warnings (707 total) |
| Isolated mixed-backend transport | Both AVFoundation/MPV directions pass, zero skips or runtime warnings |
| Release static analysis | `ANALYZE SUCCEEDED` |
| Source release preflight | All 61 checks pass for version 1.6.1 (163) |
| Final identity | HEAD, `Package.resolved`, clean checkout and package-cache revisions revalidated |

The run used macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), fresh DerivedData
and normal macOS build, test and signing-service access. The complete logs,
build products and `.xcresult` bundles remain at
`/private/tmp/aagedal-candidate-2730a4b-20260929`. This directory may be
removed by the operating system. The machine-readable XCTest summaries and
details, validator results, environment identity and preflight result are
copied here. `evidence-sha256.json` records the hashes of both the copied
files and the three external Xcode logs.

The eight skips are documented optional-input tests, not acceptance passes.
This run does not establish producer-authentic live-meter accuracy, editor
marker round trips, spoken VoiceOver, base-M1 performance, representative
media smoke, signing/notarization or distribution. This report is evidence for
the exact source commit above; adding this report changes the checkout, so a
future final release candidate needs a new clean-checkout verification.
