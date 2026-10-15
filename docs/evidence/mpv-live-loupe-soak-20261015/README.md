# Sustained concurrent live-loupe qualification

The arm64 Release candidate passes three complete cycles of the four retained
UHD60 SDR/PQ/HLG workloads, with two independent source/loupe pairs running
simultaneously. Each workload runs for 30 measured seconds per cycle: six
minutes of measured four-decoder playback, plus startup and teardown. This
qualifies concurrent decoder load; it does not qualify the comparison UI or
frame lock between independent players. Each case loads the same fixture into
both independent primaries; different-file A/B combinations remain unqualified.

## Measurements

The [acceptance output](soak-acceptance.txt) records 12 workload runs and 216
per-pair cadence windows. Every measured three-second window delivered at least
58.83 completed Metal presentations per second in both the primary and follower
(requirement: 45 fps). Maximum effective clock drift was 66.7 ms (limit: 100 ms).
At least 95% of clock samples were usable in each pair/workload; missing samples
cannot silently reduce the measured maximum.

All followers reported actual VideoToolbox decoding. The primary decoder mode,
3840×2160 decoded dimensions, matching primary/follower output color tags and
EDR mode, silent follower, disabled follower raster cache, and destruction of
each follower while its primary remains alive are asserted in the test.

Cycle-end physical footprint was 827,886,184; 850,037,424; and 913,754,872 bytes.
The final sample is 85,868,688 bytes (81.89 MiB) above the first complete warmup
cycle, within the 256 MiB growth allowance. The highest sampled footprint during
playback was 3,608,563,408 bytes (3.36 GiB), during software-primary PQ. These
samples are neither a peak-allocation measurement nor a total-memory ceiling.

The separate existing live-loupe regression run covers transport, paused native
inspection, GPU crop/rotation/reflection, resizing, file/surface replacement,
and overlay readback suppression/fallback. Its UHD transport test uses the
same four workload identities; it remains separate from the sustained test.
See [soak summary](soak-summary.json) and [regression summary](short-summary.json).

Five runner checks, six restoration checks and sixteen release-validator checks
pass. Ordinary release validation explicitly permits the new test's descriptive
opt-in skip. The dedicated soak runner requires successful XCTest exit and the
acceptance marker matching the requested cycle count and duration.

## Reproduce

Restore and build the current app using the
[native-raster handoff](../../MPV_NATIVE_RASTER_HANDOFF.md). The validated baseline
MPVKit was verified and reused without compilation. The app and hosted tests
were built for arm64 only. Shipping package pins, provider defaults and
production app sources are unchanged.

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/new-live-loupe-soak --live-viewer --soak-seconds 30 --soak-cycles 3
```

`--soak-seconds` accepts 10–3600 seconds; `--soak-cycles` accepts 3–100 cycles.
The workload inputs are the previously retained six-second generated UHD60
clips, looped during measurement. Input hashes and the original source commit,
modified source/script hashes, executable hashes, architecture and host are
bound by the [candidate receipt](candidate-receipt.json). Compressed build,
restore, XCTest and action logs are retained beside this document.

For the seven ordinary regressions, set `AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1`,
`LIVE_LOUPE_CASES` to that manifest and `MEDIA_FIXTURE_DIR` to the retained
`Test Fixtures/Generated` directory in a temporary xctestrun copy. Select
`LiveLoupeSessionTests` and exclude only
`testSustainedConcurrentViewersKeepCadenceAndBoundMemory`. The source xctestrun
is unchanged. The local xcresults are under
`/private/tmp/aagedal-loupe-soak-{qualification,short}-20261015/tests.xcresult`.

## Limits and remaining work

Longer soaks, producer-authentic long files, active scopes alongside both
viewers, the actual comparison UI, sanitizer coverage, other machines/OS
versions and physical HDR calibration remain open. This run uses the original
raster candidate, not the subsequent native-scopes delta. The retained logs
also contain MoltenVK teardown allocation diagnostics and uncommitted
CATransaction warnings. Passing process-growth checks does not prove individual
GPU/driver allocations retire immediately or resolve those diagnostics.
