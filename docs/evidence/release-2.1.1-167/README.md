# Aagedal Media Player 2.1.1 (167)

[Stable release](https://github.com/aagedal/Aagedal-Media-Player/releases/tag/2.1.1)
ships source commit `b5ad6265b83660620e355f4d112185ec1c0f77a9`, built for
arm64 with MPVKit `f957f4830d449e80723554cdc05ddc4138c1806e`
(`aagedal-1.1.0-n9.0.2-resize.1`) and the default-off native provider.
[Release receipt](release-receipt.json) binds the distribution ZIP, appcast and
source/package identity. The GitHub asset is 46,952,489 bytes with SHA-256
`1ceb31b8e7753cf71fe4d355e54f733392bf0354bd28213b9354d4fb641b83b8`.

## Acceptance

- Canonical Release suite: **943 passed**, zero failures/runtime warnings, and
  20 named opt-in skips. Every required regression passed, including the
  in-place MPV surface resize checks and the pinned-libmpv
  `moltenvk-surface-size` check added for this release.
  [Summary](test-summary.json), compressed details and validation log are retained.
- Fresh serial mixed-backend transport: **2 passed**, zero failures/skips/warnings.
  This makes 945 executed passing XCTest cases across the two result bundles.
- **31 script-validator suites**, optimized static analysis, all **85 source
  preflight checks**, source identity checks and awake-host verification pass,
  without a package cache.
- Developer ID export and exact ZIP extraction each pass **97 checks**. Apple
  notarization is **Accepted**, submission `8d55461f-a29a-42f0-ba47-e96b0a7845c7`.
  Both original and extracted app staples validate; Gatekeeper reports
  `accepted`, `source=Notarized Developer ID`. The published-state preflight
  against the extracted app passes **105 checks**.
- GitHub release target, stable state, uploaded ZIP byte size and GitHub-computed
  SHA-256 match the tested source and local distribution. The appcast enclosure
  URL returns HTTP 200.
- Homebrew cask publication is pending; `homebrewCommit` is null.

The release replaces the reload-on-rescale MPV workarounds with in-place
swapchain resizing from the MoltenVK layer-resize MPVKit build. The maintainer
checked window, fullscreen, inspector, comparison and live-loupe resizing in a
Debug build before the candidate was selected.

## Retained rejections

Two canonical attempts were rejected before any XCTest ran:

- At `08f8538`, the script-validator self-tests failed because the
  required-test lists still named four renamed MPV surface tests
  ([log](rejected-required-test-names-script-validator-tests.log.gz)). The lists
  were updated and the libmpv surface-size check made required.
- At `a3f2c71`, the verifier expanded an empty package-cache array under
  `set -u`, which macOS Bash 3.2 rejects; the evidence step then failed closed
  ([log tail](rejected-empty-cache-args-verifier-tail.log.gz)). `b5ad626`
  expands the optional arguments only when set.

Neither rejected attempt was consumed by release.sh.

This is current-host generated-media and source-level release evidence.
Physical HDR, producer-authentic long-media, older-host and performance gates
remain separate work.
