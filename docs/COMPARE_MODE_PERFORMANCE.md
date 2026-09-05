# Compare Mode performance validation

Compare Mode runs two independent decoders behind one transport clock. The
ordinary test suite uses small generated fixtures to catch synchronization and
lifecycle regressions quickly, but those clips do not establish that two UHD
HDR streams are sustainable on release hardware.

## Release baseline

While the app supports every Apple Silicon Mac capable of running macOS 15,
the release floor is a base 2020 M1 MacBook Air with 8 GB unified memory and a
7-core GPU. Revisit that named floor whenever the supported-hardware policy
changes. The release run observes each of the ten serial scenarios for 120
seconds: four decoder pairings, two real mixed-backend comparison canvases,
two mixed-backend live-scope canvases, and two mixed-backend loupe canvases
with simultaneous scopes.

Use these conditions for a comparable result:

- Install the release's minimum or current supported macOS version and record
  the exact version.
- Connect AC power, disable Low Power Mode, disconnect external displays, and
  close unrelated foreground applications.
- Generate fixtures and warm the build cache before the measured run. Fixture
  encoding and a clean Release build can otherwise preheat the fanless M1.
- Let `pmset -g therm` return to its idle state before each measured run. Record
  ambient conditions if the machine is visibly heat-soaked.
- Keep the app's comparison render setting at Full Frame for the primary gate.

Prepare a uniquely named local result directory. `build/` is ignored by Git:

```bash
profile_root="$PWD/build/compare-profile-m1"
mkdir -p "$profile_root"

COMPARE_PROFILE_SECONDS=120 \
COMPARE_PROFILE_FIXTURE_DIR="$profile_root/fixtures" \
COMPARE_PROFILE_DERIVED_DATA="$profile_root/DerivedData" \
COMPARE_PROFILE_ARTIFACT_DIR="$profile_root/preparation-artifacts" \
scripts/profile-compare-mode.sh 2>&1 | tee "$profile_root/preparation-report.md"
```

Discard the preparation numbers, wait for the machine to return to its idle
thermal state, then run the measured baseline without regenerating fixtures:

```bash
COMPARE_PROFILE_SECONDS=120 \
COMPARE_PROFILE_FIXTURE_DIR="$profile_root/fixtures" \
COMPARE_PROFILE_REUSE_FIXTURES=1 \
COMPARE_PROFILE_DERIVED_DATA="$profile_root/DerivedData" \
COMPARE_PROFILE_ARTIFACT_DIR="$profile_root/measured-artifacts" \
scripts/profile-compare-mode.sh 2>&1 | tee "$profile_root/measured-report.md"
```

`COMPARE_PROFILE_DERIVED_DATA` lets Xcode validate and incrementally reuse the
Release build rather than compiling into a new temporary directory. Reused
fixtures are accepted only when their manifest, resolution, frame rate, and
duration match the requested profile. Each artifact directory must be new; it
retains the build log, test log, fixture manifest, result bundle, exported
attachments, and a thermal observation log without silently overwriting an
earlier run. Available logs are also retained if setup or building fails.

The profiler defaults to a 30-second development run. Other supported options
are:

```bash
COMPARE_PROFILE_SIZE=3840x2160 \
COMPARE_PROFILE_RENDER_SIZE=3840x2160 \
COMPARE_PROFILE_FRAME_RATE=24 \
scripts/profile-compare-mode.sh
```

The render size defaults to `COMPARE_PROFILE_SIZE`. Use
`COMPARE_PROFILE_RENDER_SIZE=1920x1080` with the same UHD source fixtures only
for a separate Reduced Frame fallback measurement. Set `FFMPEG` when the
desired full ffmpeg is not first on `PATH`.

## Reflected UHD/HDR sources

Run a separate profile with `COMPARE_PROFILE_REFLECTED=1` to apply container
horizontal reflection to both generated sources. This exercises MPV's
reflection correction with VideoToolbox copyback and its vertical video filter,
alongside AVFoundation's native transform handling, in all ten scenarios.
The encoded raster remains UHD 10-bit HDR; reflection is display metadata.
Each test verifies the actual source transforms before starting its workload.

```bash
COMPARE_PROFILE_REFLECTED=1 \
COMPARE_PROFILE_SECONDS=120 \
COMPARE_PROFILE_FIXTURE_DIR="$PWD/build/compare-profile-reflected/fixtures" \
COMPARE_PROFILE_DERIVED_DATA="$PWD/build/compare-profile-reflected/DerivedData" \
COMPARE_PROFILE_ARTIFACT_DIR="$PWD/build/compare-profile-reflected/preparation-artifacts" \
scripts/profile-compare-mode.sh
```

Use the same warm-up, cooldown, reuse, and measured-run procedure as the normal
baseline. Reuse rejects a reflection setting that differs from the manifest;
older manifests without a reflection field describe unreflected sources.
The report records the selected reflection setting. This workload measures
transport, comparison rendering, scopes, and live loupe capture cadence. Direct
app CPU/GPU measurements still require the hands-on Instruments pass.

## Automated coverage and pass criteria

The profiler creates 3840×2160, 24 fps, 10-bit HEVC fixtures with BT.2020/PQ
signaling. It runs the source-timecode alignment, transport, decoder-advance,
audio-suppression, and one-frame drift assertions from
`CompareLiveBackendTests` across MPV/MPV, AVFoundation/AVFoundation, and both
mixed-backend directions. The visual passes repeatedly exercise all seven
presentation modes, their adjustable controls, and every safe-area/aspect-ratio
guide combination. The scope passes cycle A, B, and timestamp-paired display
difference while rendering live waveform and vectorscope output. The loupe
passes host the production paired loupe overlay, sweep picture positions and
2×/4×/8× magnification, and check fresh captures from both decoders while scopes
remain active.

The automated gate requires:

- All four decoder pairings keep both clocks advancing for the requested run.
- Any excursion beyond one primary frame reconverges within one second plus
  one 25 ms sampling interval.
- An excursion active at the cutoff reconverges within its deadline, and the
  final sample is within the one-frame correction threshold.
- MPV-backed source B keeps its audio track disabled while A is monitored.
- Both comparison canvases cover every mode and guide state, retain decoder
  and native-surface identity, deliver at least four control updates per
  second, and keep main-actor delay at or below 250 ms.
- Both live-scope passes advance A and B capture, publish fresh waveform and
  vectorscope output for every source, retain decoder identity, and keep
  main-actor delay at or below 250 ms.
- Both loupe passes publish at least two visibly changed captures per second
  per source, with no capture gap above one second, while exercising every
  magnification. Main-actor delay stays at or below 250 ms. These are minimum
  responsiveness gates; the capture cap remains 10 fps.
- Playback remains responsive without a decoder stall or a reported thermal
  limit during the measured run.

The Markdown report records source revision and cleanliness, Xcode and macOS,
hardware identity, power and thermal snapshots, fixture sizes, drift metrics,
wall time, CPU time, and peak resident memory from command accounting.
`/usr/bin/time` wraps `xcodebuild` for the ten-test serial run, but XCTest can
launch the app through macOS services outside that command's accounted process
tree. Those CPU and memory numbers therefore must not be treated as app
resource totals or per-mode measurements. Measure the app directly in
Instruments for CPU, GPU, and memory baselines. The drift and responsiveness
limits above are the current numeric pass/fail gates.

If the requested observation ends during an out-of-frame excursion, that
pairing continues only until it reconverges or its one-second recovery deadline
expires. This prevents the result from depending on the part of a correction
cycle that coincides with the cutoff. The script prints its report even when a
test assertion fails and returns the failing `xcodebuild` status. It requires
each of the ten expected scenario/backend combinations exactly once; skipped,
missing, duplicate, or malformed scenario records reject the run. Run
`scripts/test-compare-profile-validation.sh` to verify those rejection paths
without starting decoders.

`thermal.log` samples `pmset -g therm` every two seconds throughout the measured
run, with UTC timestamps. The report lists distinct observations so pressure
between the endpoint snapshots is visible. These are system observations, not
GPU utilization measurements or a per-process thermal model. Review them for
reported limits before accepting a release baseline; unavailable observations
do not establish that there was no thermal pressure.

## Instruments run sheet

The automated report does not measure GPU utilization. After it passes, use
the retained fixtures for a hands-on Release-app run:

1. Open the Release app from the retained DerivedData products. Open
   `source-a.mov`, add `source-b.mov`, and verify Source Timecode alignment and
   the active decoder identities before recording. The automated tests force
   all four backend pairings; ordinary app selection may choose MPV for both
   synthetic HEVC files, so record the actual pair and also use representative
   release media for codec-specific manual coverage.
2. In Instruments, record the `CompareMode` and `ScopePerformance` points of
   interest alongside Time Profiler and Metal System Trace data. If those
   instruments cannot share one document on the installed Xcode, make two
   passes with the same sequence and duration.
3. At Full Frame, dwell for 30 seconds in A, B, side by side, vertical wipe,
   horizontal wipe, overlay, and display difference. Move each wipe and sweep
   overlay blend and difference gain during its interval.
4. Enable scopes and dwell for 30 seconds each on A, B, and display difference,
   including a difference-gain change. Confirm waveform and vectorscope remain
   live.
5. Enable the paired loupes with scopes still running. Move the picture point,
   switch 2×/4×/8× magnification, pin/unpin, and close/reopen while playing.
   Check registration, capture cadence, and unchanged controls at Full Frame.
6. Record median and peak CPU and GPU utilization, peak resident memory, worst
   visible interaction delay, drift/correction events, and thermal state before
   and after the trace. Save the trace beside `measured-report.md` or record its
   external location and checksum there.
7. If Full Frame fails, repeat once at Reduced Frame (1/2) and keep both
   results. Reduced Frame is an explicit fallback result, not a passing
   substitute for the Full Frame release gate.

Use a compact results table in the saved report:

| Run | Backends | Render | CPU median/peak | GPU median/peak | Peak RSS | Worst drift/recovery | Thermal before/after | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Automated | All forced pairs | Full | | n/a | | | | |
| Instruments | Record actual pair | Full | | | | | | |
| Instruments fallback | Record actual pair | Reduced | | | | | | |

Synthetic test patterns are reproducible and frame-sized, but they do not
represent every production codec, bitrate, GOP structure, or HDR master.
Follow the profile with representative source/encode pairs from the release
verification matrix.
