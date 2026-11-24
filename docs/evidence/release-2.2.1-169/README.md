# Aagedal Media Player 2.2.1 (169)

[Stable release](https://github.com/aagedal/Aagedal-Media-Player/releases/tag/2.2.1)
ships source commit `928e488923f46a502964b20fb0805a7f9f9d21af`, built for
arm64 with MPVKit `3b3748b8a488608598fbde73e70e8cf9bf7097c4`
(`aagedal-1.1.0-n9.0.2-mpv0.42.1`), SwiftMediaMetadata 3.1.4 and the
2026-11-16 FFmpeg 9.0.2 full build.
[Release receipt](release-receipt.json) binds the distribution ZIP, appcast and
source/package identity. The GitHub asset is 50,502,327 bytes with SHA-256
`aa2a724a74331f82d057a908ee5495c9f4f7f09e4488bd285ad0ee10e2858cf1`.

## Acceptance

- Canonical Release suite: **972 passed**, zero failures/runtime warnings, and
  20 named opt-in skips. Every required regression passed.
  [Summary](test-summary.json), compressed details and validation log are retained.
- Fresh serial mixed-backend transport: **2 passed**, zero failures/skips/warnings.
  This makes 974 executed passing XCTest cases across the two result bundles.
- **31 script-validator suites**, optimized static analysis, all **101 source
  preflight checks**, source identity checks and awake-host verification pass,
  using the verified local SwiftPM package cache matching `Package.resolved`.
- Developer ID export and exact ZIP extraction each pass **113 checks**. Apple
  notarization is **Accepted**, submission `45b45e5f-af90-4662-a0bb-2bef8a02ea48`.
  The extracted app's staple validates; Gatekeeper reports `accepted`,
  `source=Notarized Developer ID`. The published-state preflight against the
  extracted app passes **121 checks**.
- GitHub release target, stable state, uploaded ZIP byte size and GitHub-computed
  SHA-256 match the tested source and local distribution. The appcast enclosure
  URL returns HTTP 200.
- Homebrew cask publication is pending; `homebrewCommit` is null.

The candidate was verified once on the clean merge commit with freshly generated
fixtures; no attempt was rejected.

This is current-host generated-media and source-level release evidence.
Physical HDR, producer-authentic long-media, older-host and performance gates
remain separate work.
