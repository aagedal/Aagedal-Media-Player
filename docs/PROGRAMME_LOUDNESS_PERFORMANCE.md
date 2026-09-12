# Split-mono programme loudness profiling

Run the production programme analyzer against explicit files containing at least
eight known mono audio tracks and at least 60 seconds of known duration:

```bash
scripts/profile-programme-loudness.sh /tmp/new-programme-profile \
  /path/to/eight-mono-deliverable.mov
```

The artifact directory must not exist. `PROGRAMME_LOUDNESS_PROFILE_DERIVED_DATA`
can select a compatible Xcode build cache. The runner builds Release tests and
records the commit/working-tree state, hardware, OS, Xcode, power state and input
SHA-256 hashes, alongside build/test logs, `.xcresult`, attachments and validated
`summary.json`. Keep the isolated test-host player and native automation idle.
The runner also saves `power-events.json` for its measurement interval and fails
if macOS reports sleep during that interval. It preserves the interrupted
measurements for diagnosis, but they must not be used as clean timing evidence.
Keep the laptop open during measurement; the runner does not override sleep.

For each input, the first two known mono audio ordinals form Stereo (FL, FR),
and the first six form 5.1 (FL, FR, FC, LFE, SL, SR). Other tracks are excluded.
Each layout runs whole-file, first-30-second and last-30-second measurements
sequentially through `FFmpegService.analyzeProgrammeLUFS` and bundled FFmpeg.
The report preserves every source audio ordinal, channel count, sample rate and
codec, and each measurement's exact assignments and speaker roles. This fixed
profiling mapping is not an assertion about a deliverable's actual channel order.

Timing includes process startup, decode/resampling/padding/joining, loudness and
true-peak filtering, parsing, and up to 20 ms of completion polling. Metadata
loading happens before timing and memory sampling. A 30-minute per-job deadline
cancels and fails a stalled workload. Range throughput counts selected seconds,
not all decoded seconds: a late interval still decodes preceding material.

RSS is sampled every 20 ms for the parent test host and the sum of its direct
children separately. A child can exit between enumeration and inspection; short
peaks and grandchildren are not captured. Idle isolation is necessary to avoid
unrelated child processes. Separate parent and child maxima are not a measured
simultaneous total. Metadata allocations and retained caches can affect initial
parent RSS, and metadata's earlier peak is excluded entirely.

One observation per workload is a baseline, not a statistical comparison. No
cache flushing or thermal control is performed. Synthetic hour-long media tests
content duration, not an hour of elapsed playback or a soak. This harness does
not establish production-content coverage, oldest-supported-hardware performance,
energy, playback responsiveness, concurrent cancellation, UI state or VoiceOver
acceptance. Existing correctness tests provide independent signal references;
this profiler checks complete usable measurements rather than recalibrating LUFS.

## Reproducible synthetic input

With a full FFmpeg installation:

```bash
mkdir -p /tmp/programme-fixtures
ffmpeg -hide_banner -loglevel error -nostdin -f lavfi \
  -i 'sine=frequency=1000:sample_rate=48000:duration=10' \
  -map 0:a -map 0:a -map 0:a -map 0:a \
  -map 0:a -map 0:a -map 0:a -map 0:a \
  -c:a alac -n /tmp/programme-fixtures/seed.m4a
ffmpeg -hide_banner -loglevel error -nostdin -stream_loop -1 \
  -i /tmp/programme-fixtures/seed.m4a -t 3600 -map 0:a -c copy \
  -n /tmp/programme-fixtures/1h-eight-mono.m4a
```

All eight tracks contain the same tone, including unused spare tracks. Repeated
packets keep generation practical while input bytes and packet tables grow with
duration. Allow approximately 600 MiB for the one-hour file. This is synthetic
ALAC decode/filter evidence; rerun with actual production codecs and programme
content and on base M1 before closing the broader performance acceptance gate.

## Harness verification

`python3 scripts/test-programme-loudness-profile-validation.py` checks accepted
complete/silent results and rejects missing/duplicate inputs or workloads, bad
assignments/roles, invalid source metadata, non-finite timing, wrong selected
ranges/throughput and absent child-memory samples. Shared metric/range/RSS
validation also has its own suite:
`python3 scripts/test-audio-loudness-profile-validation.py`. Power-event window
and event-type checks run with
`python3 scripts/test-programme-profile-power.py`. The detector was also checked
against the actual uninterrupted one-hour and interrupted eight-hour runs.

## Original shared-input baseline — 2026-09-12

Apple M5 Pro (18 CPU cores), 64 GB RAM, macOS 27.0 (26A428), Xcode 26.6
(17F113). The power snapshot reported AC power and a discharging battery.
Release test build based on `138fd9c` plus this continuation. Other repository
build/test work ran concurrently, so wall times are observations under that host
load, not controlled throughput comparisons. Native automation left the profiler
host idle. This machine is not the base M1 acceptance target.

The one-hour fixture has eight 48 kHz mono ALAC streams, exactly 3,600 seconds,
and 580,243,273 bytes. Each stream reports 160,409 bit/s; the initial packets
contain 1,700 bytes and span 0.085333 seconds. SHA-256:
`dbe5a5e95a909b4688477f782c0752f7294db5ed51466fa0e8b071057b7000c7`.

All six production workloads and artifact validation passed. Stereo returned
-18.1 LUFS and 5.1 returned -13.4 LUFS, with 0.0 LU range and -18.1 dBTP for
both layouts across all scopes. These are repeated-tone consistency results.

| Content duration | Layout | Scope | Wall time | Parent initial RSS | Parent sampled peak RSS | Children sampled peak RSS |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 1 hour | Stereo | whole | 12.712 s | 674.25 MiB | 674.34 MiB | 165.44 MiB |
| 1 hour | Stereo | early | 0.127 s | 671.39 MiB | 671.41 MiB | 40.98 MiB |
| 1 hour | Stereo | late | 1.210 s | 671.47 MiB | 671.48 MiB | 132.06 MiB |
| 1 hour | 5.1 | whole | 40.885 s | 671.48 MiB | 671.80 MiB | 565.20 MiB |
| 1 hour | 5.1 | early | 0.405 s | 122.03 MiB | 122.03 MiB | 98.25 MiB |
| 1 hour | 5.1 | late | 4.449 s | 122.03 MiB | 122.05 MiB | 522.88 MiB |

The 5.1 child reaches approximately 565 MiB for the whole file and 523 MiB for
the late selection, substantially more than the first selection's 98 MiB. The
stereo workloads show the same direction. This evidence does **not** close the
bounded-memory gate; duration scaling and graph/decoder buffering need further
investigation. The parent starts near 674 MiB after metadata, whose earlier
peak is excluded; it eventually falls to approximately 122 MiB. See the separate
[metadata-memory investigation](METADATA_MEMORY_PERFORMANCE.md).

Raw one-hour artifacts: `/tmp/aagedal-programme-profile-20260912-c`, including
`fixture-probe.json`, environment/input hashes, validated summary, attachments
and `.xcresult`. The earlier `-20260912` and `-20260912-b` attempts failed during
package resolution before profiling and are excluded. Temporary files may be
removed by the OS; the recipe, hashes and table are the durable evidence.

### Interrupted eight-hour diagnostic run

The same fixture recipe with `-t 28800` produced eight mono tracks, each reporting
start zero and exactly 28,800 seconds. Packets for all eight tracks are present
at 28,770 seconds. File size is 4,652,793,673 bytes; SHA-256:
`bafb0d0ee9e7b1a218e3830695642bd6f450d1ab3ee18aec4553d3bc23035ca6`.

Artifacts are `/tmp/aagedal-programme-profile-20260912-8h`. The original
structural validator and XCTest passed, but retrospective power inspection
found Clamshell Sleep at 11:41:01, followed by repeated sleep/dark-wake events
through the run ending at 12:05:29. The new runner power check correctly rejects
this run. **Its timings are excluded from performance comparisons.** The 5.1
whole-file wall time includes that sleep; interrupted RSS sampling can miss
peaks and likewise cannot establish a controlled duration-scaling comparison.

Observed child RSS reached approximately 694 MiB for stereo whole-file and
1,864 MiB for 5.1 whole-file; late selections reached 424 and 1,594 MiB. These
are diagnostic lower bounds, not clean benchmark results. More concerning,
both late selections returned -21.1 LUFS despite the repeated identical tones:
whole-file values were -18.1 LUFS stereo and -13.4 LUFS 5.1. Stereo whole-file
true peak also differed (-17.5 versus -18.1 dBTP). Structural validity is not
numerical correctness. Independent graph runs subsequently reproduced the late-range fault: the
original shared-input 5.1 graph returned -21.1 LUFS with FL at -18.1 dBTP and
the other five channel peaks at negative infinity, despite exit status zero
and no warning. Separate input contexts returned the expected -13.4 LUFS and
-18.1 dBTP on every assigned channel. This establishes a real old-graph
correctness failure independent of the interrupted profile's timing. It does
not establish why this large fixture triggers the problem.

### Separate-input correction

The production graph (`c892eef`) now opens an independent demux input for each assigned
mono track. Each input retains the same file timeline, duration limit and
header-derived decoder arguments; resampling, finite padding, exact trimming,
speaker roles and loudness filtering remain in place. This avoids the
reproduced cross-track queue growth and loss of assigned channels. Twenty-two
focused programme/controller/RIFX tests pass with the correction, including
delayed/shorter tracks, mixed rates, opposite polarity, loud spare tracks,
surround/LFE weighting, exact range provenance and cancellation.

Independent process experiments on the same fixtures measured the 5.1 late
selection at 126,156,800 bytes (120.31 MiB) child RSS for one hour and
643,661,824 bytes (613.84 MiB) for eight hours with separate inputs. All six channels in the eight-hour result
returned -18.1 dBTP and the programme returned -13.4 LUFS. Artifacts:
`/tmp/aagedal-programme-buffer-review/baseline-shared-input-8h.log` and
`/tmp/aagedal-programme-buffer-review/separate-inputs-8h.log`. These isolated
graph experiments support the correction but are distinct from the production
service profiler. Per-input container indexes still grow with content duration;
this is a reduction in measured memory, not a constant-memory guarantee.

### Corrected production one-hour rerun

The production service rerun at
`/tmp/aagedal-programme-profile-20260912-separate-1h` passes all six workloads,
artifact validation and the new power-event check, with no sleep observed during
the measured interval. It uses the same one-hour fixture and M5 Pro host as the
original baseline. Concurrent repository build/test activity remains a timing
limitation. All Stereo scopes return -18.1 LUFS, all 5.1 scopes return -13.4 LUFS,
and every scope returns 0.0 LU range and -18.1 dBTP.

| Layout | Scope | Wall time | Parent initial RSS | Parent sampled peak RSS | Children sampled peak RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| Stereo | whole | 12.170 s | 672.81 MiB | 674.28 MiB | 52.50 MiB |
| Stereo | early | 0.148 s | 669.03 MiB | 669.03 MiB | 51.58 MiB |
| Stereo | late | 1.358 s | 669.03 MiB | 669.03 MiB | 54.09 MiB |
| 5.1 | whole | 42.940 s | 669.06 MiB | 670.88 MiB | 125.89 MiB |
| 5.1 | early | 0.402 s | 121.78 MiB | 121.80 MiB | 121.12 MiB |
| 5.1 | late | 3.916 s | 121.80 MiB | 121.80 MiB | 121.83 MiB |

Whole-file child sampled peaks fall from 165.44 to 52.50 MiB for Stereo and from
565.20 to 125.89 MiB for 5.1 in these observations. The 5.1 late selection falls
from 522.88 to 121.83 MiB. Parent metadata-related memory remains high until
retained pages/caches are released, so this does not close full-app memory
acceptance. A clean eight-hour **production service** rerun, representative
production codecs/content, base-M1 measurement and actual elapsed-time soaks
remain separate acceptance work. The independent eight-hour graph result above
confirms the specific long-file channel-loss correction, not all those gates.
