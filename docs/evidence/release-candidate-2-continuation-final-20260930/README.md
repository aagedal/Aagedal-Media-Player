# Integrated 2.0 continuation Release verification — 2026-09-30

The canonical clean-checkout verifier passed at
`7bccab4f619eb88f7a1ad08de1c6fddf9e8943d9` between 15:52:40 and 15:58:01
Europe/Oslo. The package-resolved SHA-256 is
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

- 707 optimized Release tests passed; eight named, allowlisted opt-in cases
  skipped (715 aggregate outcomes), with zero failures or runtime warnings.
- Both isolated mixed-backend transport directions passed in the fresh serial
  repeat, without changing synchronization tolerances.
- Release static analysis and all 61 source-tree preflight checks passed.
- The self-contained script-validator suite passed.
- Retained power evidence reports no sleep. HEAD, the clean checkout, resolved
  packages and pinned package-cache revisions were revalidated before passing.

The aggregate includes both new Review range-correction tests and the extended
real-controller persistence case. The authentic ITU reference test remains an
explicit optional skip in this ordinary candidate run; its actual passing
Release result is retained separately in
[the 4,896-window programme check](../live-meter-itu-windows-20260930/README.md).
Metadata recovery and native output diagnosis likewise retain separate media
and failure evidence; this canonical result does not turn those into completed
external acceptance gates.

The environment, complete detailed outcomes, summaries, validator/preflight
reports, power interval and log hashes are retained here. Full build/test logs
and result bundles remain at
`/private/tmp/aagedal-2-continuation-final-candidate-20260930`.

```bash
AAGEDAL_CANDIDATE_PACKAGE_CACHE=/tmp/aagedal-itu-live-dd-20260930/SourcePackages \
  scripts/verify-release-candidate.sh /tmp/new-continuation-candidate
```

This evidence-report commit follows the verified implementation commit. Later
commits require their own exact-HEAD candidate verification for distribution.
MPVKit repair/rebuild, original historical XMP, upstream JXL reconciliation,
editor/native accessibility, representative delivery/hardware and distribution
acceptance remain open.
