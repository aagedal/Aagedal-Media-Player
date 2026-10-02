# Basic current-machine performance — 2026-10-02

The user deferred M1-specific testing and requested basic performance on this
Mac. These measurements use an M5 Pro/64-GB MacBook Pro (Mac17,8), macOS
27.0.1 and Xcode 27.0. The comparison run used battery power on the active
user desktop; Low Power Mode was not exposed by the profiler. This is a basic
current-machine result, not the isolated release-floor hardware protocol.

## Software decoder headroom

The unchanged bundled FFmpeg decoded producer-original H.264 10-bit 4:2:2
clips without audio, hardware acceleration or rendering. One 200-frame warm-up
was discarded, followed by three 600-frame measurements per clip. Input hashes
match before/after. Hashing warms file data before the timed decode; startup
and null-output overhead are included in wall time.

Score = `100 × (decoded frames / wall seconds) / source FPS`.
100 means realtime for that particular clip; the user's threshold is above 100.
This measures this decoder/workload, not a universal machine rating.

| Clip | Raster / source rate | Median score | Minimum score | Current-machine decode result | Hypothetical 20% score |
| --- | --- | ---: | ---: | --- | ---: |
| Sony HD MP4 | 1920 × 1080 / 50 fps | 1320.7 | 1319.7 | Pass | 264.1 |
| Sony FX6 MXF | 3840 × 2160 / 50 fps | 985.6 | 980.9 | Pass | 197.1 |

The 20% column is arithmetic using the user's hypothetical factor. No M1 was
tested and no architectural/codec-specific scaling factor was established.
Commands, exact source/binary identities and individual runs are retained in
[decode-receipt.json](decode-receipt.json) and the one-off measurement script.

## Repinned UHD comparison

A separate ordinary optimized Release test host at clean source commit
`53d055b7f1839f5a6c209e9441c1c4e764592f15` uses the published shipping pins.
The preparation run generated fixtures and warmed the build; its numbers are
discarded. The measured run reuses those fixtures and observes each of ten
serial scenarios for 30 seconds: four transport pairings, two visual canvases,
two scope canvases and two loupe-with-scope canvases. Both streams/render
surfaces are 3840 × 2160, 24 fps, HEVC Main 10, BT.2020/PQ.

All ten tests pass without skips or XCTest runtime warnings. Both clocks
advance for each observation, final effective drift is within one frame, and
out-of-tolerance excursions recover within the existing one-second contract.
The profiler's duplicate/missing/skipped-scenario validator passes unchanged.
This contract does not require every sample to stay within one frame.

| Transport pair (primary / secondary) | Samples within one frame | Worst drift | Longest excursion | Final drift |
| --- | ---: | ---: | ---: | ---: |
| AVFoundation / AVFoundation | 100.0% | 21 ms | 0 ms | 21 ms |
| AVFoundation / MPV | 99.8% | 54 ms | 27 ms | 32 ms |
| MPV / MPV | 99.0% | 125 ms | 301 ms | 0 ms |
| MPV / AVFoundation | 75.3% | 200 ms | 459 ms | 5 ms |

**Comparison follow-up remains open:** MPV-primary/AVFoundation-secondary
scope playback is within one frame for only 45.4% of samples, with 242-ms worst
drift and a 701-ms longest excursion. Its loupe case is within one frame for
79.1%, with 229-ms worst drift and a 729-ms longest excursion. Similar behavior
appears in preparation. Recovery-test passes do not establish frame-exact
comparison throughout playback. Maximum observed main-actor delay is 147 ms.
Retain this timing issue for native comparison acceptance.

Direct one-second app-process sampling records peak RSS 1947.9 MiB (1.90 GiB)
and peak CPU 125.8%, where one core is 100%. RSS excludes some shared/unified
GPU allocations and these are sampled maxima, not total memory-pressure
qualification. The profiler's `time` totals apply to xcodebuild, so they are
not substituted for the app samples. `pmset` reports no recorded thermal or
performance warnings throughout; CPU-limit status is unavailable.

[Measured report](measured-report.md), [metrics](measured-metrics.txt),
[test summary](measured-test-summary.json), [resource summary](measured-resource-summary.json)
and [build identities](compare-build-identity.json) retain the exact results.
Xcode reruns CodeSign before measurement, changing the executable's full-file
hash; both preparation and measured identities are retained without claiming
byte-identical signatures. No app source is recompiled or linked in that build.
Full result bundles, fixtures and build products remain at
`/private/tmp/aagedal-m5-basic-performance-20261002`; temporary storage is not
a durable binary archive.

The basic software-decode threshold and existing UHD development-profile checks
pass on this machine. The 30-minute meter/device soak, audible/device/surround
acceptance, verified MPV source pixels, wider editor/accessibility matrix and
signing/update/editor-beta gates remain open. Spoken VoiceOver acceptance is
explicitly left open by the user. Automatic content-mismatch detection is
explicitly deferred to a later release. These measurements do not close M1,
minimum-macOS, reflected/interlaced/HFR or long-soak qualification.
