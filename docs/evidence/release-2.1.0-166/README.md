# Aagedal Media Player 2.1.0 (166)

[Stable release](https://github.com/aagedal/Aagedal-Media-Player/releases/tag/2.1.0)
ships source commit `bc5ba4a47c62c897bb5c4dd67d3ad1e5129b165b`, built for
arm64 with the unchanged shipping package pins and default-off native provider.
[Release receipt](release-receipt.json) binds the distribution ZIP, appcast,
source/package identity and Homebrew commit. The GitHub asset is 46,781,492 bytes
with SHA-256 `0f6363426a3685816ab33bb034fc4bba9da0759f22ccff91812cd8f89990bca8`.

## Acceptance

- Canonical Release suite: **941 passed**, zero failures/runtime warnings, and
  20 named opt-in skips. The skips require external/reference/performance inputs
  or separate experimental native-scope/audio-filter providers, not ordinary
  playback or LUFS coverage. Every required LUFS and AV output-retention regression
  passed. [Summary](test-summary.json), compressed details and validation log are retained.
- Fresh serial mixed-backend transport: **2 passed**, zero failures/skips/warnings.
- **30 script-validator suites**, optimized static analysis, all **77 source
  preflight checks**, source/cache identity checks and awake-host verification pass.
  See the canonical environment and compressed logs. This makes 943 executed
  passing XCTest cases across the two canonical result bundles.
- Developer ID export and exact ZIP extraction each pass **89 checks**. Apple
  notarization is **Accepted**, submission `3606bd38-2b2e-420f-bf5f-997ece4c7202`.
  Both original and extracted app staples validate; Gatekeeper reports
  `accepted`, `source=Notarized Developer ID`. The signed feed passes **85 checks**.
- GitHub release target, stable state, uploaded ZIP byte size and GitHub-computed
  SHA-256 match the tested source and local distribution. Homebrew version/SHA
  publication is committed at `72a2e2183fba4682882c9bb928353e8db2ecb08c`.

The public release includes the maintainer-accepted LUFS waveform graph and its
left-aligned menu, waveform/Playback-sidebar improvements and default live MPV
loupe playback. Final validation also fixed unnecessary AVFoundation output
removal when switching scope display requirements. AVFoundation's output format
is unchanged by that flag; retaining it avoids interrupting the decode pipeline.
The new retention regression is required by candidate verification and release
consumption. No synchronization/cadence tolerances were relaxed.

## Retained rejections

The first canonical attempt at `1714806` records **936 passes, four failures and
20 opt-in skips**. The four mixed-backend scope/loupe fixtures expected simultaneous
A/B samples while default A selection now intentionally suspends unselected B.
The fixtures now request difference inputs for that initial checkpoint and count
actual publications while each source is requested, rather than reading only a
possibly retired payload at the end. Scope coverage/freshness gates remain.

The first corrected-fixture focused run passes three of four cases but rejects
AV-primary loupe profiling on clock advance; an unchanged-build repeat rejects
it again. Those logs are retained. Switching display requirements repeatedly
removed/recreated the AV output even though AV capture uses the same output in
all scope modes. The subsequent production output-retention fix passes all ten
focused comparison/scope checks with no skips/warnings, then the complete fresh
canonical run above. The rejected attempts were never consumed by release.sh.

The missing-xctestrun repeat invocation failed before running tests; the actual
unchanged-build repeat used `xcodebuild test` with the existing DerivedData and
has its separate rejection log. No result from that failed invocation is counted.

This is current-host generated-media and source-level release evidence. Earlier
native-provider memory rejections, detached-host survival, physical HDR,
producer-authentic long-media, older-host and dependency sanitizer qualification
remain separate work. This release does not enable or ship the experimental
native-provider development bundle.
