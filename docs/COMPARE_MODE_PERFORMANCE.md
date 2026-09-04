# Compare Mode performance validation

Compare Mode runs two independent decoders behind one transport clock. The
ordinary test suite uses small generated fixtures to catch synchronization and
lifecycle regressions quickly, but those clips do not establish that two UHD
HDR streams are sustainable on release hardware.

Run the production-resolution profile on the oldest supported Apple Silicon
Mac before a Compare Mode release:

```bash
scripts/profile-compare-mode.sh | tee compare-mode-profile.txt
```

The profiler generates disposable 3840×2160, 24 fps, 10-bit HEVC fixtures with
BT.2020/PQ signaling. It then runs the same source-timecode alignment,
transport, decoder-advance, audio-suppression, and one-frame drift assertions
used by `CompareLiveBackendTests` for 30 seconds across MPV/MPV,
AVFoundation/AVFoundation, and both mixed-backend directions. Its report also
captures wall time, CPU time, and peak resident memory for the optimized,
serial test run. The profiler injects its configuration into a disposable
`.xctestrun` file, so concurrent ordinary tests in the checkout are unaffected.
Each backend is attached to a retained render output matching the fixture size;
ordinary integration-test runs continue to use small 320×180 outputs.
If the requested observation ends during an out-of-frame excursion, that
pairing continues only until it reconverges or its one-second recovery deadline
expires. This prevents the result from depending on which part of a correction
cycle happens to coincide with the cutoff.

Configuration is opt-in through environment variables:

```bash
COMPARE_PROFILE_SECONDS=120 \
COMPARE_PROFILE_SIZE=3840x2160 \
COMPARE_PROFILE_RENDER_SIZE=3840x2160 \
COMPARE_PROFILE_FRAME_RATE=24 \
scripts/profile-compare-mode.sh | tee compare-mode-profile.txt
```

The render size defaults to `COMPARE_PROFILE_SIZE`; override it only when a
separate output-resolution comparison is intentional.

Set `FFMPEG` when the desired full ffmpeg is not first on `PATH`. Set
`COMPARE_PROFILE_FIXTURE_DIR` to retain the generated media for repeated manual
or Instruments runs; otherwise the profiler removes its temporary fixtures.

## Pass criteria

- All four decoder pairings keep both clocks advancing for the requested run.
- Any excursion beyond one primary frame reconverges within one second.
- An excursion active at the cutoff reconverges within its one-second deadline,
  and the final sample is within the one-frame correction threshold.
- MPV-backed source B keeps its audio track disabled while A is monitored.
- The machine remains responsive and the comparison view remains interactive.

The automated report does not measure GPU utilization or prove that wipe,
overlay, difference rendering, and scopes remain interactive under the same
load. For release validation, retain the fixtures and perform a second run in
the app while recording the existing `CompareMode` signposts in Instruments.
Also record the `ScopePerformance` category when exercising scope sources.
Exercise the visual modes and scope sources, record CPU/GPU utilization and
thermal behavior, and attach those observations to the saved profile report.

The script prints its drift and resource report even when an assertion fails,
then returns the failing `xcodebuild` status so it can be used as a release or
continuous-integration gate.

Synthetic test patterns are deliberately reproducible and frame-sized, but
they do not represent every production codec, bitrate, GOP structure, or HDR
master. Follow the profile with representative source/encode pairs from the
release verification matrix.
