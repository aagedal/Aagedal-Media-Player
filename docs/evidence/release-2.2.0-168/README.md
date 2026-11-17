# Aagedal Media Player 2.2.0 (168)

[Stable release](https://github.com/aagedal/Aagedal-Media-Player/releases/tag/2.2.0)
ships source commit `72a9b8a765d49bf36044b4884e81d20026cce6bf`, built for
arm64 with MPVKit `3b3748b8a488608598fbde73e70e8cf9bf7097c4`
(`aagedal-1.1.0-n9.0.2-mpv0.42.1`), SwiftMediaMetadata 3.1.4 and the
2026-11-16 FFmpeg 9.0.2 full build.
[Release receipt](release-receipt.json) binds the distribution ZIP, appcast and
source/package identity. The GitHub asset is 50,493,652 bytes with SHA-256
`672b8095a365289ce2f1fc5fdd1708697eb5859762fc67836ccec1a132b8f402`.

## Acceptance

- Canonical Release suite: **967 passed**, zero failures/runtime warnings, and
  20 named opt-in skips. Every required regression passed.
  [Summary](test-summary.json), compressed details and validation log are retained.
- Fresh serial mixed-backend transport: **2 passed**, zero failures/skips/warnings.
  This makes 969 executed passing XCTest cases across the two result bundles.
- **31 script-validator suites**, optimized static analysis, all **93 source
  preflight checks**, source identity checks and awake-host verification pass,
  without a package cache.
- Developer ID export and exact ZIP extraction each pass **105 checks**. Apple
  notarization is **Accepted**, submission `fc33d8b8-5c7b-45b6-85fa-4c245e4bc6b5`.
  The extracted app's staple validates; Gatekeeper reports `accepted`,
  `source=Notarized Developer ID`. The published-state preflight against the
  extracted app passes **113 checks**.
- GitHub release target, stable state, uploaded ZIP byte size and GitHub-computed
  SHA-256 match the tested source and local distribution. The appcast enclosure
  URL returns HTTP 200.
- Homebrew cask publication is pending; `homebrewCommit` is null.

The candidate was verified once, in a clean detached checkout of the merge
commit with freshly generated fixtures; no attempt was rejected.

This is current-host generated-media and source-level release evidence.
Physical HDR, producer-authentic long-media, older-host and performance gates
remain separate work.
