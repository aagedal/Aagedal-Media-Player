# Sustained different-file comparison: qualification rejected

The later [rate-following continuation](../mpv-loupe-rate-scope-demand-20261016/README.md)
passes a fresh three-cycle, 30-second-per-mode run with unchanged gates. This
document and its receipts retain the earlier rejected candidate's results.

The arm64 Release candidate completed three cycles of both different-file
SDR/PQ and PQ/HLG UHD60 pairs in side-by-side, vertical wipe and overlay modes,
with at least 30 measured seconds per mode per pair. The hosted XCTest failed
two 100 ms follower-drift assertions: source B reached 133.3 ms and 166.7 ms in
the first two side-by-side windows of the first SDR/PQ pair. This is **not** an
accepted sustained comparison candidate. The runner correctly returned failure
even though the test printed its end-of-run completion marker.

The [measurements](measurements.txt) contain 358 loupe windows. Minimum completed
Metal presentation cadence was 58.94 fps (requirement: 45). There were 10,739
usable clock samples out of 10,740; every window met the 29/30 requirement.
Screenshot workers remained idle during measured playback. All repeated
paired pause/native-raster seek, close/reopen, decoder/color configuration and
lifecycle assertions passed. These passing checks do not override the drift
failures. The [XCTest summary](summary.json) records one failed test, no skips.

Cycle-end physical footprints were 856,115,480; 919,456,192; and 728,877,384 bytes.
Maximum growth above the first complete warmup cycle was 63,340,712 bytes
(60.41 MiB), within 256 MiB. Highest sampled in-playback footprint was
1,857,718,984 bytes (1.73 GiB). Samples do not measure peak allocation or impose
a total-memory ceiling.

## Reproduce and evidence

Restore the verified bundle and build the current sources for arm64 testing
using [the handoff](../../MPV_NATIVE_RASTER_HANDOFF.md), then run:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/new-comparison-soak \
  --comparison --soak-seconds 30 --soak-cycles 3
```

The [candidate receipt](candidate-receipt.json) records source, binary, fixture
and bundle hashes plus measured results and the explicit rejected status. The
app executable is arm64 only, its strict/deep signature verification passes,
and MPVKit was restored without compilation. Shipping pins and the provider's
default-off gate are unchanged. Seven runner checks and eighteen release-result
validator checks pass. The candidate and full result remain at:

- `/private/tmp/aagedal-comparison-soak-derived-20261015/Build/Products/Release/Aagedal Media Player.app`
- `/private/tmp/aagedal-comparison-soak-validation-v2-20261015/tests.xcresult`

Compressed build, restore, action and XCTest stdout logs are retained beside
this document. The initial run used synchronous main-actor clock reads and was
interrupted after drift and screenshot-worker failures. Its logs are retained
as `initial-interrupted-*`; they are diagnostic evidence, not a completed soak.
The completed run moves measurement reads to a detached task, matching the
existing concurrent-viewer sampler, and keeps all acceptance limits unchanged.
The first run's additional failures cannot be attributed solely to measurement
without further investigation.

## Remaining work and limits

Investigate cold-start and comparison-loop source/follower synchronization,
including source B's first two measured windows. The live follower currently
allows a larger drift before hard correction than this acceptance limit, and
hard correction can temporarily withdraw readiness and enable capture fallback;
these code paths warrant investigation, not an unverified diagnosis. Preserve
the strict drift and idle-worker gates while addressing the failure, then rerun
all three cycles with fresh evidence.

Inputs are generated six-second looped UHD60 clips. The production comparison
canvas is hosted at 960×540; counters measure lenses, not canvas cadence or
unique video frames. This does not qualify composite pixels, A/B frame lock,
active scopes, producer-authentic long files, sanitizers, physical HDR, other
machines or long-duration release performance. MoltenVK teardown diagnostics
remain in the retained logs.
