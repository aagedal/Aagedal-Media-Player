# Authentic 2.0 continuation candidate verification — 2026-09-30

The canonical clean-checkout verifier passes at implementation commit
`1e8023258c7192b8c426ea42f5e64162b4890ca4`, from 20:37:03 to 20:42:42
Europe/Oslo. Final source, resolved-package and package-cache identities match.

- **725 optimized Release tests pass**, with eight documented optional skips
  (733 total), no failures, expected failures or runtime warnings. Every
  detailed result reconciles. A separate exact-count validator requires both
  new transport and both new Review correction regressions.
- Both isolated mixed-backend shared-transport tests pass in a fresh serial runner.
- Release static analysis succeeds and all 61 preflight checks pass.
- The complete script-validator gate passes, including thirteen clean-builder,
  twelve incremental-builder, fifteen release-script and twenty-three live-profile
  regression cases.
- Power evidence contains no sleep events.

This integrates Review correction ownership across fields/findings, authoritative
comparison Pause, explicit user transport during replacement loading, and
synchronization after delayed Play acknowledgement. The earlier canonical run's
mixed-backend paused-alignment failure passes here. Its failure, unchanged
isolated pass, two reproduced source bugs and focused corrected results remain
in [the transport evidence](../compare-paused-alignment-20260930/README.md).
No timing tolerance, skip allowance or test exclusion was relaxed. Consumption
requires 733 aggregate tests plus both isolated transport directions.

The candidate uses the **unchanged shipping MPVKit pin**. It verifies corrected
GPL/Metal prerequisite and artifact-receipt tooling, not a repaired shipping
framework. The [historical full-build audit](../live-meter-native-output-20260930/shipping-parity-audit/README.md)
finds GPL/Metal feature loss and the host's missing Metal compiler; the old local
artifact is rejected for shipping parity. A replacement, immutable public recipe
and artifact/package publication, repin and native output/hardware acceptance
remain open.

The [authentic meter observations](../../LIVE_AUDIO_METER_AUTHENTIC_NATIVE_CHECK_2026-09-30.md)
retain six passing rows on identified local candidates and an unexplained earlier
FX6 near-EOF synchronization failure. The
[camera metadata profiles](../authentic-camera-metadata-memory-20260930/README.md)
retain the transient FX6 memory cost and bounded-reader investigation; no bounded
reader implementation is claimed. The
[JXL test-only proposal](../jxl-contract-proposal-20260930/README.md) still needs
upstream reconciliation. Long-play/base-M1, keyboard/Full Keyboard Access/spoken
VoiceOver, remaining editor interoperability and signed/notarized distribution
acceptance remain open. The app still declares 1.6.1 (163).

Full logs, `.xcresult` bundles and fresh DerivedData remain at
`/private/tmp/aagedal-authentic-continuation-fixed-candidate-20260930`. Retained
summaries, details, validators, environment, preflight and power receipts have
hashes in [evidence-sha256.json](evidence-sha256.json). This report's later
retention commit is not the verified app source; release execution at a later
HEAD requires fresh matching verification.

```bash
AAGEDAL_CANDIDATE_PACKAGE_CACHE=/tmp/aagedal-itu-live-dd-20260930/SourcePackages \
  scripts/verify-release-candidate.sh /tmp/new-authentic-continuation-candidate
```
