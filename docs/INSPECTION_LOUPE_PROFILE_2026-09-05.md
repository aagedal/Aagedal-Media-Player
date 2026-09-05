# Live-loupe development profile — 2026-09-05

## Scope and conditions

The comparison profiler now measures paired loupes with simultaneous scopes,
in both mixed-backend directions, alongside its existing eight workloads.
This is a development run on an M5 Pro, not the 120-second base-M1 release gate
or a direct Instruments measurement of app CPU, GPU, or memory.

- MacBook Pro, Apple M5 Pro, 64 GB (Mac17,8), AC power.
- macOS 27.0; Xcode 26.6 (17F113).
- Reflected fixtures: 3840×2160, 24 fps, HEVC Main 10, BT.2020/PQ,
  horizontal container reflection on both sources, roughly 13.6 Mbps each.
- Full-resolution decoder surfaces; eight seconds per scenario.
- Source revision: `c44536e` plus this continuation's changes.

## Initial failure

The first reflected profile failed both loupe workloads while the other eight
scenarios passed. The loupe backed by AVFoundation published only 0.25 fresh
frames/second as source A and 0.87 as source B, with gaps of 7.146 and 2.749
seconds respectively. MPV delivered 5.71 and 5.60 fresh frames/second. Both
playback clocks and scope rendering continued. The normal small-fixture loupe
tests had passed, demonstrating why production-resolution validation matters.

The AV loupe captured a playback timestamp, then dispatched background work
and awaited asset metadata before asking for the corresponding buffer. The
capture path now copies the buffer immediately at the current player time and
passes the retained snapshot to background conversion. The single-worker gate
and independent AV output ownership remain in place.

The initial loupe metric also reported canvas points instead of backing pixels.
The report now uses backing pixels and asserts native surface sizes. The first
run's `canvas=1920x1080` represented a 3840×2160 Retina canvas; it was not a
reduced-resolution configuration.

Failed-run evidence on the test machine:
`/private/tmp/aagedal-loupe-cadence-reflected-artifacts` and
`/private/tmp/aagedal-loupe-cadence-reflected-report.md`.

## First snapshot-fix verification

Both loupe workloads passed after acquiring the buffer before background work:

| A / B backend | Fresh capture fps A / B | Longest gap A / B | Main-actor delay | Longest drift excursion |
| --- | ---: | ---: | ---: | ---: |
| AVFoundation / MPV | 5.24 / 5.37 | 0.299 / 0.364 s | 0.106 s | 0.000 s |
| MPV / AVFoundation | 5.58 / 4.46 | 0.346 / 0.444 s | 0.116 s | 0.639 s |

Both sources retained their native surfaces, all magnifications and scope
sources were exercised, and overlay-close cleanup passed. The complete run
still failed: the separate AVFoundation/MPV scope-only workload measured
280 ms main-actor delay against its unchanged 250 ms limit. These loupe results
are useful fix evidence, but this run is not a passing ten-scenario profile.

Evidence: `/private/tmp/aagedal-loupe-cadence-snapshot-artifacts` and
`/private/tmp/aagedal-loupe-cadence-snapshot-report.md`.

## Final complete verification

The unchanged snapshot fix passed all ten reflected UHD/HDR scenarios in a
fresh run, with zero failures and no skips. No performance thresholds were
relaxed. The scope-only delay excursion did not recur. Worst drift recovery
across all workloads was 0.732 seconds; worst main-actor delay was 116 ms.

| A / B backend | Fresh capture fps A / B | Longest gap A / B | Main-actor delay | Fresh scope renders |
| --- | ---: | ---: | ---: | ---: |
| AVFoundation / MPV | 5.75 / 5.75 | 0.400 / 0.315 s | 0.116 s | 58 |
| MPV / AVFoundation | 5.11 / 5.61 | 0.284 / 0.284 s | 0.097 s | 60 |

Both loupe workloads covered all three magnifications and scope sources and
stayed within one primary frame for every drift sample. This observation on
this generated workload is not a claim of continuous frame lock for arbitrary
media. Native-surface identity, output cleanup, and stale-result rejection
checks passed. `pmset` reported no recorded thermal/performance warnings or CPU
power status; direct app resource measurements remain necessary.

Evidence: `/private/tmp/aagedal-loupe-cadence-final-artifacts` and
`/private/tmp/aagedal-loupe-cadence-final-report.md`.

The full Release suite also passed 335 tests without failures or skips. Xcode
static analysis, all 61 release-preflight checks, and profiler metric/reuse
rejection checks passed. Logs are retained on the test machine at
`/private/tmp/aagedal-loupe-cadence-full.log`,
`/private/tmp/aagedal-loupe-cadence-analysis.log`,
`/private/tmp/aagedal-loupe-cadence-preflight.log`, and
`/private/tmp/aagedal-loupe-cadence-validator.log`.

## Interpretation and remaining gates

Fresh-frame counts require both a new CGImage and changed normalized 32×18
sampled pixels. They measure published, visibly changing decoder captures on a
moving fixture, not panel refresh, exact source pixels, or timestamp-paired A/B
samples. The minimum gate is two fresh frames/second per source, no capture gap above one second, and at most 250 ms main-actor delay. The 10 fps capture ceiling is
not a guaranteed cadence.

Native pointer registration across all modes, fullscreen/resizing, keyboard
and VoiceOver validation, representative production media, 120-second ordinary
and reflected base-M1 runs, and direct Instruments measurements remain open.
