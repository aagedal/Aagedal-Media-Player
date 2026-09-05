# Compare Mode 120-second development profile — 2026-09-05

All eight serial scenarios passed their automated drift, decoder-advance,
audio-suppression, visual-identity, and responsiveness assertions. Each scenario
observed 120 seconds at full 3840×2160 render resolution. This is development
evidence on an M5 Pro, not the base-M1 release gate.

## Configuration

- MacBook Pro, Mac17,8, Apple M5 Pro, 64 GB unified memory.
- macOS 27.0; Xcode 26.6, build 17F113; optimized Release tests.
- Source revision at invocation: `f3cf8c7b17aa2ed601fd71878e24afaa09abf1fc`,
  with the export, still-rendering, and profiler changes in this continuation.
  Subsequent sidecar validation changes were tested separately and do not
  change playback or rendering.
- Generated 3840×2160, 24 fps, HEVC Main 10, BT.2020/PQ pair, approximately
  13.60/13.61 Mbps; source A/B sizes 212,470,824/214,318,632 bytes.
- AC power reported; Low Power Mode information unavailable. No controlled
  cooldown or external-display condition was established for this development
  run.
- `pmset -g therm` sampled every two seconds. Every observation reported no
  recorded thermal warning, performance warning, or CPU power status. This is
  limited system telemetry, not a measured absence of thermal pressure.

## Results

AV denotes AVFoundation. Percentages and times below are rounded by the
profiler; final drift is asserted against the unrounded one-frame threshold.

| Workload | A/B backends | Samples within one frame | Worst drift | Longest excursion | Final drift | Worst main-actor delay |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Transport | AV/AV | 100.0% | 32 ms | 0 ms | 32 ms | n/a |
| Transport | AV/MPV | 99.6% | 66 ms | 57 ms | 32 ms | n/a |
| Transport | MPV/MPV | 99.9% | 83 ms | 27 ms | 42 ms | n/a |
| Transport | MPV/AV | 93.6% | 200 ms | 439 ms | 26 ms | n/a |
| Visual | AV/MPV | 100.0% | 43 ms | 27 ms | 20 ms | 8 ms |
| Visual | MPV/AV | 96.9% | 200 ms | 322 ms | 16 ms | 10 ms |
| Live scopes | AV/MPV | 99.0% | 80 ms | 910 ms | 10 ms | 95 ms |
| Live scopes | MPV/AV | 84.4% | 226 ms | 807 ms | 23 ms | 96 ms |

Both visual passes delivered 1,200 updates and covered all seven modes and all
20 guide combinations. Live scopes produced 1,585 renders for AV/MPV and 1,419
for MPV/AV; both exercised A, B, and display difference with advancing captures.
The scope workload with AVFoundation as B spent more time outside one frame,
even though every excursion recovered within the existing deadline. A passing
recovery gate does not mean continuous frame lock.

The timed command took 977.24 seconds. Its accounting reported 1.70 seconds
user CPU, 1.29 seconds system CPU, and 894,730,240 bytes peak RSS (about 853 MiB).
These are `xcodebuild` command-accounting values. The separately hosted test
app may be excluded, so these values are not app CPU or memory measurements.

## Retained local evidence and remaining gates

The original report is `/private/tmp/aagedal-compare-120-report.md`; raw logs,
thermal observations, attachments, fixture manifest, and result bundle are in
`/private/tmp/aagedal-compare-120-artifacts`. Fixtures remain in
`/private/tmp/aagedal-compare-120-fixtures`. Copy these temporary artifacts to
durable release storage before relying on them later.

The remaining gates are the controlled base-2020-M1 run, app-level Instruments
CPU/GPU/memory and thermal validation, representative-media and live pixel
checks, editor interchange, beta feedback, and demo recording. Follow
[the performance run sheet](COMPARE_MODE_PERFORMANCE.md) for the release run.

## Code validation in this continuation

- The initial complete Release suite passed 274 tests before the additional
  sidecar arithmetic hardening.
- All 64 focused export, sidecar, still-rendering, and presentation tests
  passed after that hardening; Xcode static analysis and all 61 source release
  preflight checks passed too.
- A later full-suite attempt encountered repeated native audio startup
  timeouts (`AQMEIO` / `MEDeviceStreamClient`) and decoder-advance failures in
  both backends. That run was stopped and is not a passing full-suite result.
  Its log is `/private/tmp/aagedal-compare-final-tests.log`. The earlier
  sustained profile remains a separate successful observation; it does not
  erase this later validation failure.
- A fresh-process retry of
  `testDisjointSourceTimecodesClampToFirstSecondaryFrame` reproduced the
  decoder-advance failure, with native audio startup timeouts still present.
  The built-in output device was listed by a read-only system diagnostic;
  the underlying startup failure remains unresolved. Retain
  `/private/tmp/aagedal-compare-playback-retry.log` and require a clean complete
  suite before release. No audio settings or services were changed.
