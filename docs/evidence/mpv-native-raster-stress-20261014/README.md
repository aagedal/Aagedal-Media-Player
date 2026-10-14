# Native raster: repeated UHD/HDR app lifecycle validation

The arm64 Release development app was built from current sources using the
checksum-verified restored MPVKit bundle. No MPVKit source or binaries were
rebuilt or republished. Shipping package pins and the default-off provider gate
are unchanged.

The consumer now rejects inconsistent oriented raster dimensions before copying
the provider's potentially 72 MiB payload. A regression uses an unreadable data
pointer with inconsistent geometry to verify rejection precedes any pixel read.

## Results

- [66 consumer/loupe tests](regressions-summary.json): passed, no skips.
- [Hosted fixture test](hosted-summary.json): passed all 20 positive native cases,
  including independent pixel references, orientation, color tags, hardware
  transfer, seeks, cached-image reuse, and resume revocation.
- [Stress test](stress-summary.json): passed six cycles of all ten UHD/DCI/HDR
  cases, totaling 60 load/capture/seek/resume/teardown lifecycles and 180 rapid
  loupe close/reopen sequences. Each sequence also stops and immediately restarts
  a capture to exercise rejection of obsolete work.

[Cycle-end physical footprint](stress-acceptance.txt), in MiB:
1034.1, 815.2, 766.9, 788.8, 847.6, 471.6. All five post-warmup samples remain
below the first complete cycle. The growth limit was fixed at 256 MiB above
warmup before running the test; it was not relaxed after observing the results.
The fixture harness releases its retained Metal surfaces after each case.

The [candidate receipt](candidate-receipt.json) records arm64 architecture,
successful code-signature verification, and hashes of changed source files,
the runner, app executable, and hosted test executable. Compressed build and
hosted/stress logs are retained alongside the summaries.

## Test build and reproduction

The locally signed development app and opt-in launcher are at
`build/native-raster-candidate-20261014/` in the source worktree (ignored build
output). Use `Launch Native Raster Candidate.command`; opening the app directly
keeps native inspection disabled. This is not a notarized shipping update.

Follow the [restore/build handoff](../../MPV_NATIVE_RASTER_HANDOFF.md), then use
`scripts/validate-mpv-native-app.py` with the generated xctestrun, rebased fixture
manifest, and a new output directory. Run once without `--stress-cycles` for all
20 cases and once with `--stress-cycles 6` for repeated UHD/HDR lifecycles.
The runner requires a successful XCTest exit and the appropriate action-log
acceptance marker; a stock preview-only pass does not qualify.

These are bounded generated-fixture checks on macOS 27.0.1. Cycle-end process
footprint does not establish peak memory, per-allocation ownership, long-duration
stability, sanitizer acceptance, arbitrary-media coverage, or physical HDR
display calibration. Those remain further qualification work.
