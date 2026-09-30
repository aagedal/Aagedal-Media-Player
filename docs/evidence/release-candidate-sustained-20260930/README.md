# Sustained-acceptance 2.0 continuation — 2026-09-30

The canonical clean-checkout verifier passes at
`601bbb859c436037388c3d3c080cb0132b7e357d`, from 18:26:27 to 18:32:28
Europe/Oslo. Source, resolved-package and cached dependency identities are
unchanged at completion.

- 721 optimized Release tests pass, with eight documented optional skips
  (729 total). Detailed outcomes reconcile, with no failures, expected failures
  or runtime warnings. All three new Review endpoint regressions pass.
- Both isolated mixed-backend transport checks pass in a fresh serial runner.
- Release static analysis succeeds and all 61 source preflight checks pass.
- The complete script-validator gate passes, including 23 live-profile,
  12 dependency-builder and 15 release-script checks.
- Retained power evidence contains no sleep events.

This verifies Review clip-end rounding/overflow handling, long-observation
meter harness enablement, isolated dependency input-preservation guards and
release source identity checks. Candidate and release consumption now enforce
729 aggregate tests plus both isolated transport directions.

The canonical build uses the unchanged shipping MPVKit pin. The new locally
rebuilt dependency has its own [input-preservation receipt](../live-meter-native-output-20260930/incremental-rebuild/input-guard-rebuild-receipt.json);
its universal incremental rebuild preserves all 218 unrelated objects per
architecture. No native playback rerun is claimed for that new candidate.
Both older repaired candidates' retained profiles still pass the stronger
meter progress validator (nine aggregate rows, including authentic Sony).
That revalidation does not substitute a repaired dependency into this
canonical source run, establish a 30-minute soak, or close the shipping repair.

A bounded native inventory listed the player as stopped, but selecting Finder
hung and was cancelled. No new keyboard, Full Keyboard Access or spoken
VoiceOver acceptance is inferred. Immutable full MPVKit build/repin, sustained
representative-media/base-M1, MPV decoder-raster, editor and distribution gates
remain open.

Full build/test/analysis logs, result bundles and derived data remain at
`/private/tmp/aagedal-sustained-2-candidate-20260930`. The retained summaries,
detailed outcomes, validator/preflight logs, environment and power receipts
have SHA-256 identities in [evidence-sha256.json](evidence-sha256.json).
This record attests to the exact implementation commit above; its later
documentation-only retention commit is not the source of the verified app.
Release execution at a later HEAD still requires fresh matching verification.

```bash
AAGEDAL_CANDIDATE_PACKAGE_CACHE=/tmp/aagedal-itu-live-dd-20260930/SourcePackages \
  scripts/verify-release-candidate.sh /tmp/new-sustained-candidate
```
