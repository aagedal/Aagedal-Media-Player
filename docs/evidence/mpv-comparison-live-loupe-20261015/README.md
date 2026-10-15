# Different-file UHD/HDR comparison loupe acceptance

The arm64 Release candidate passes the production comparison canvas and paired
live-loupe integration check. The hosted test mounts `ComparePlayerView` and
`InspectionLoupeOverlay`, driven by `CompareSessionController`, with different
SDR/PQ and PQ/HLG UHD60 files. Both pairs pass side-by-side, vertical wipe and
overlay playback, paired native-raster pause/seek, and loupe close/reopen.

All 12 three-second loupe measurements deliver at least 58.99 completed Metal
presentations per second (requirement: 45). Maximum source-to-follower effective
clock drift is 33.34 ms (limit: 100 ms); all 360 clock samples are usable. Both
source decoders and followers report VideoToolbox, decoded dimensions are
3840×2160, and each lens belongs to its own A/B controller with matching output
color tags. Followers are silent and their native-raster caches remain disabled.
Both screenshot workers remain idle during measured live playback.

Pausing restores verified native rasters for both sources. A paired seek to one
second replaces both images and verifies their current raster provenance.
Resuming restores live output. Closing destroys both follower contexts while
leaving the source contexts alive; reopening makes both lenses ready again.
The [acceptance output](acceptance.txt) records cadence and drift; the
[XCTest summary](summary.json) records one passing test with no failures/skips.
All six runner checks and seventeen release-result validator checks also pass.

## Reproduce

Follow the [native-raster handoff](../../MPV_NATIVE_RASTER_HANDOFF.md) to restore
the checksummed development bundle and build the current sources for testing.
The candidate was verified and reused without compiling MPVKit. Shipping pins
and the native provider's default-off gate are unchanged. The test runner
activates the candidate only in a temporary xctestrun copy.

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/new-comparison-loupe-check --comparison
```

The [candidate receipt](candidate-receipt.json) binds source hashes, binary
hashes, fixture hashes, bundle descriptor, architecture and host. Build, restore,
XCTest and action logs are retained as compressed files. The candidate app is
at `/private/tmp/aagedal-comparison-loupe-derived-20261015/Build/Products/Release/Aagedal Media Player.app`;
its strict/deep code-signature verification passes. The full result bundle is
at `/private/tmp/aagedal-comparison-loupe-validation-20261015/tests.xcresult`.

## Limits and remaining work

Inputs are generated six-second UHD60 clips, looped during playback. This is a
short UI integration check, not a sustained comparison-memory qualification.
Presentation counters measure the two loupe surfaces, not comparison canvas
cadence, unique frame delivery, or composite pixel correctness. Clock checks
measure each source against its follower; they do not establish A/B frame lock.
Active scopes, producer-authentic long files, sanitizer coverage, other machines
and physical HDR calibration remain open. Existing MoltenVK teardown allocation
and CATransaction diagnostics remain visible in the retained logs; this test
does not establish allocation retirement or resolve those diagnostics.
