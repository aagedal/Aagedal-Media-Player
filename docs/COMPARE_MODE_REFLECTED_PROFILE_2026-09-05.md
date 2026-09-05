# Reflected Compare Mode development profile — 2026-09-05

## Scope and conditions

This is a development smoke profile of the reflection-only MPV copyback/filter
path. It does not satisfy the 120-second base-M1 release gate, verify live loupe
cadence, or measure app GPU utilization.

- MacBook Pro, Apple M5 Pro, 64 GB (Mac17,8), connected to AC power.
- macOS 27.0; Xcode 26.6 (17F113).
- Both sources: 3840×2160, 24 fps, HEVC Main 10, BT.2020/PQ, with container
  horizontal reflection. Test setup verifies the actual display transforms.
- Full 3840×2160 render surfaces; eight seconds per scenario.
- Fixtures encoded with ffmpeg 9.0.1; approximately 13.6 Mbps per source.
- Changes based on `54396aa`, with the continuation changes uncommitted.

## Initial run

The initial run returned Xcode status 65: all eight sustained workload metrics
met their existing drift/recovery limits, but the AVFoundation/MPV transport
case failed its subsequent loop-resume assertion. Its wait stopped when B's
position was aligned and immediately checked the asynchronously published
playing state. The check now waits for both conditions within the original
two-second deadline and unchanged drift threshold.

Initial worst drift recovery was 0.744 seconds; worst main-actor delay was
102 ms. Both visual passes delivered 80 updates and covered all seven modes.
These measurements are retained as failed-run evidence, not a passing profile.
Raw evidence: `/private/tmp/aagedal-reflected-profile-measured-artifacts` and
`/private/tmp/aagedal-reflected-profile-measured-report.md` on the test machine.

## Corrected run

The rerun passed all eight scenarios with zero failures and no skipped tests.
The loop check now observes resumed playback and aligned position together;
no production transport change was needed. Worst recovery was 0.754 seconds,
worst main-actor delay was 89 ms, both visual passes produced 80 updates, and
both scope passes produced 101 fresh renders across all three scope sources.

| Workload | A / B backend | Within one frame | Longest excursion | Main-actor delay |
| --- | --- | ---: | ---: | ---: |
| Decoder | avFoundation/avFoundation | 100.0% | 0.000s | — |
| Decoder | avFoundation/mpv | 96.4% | 0.030s | — |
| Decoder | mpv/avFoundation | 100.0% | 0.000s | — |
| Decoder | mpv/mpv | 100.0% | 0.000s | — |
| Scopes | avFoundation/mpv | 94.6% | 0.252s | 0.078s |
| Scopes | mpv/avFoundation | 90.6% | 0.754s | 0.089s |
| Visual | avFoundation/mpv | 94.0% | 0.190s | 0.006s |
| Visual | mpv/avFoundation | 44.2% | 0.338s | 0.007s |

The MPV/AVFoundation visual workload was within one frame for 44.2% of
samples while meeting the bounded recovery gate. This is not continuous frame
lock. `pmset` reported no recorded thermal/performance warnings or CPU power
status; that is not a direct measurement of app thermal behavior.

Raw evidence: `/private/tmp/aagedal-reflected-profile-final-artifacts` and
`/private/tmp/aagedal-reflected-profile-final-report.md` on the test machine.
The ordinary complete Release suite also passed 333 tests with no skips; the
profile rerun verifies the subsequent loop-test predicate change.

## Remaining release work

Run the reflected and ordinary profiles for 120 seconds per scenario on the
base 2020 M1 MacBook Air under the conditions in `COMPARE_MODE_PERFORMANCE.md`.
Measure the hosted app directly in Instruments for CPU, GPU, memory, and thermal
behavior, including simultaneous loupe capture and scopes. The command-level
resource totals cannot establish app resource usage. Complete native pointer,
fullscreen/resizing, reduced-render, and accessibility checks from
`INSPECTION_LOUPE.md`.
