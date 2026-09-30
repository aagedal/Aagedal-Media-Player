# Integrated parallel 2.0 continuation — 2026-09-30

The canonical clean-checkout verifier passes at
`88e8bdbfaacb1136770a9d6fcbb88296c8d0608b`, from 17:23:48 to 17:29:16
Europe/Oslo. Source, resolved-package and cached dependency identities are
unchanged at completion.

- 718 optimized Release tests pass, with eight documented allowlisted optional
  skips (726 total). Detailed outcomes reconcile; no failures, expected failures
  or runtime warnings occur.
- Both isolated mixed-backend transport checks pass in a fresh serial runner.
- Release static analysis succeeds and all 61 source-tree preflight checks pass.
- Script-validator tests pass, including the six new dependency-builder safety
  checks and sixteen authentic peak calculator/validator checks.
- Retained power evidence contains no sleep events.

This integrates the Review correction-focus fix, typed/overflow-safe MPV
screenshot parser, authentic live peak reference tooling and local dependency
candidate builder. Verification and release consumption now enforce a floor of
726 aggregate tests plus the two isolated transport checks.

The canonical build uses the unchanged pinned MPVKit dependency. The separately
linked local CoreAudio repair's nine passing production-profile rows are
[distinct candidate evidence](../live-meter-native-output-20260930/incremental-rebuild/README.md),
and are not substituted into this clean-source run. Shipping dependency repin,
MPV decoder-raster capture, native keyboard/spoken accessibility, editor and
release-floor hardware/distribution gates remain open. The native Mac inventory
was locked; no new UI acceptance is claimed.

Full build/test/analysis logs, both result bundles and derived data remain at
`/private/tmp/aagedal-parallel-2-candidate-20260930`. The retained summaries,
detailed outcomes, validator/preflight logs, environment and power receipts have
SHA-256 identities in [evidence-sha256.json](evidence-sha256.json). This record
attests to the exact source commit above; its later documentation-only retention
commit is not the source of the verified app.

```bash
AAGEDAL_CANDIDATE_PACKAGE_CACHE=/tmp/aagedal-itu-live-dd-20260930/SourcePackages \
  scripts/verify-release-candidate.sh /tmp/new-parallel-2-candidate
```
