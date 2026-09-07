# Multichannel loudness profiling

Run the production analysis service against explicit files with at least one
six-channel (or larger) audio stream and at least 60 seconds of known duration:

```bash
scripts/profile-audio-loudness.sh /tmp/new-loudness-profile \
  /path/to/1h-5.1.m4a /path/to/8h-5.1.m4a
```

The artifact directory must not exist. `LOUDNESS_PROFILE_DERIVED_DATA` can point
to a compatible Xcode build cache. The script builds Release tests, runs the
opt-in workload in isolation, and saves build/test logs, the `.xcresult`, raw
attachments, `summary.json`, hardware/OS/Xcode information, working-tree state,
and SHA-256 input hashes. Keep the test-host player and native app automation
idle during the run. Missing records, duplicate input records, missing workloads,
and invalid measurements fail the script even if XCTest otherwise succeeds.

## Workload and interpretation

Every eligible audio stream is measured sequentially using the actual
`FFmpegService.analyzeLUFS` implementation and bundled FFmpeg: whole file,
first 30 seconds, and last 30 seconds. Timing includes process startup,
decode/filter work, output parsing, and up to 20 ms of completion polling.
Metadata discovery occurs before timing and RSS sampling; its cost is excluded.
Each job has a 30-minute deadline, after which the harness cancels it and fails.
An empty selected interval (for example before a delayed stream starts) fails
through the production error path; use files whose selected intervals contain
samples. Streams below six channels are excluded and reported stream counts
refer only to eligible multichannel streams.

The summary records channels, sample rate, codec, selected boundaries, wall time,
selected-audio seconds per wall second, integrated LUFS, loudness range and true
peak. Metric values are strings so valid digital-silence infinities remain JSON
representable. The early and late ranges have equal selected duration, but the
late range decodes preceding audio before trimming. Its throughput therefore
measures the user's wait for a selection, not total decoder throughput.

Resident memory is sampled every 20 ms for the XCTest app process and its direct
children separately. In an idle isolated host the children are the production
FFmpeg jobs. Child memory is the sum of resident bytes of successfully inspected
direct children at each sample; an exiting child can disappear before inspection.
The report records the maximum observed sum. It excludes grandchildren, can miss
short peaks, and can include unrelated children if other app work is started.
The parent and child maxima may occur at different times and should not be added
as an observed simultaneous total. Parent memory includes framework caches and
allocator high-water marks retained from earlier workloads. These measurements
can reveal growth but cannot prove constant memory for every codec or duration.

There is one observation per workload, with no cache flushing or thermal control.
Repeat runs before making comparative performance claims. This harness does not
measure CPU/GPU energy, playback responsiveness, simultaneous-job cancellation,
UI stale-result suppression, reference accuracy, or accessibility acceptance.
Those remain separate acceptance work described in `AUDIO_LOUDNESS.md`.

## Reproducible synthetic fixtures

A full FFmpeg installation can create a ten-second 48 kHz 5.1 ALAC seed and
stream-copy repeated packets into one-hour and eight-hour M4A files:

```bash
mkdir -p /tmp/loudness-fixtures
ffmpeg -hide_banner -loglevel error -nostdin -f lavfi \
  -i 'sine=frequency=1000:sample_rate=48000:duration=10' \
  -af 'pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0' \
  -c:a alac -n /tmp/loudness-fixtures/seed.m4a
for hours in 1 8; do
  ffmpeg -hide_banner -loglevel error -nostdin -stream_loop -1 \
    -i /tmp/loudness-fixtures/seed.m4a -t "$((hours * 3600))" \
    -c copy -n "/tmp/loudness-fixtures/${hours}h-5.1.m4a"
done
```

Allow about 2.5 GiB for these fixtures. The same tone appears in all six channels, including LFE. Repeated compressed
content keeps generation practical while packet tables and input bytes still
grow with duration. This is a synthetic decoder workload, not representative
programme material or a calibrated loudness reference. Record exact hashes and
reported durations because packet boundaries may slightly exceed the requested
length. Repeat on the oldest supported Apple Silicon hardware with production
codecs, multitrack files, and representative content before closing the broader
multichannel performance gate.

## Local baseline — 2026-09-07

Apple M5 Pro (18 CPU cores), 64 GB RAM, macOS 27.0 (26A5425a), Xcode 26.6
(17F113), on AC power. Release build based on `f0ba95e` plus this continuation.
The fixtures report ALAC, 48 kHz, six channels and exactly 3,600/28,800 seconds.
All six workloads returned -13.4 LUFS integrated, 0.0 LU range and -18.1 dBTP.
This is consistency on a repeated tone, not reference measurement accuracy.
The complete isolated run and artifact validator passed.

| Duration | Scope | Wall time | Parent initial RSS | Parent sampled peak RSS | Children sampled peak RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 hour | Whole file | 36.358 s | 393.12 MiB | 397.53 MiB | 37.44 MiB |
| 1 hour | First 30 s | 0.341 s | 121.22 MiB | 121.23 MiB | 35.14 MiB |
| 1 hour | Last 30 s | 1.321 s | 121.27 MiB | 121.27 MiB | 36.80 MiB |
| 8 hours | Whole file | 277.759 s | 2338.92 MiB | 2373.50 MiB | 50.33 MiB |
| 8 hours | First 30 s | 0.323 s | 181.00 MiB | 181.00 MiB | 43.19 MiB |
| 8 hours | Last 30 s | 7.743 s | 181.00 MiB | 181.00 MiB | 51.81 MiB |

Whole-file throughput was about 99× and 104× real time. The late ranges remained
slower than the early ranges despite equal selected duration: preceding material
is decoded, but only samples surviving trimming reach the loudness/true-peak
filter. All six workloads observed nonzero child RSS through the direct-child
sampler. Child sampled peaks grew moderately between durations; this is not a
constant-memory guarantee.

The parent process was already at approximately 2.3 GiB immediately after metadata
discovery for the eight-hour file, then fell to about 181 MiB before the next
workload. This points to substantial transient metadata/allocator costs requiring
separate investigation. Metadata discovery occurs before these measurements, so
its own peak may be higher. The full-process bounded-memory acceptance gate
remains open despite the comparatively small FFmpeg child RSS. Do not attribute
this parent spike to the loudness filter based on these observations alone.

Raw artifacts: `/tmp/aagedal-loudness-profile-20260907-c`, including fixture
hashes, test attachments, validated `summary.json` and `LoudnessProfile.xcresult`.
An earlier run (`-b`) was interrupted by manual use and closure of the test host;
its measurements are excluded from this baseline. Temporary artifacts may be
removed by the operating system; this recipe and table are the durable record.

## Regression verification

The continuation passes 406 Release tests, Xcode static analysis, all 61
release-preflight checks, and five Python validator tests. Run the latter with
`python3 scripts/test-audio-loudness-profile-validation.py`. They reject missing
or duplicate input/workload records, non-finite timing, incorrect selected
ranges, inconsistent stream metadata/throughput, and absent child-memory
observations while accepting legitimate digital-silence values.

## Metadata memory follow-up

A source audit of resolved SwiftMediaMetadata 3.0.0 (`c2d77c2`) found that
`VideoMetadata.read` maps the source using `Data(contentsOf:options: .alwaysMapped)`
in `loadContainerDataInner` and retains it as internal `originalData` for
MP4/MOV/M4V. The MP4 top-level parser explicitly skips `mdat` payloads. Whole-file
mapping and retention are established; this inspection does not establish why
approximately file-size memory becomes resident, or prove a whole-file heap copy.

Next, profile allocations and resident pages specifically around metadata loading,
conversion to the app model, and release of the dependency's result. Compare one-
and eight-hour inputs and verify metadata parity before changing mapping lifetime
or the dependency. The app cannot directly clear the dependency's internal source
data, and bypassing its normal read wrapper would skip metadata postprocessing.
This needs a measured dependency-level fix, not a loudness-filter workaround.
