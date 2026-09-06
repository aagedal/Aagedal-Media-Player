# Timeline thumbnail profiling

Run the production hover loader against explicit video files of at least
40 seconds each:

```bash
scripts/profile-timeline-thumbnails.sh /tmp/new-thumbnail-profile \
  /path/to/one-hour.mov /path/to/eight-hours.mov /path/to/twenty-four-hours.mov
```

The artifact directory must not exist. Set `TIMELINE_PROFILE_DERIVED_DATA` to
reuse a compatible Xcode build cache. The script builds Release tests, runs the
opt-in profile in isolation, and preserves build/test logs, the `.xcresult`,
attachments, `summary.json`, hardware/OS/Xcode information, working-tree state,
and SHA-256 input hashes. Do not interact with the test-host player while it runs.
Missing or incomplete result records fail the script, including an accidentally
unconfigured test that returns without profiling.

## What it measures

For each file, 40 requests span the duration in a non-sequential permutation.
Each uses the actual `TimelineThumbnailLoader`, its 180 ms hover delay, and its
AVFoundation extraction with the bundled ffmpeg fallback. Latency includes the
delay, extraction, publication, and up to 10 ms of polling. The report gives
median, nearest-rank p95, and maximum request latency. A request without an image
within 30 seconds fails the run.

Every returned image must fit within 240 × 135 pixels. The cache must never
exceed 32 entries, must reach that limit after 40 unique requests, and must
clear when dismissed with cache invalidation. Reopening the last cached position
must publish synchronously. The pixel-storage upper bound uses the largest
observed image's actual row stride, including padding, times 32.

Resident memory is sampled in the XCTest app process every 10 ms while waiting
for a result. Initial and sampled peak bytes include framework/decoder costs
and previous files' allocator high-water marks; they are not a measurement of
cache storage alone. Sampling can miss shorter peaks and excludes any ffmpeg
child process. Neither these samples nor the cache bound establish an overall
constant-memory decoder guarantee.

The profile does not start playback, scopes, or loupes. It does not establish
thumbnail accuracy, pointer positioning, CPU/GPU load, thermal stability,
assistive-technology acceptance, or concurrent playback responsiveness.

## Reproducible long-GOP fixture recipe

With a full ffmpeg installation, create a 10-second H.264 seed and loop it with
stream copy to preserve 10-second keyframe spacing. These fixtures are synthetic
SDR 640 × 360, 24 fps, not UHD/HDR reference media. Repeated content keeps
generation practical; the MP4 sample table and file size still grow with duration.

```bash
mkdir -p /tmp/thumbnail-fixtures
ffmpeg -hide_banner -loglevel error -nostdin \
  -f lavfi -i 'testsrc2=size=640x360:rate=24' -t 10 \
  -c:v libx264 -preset ultrafast -crf 35 -g 240 -keyint_min 240 \
  -sc_threshold 0 -an -n /tmp/thumbnail-fixtures/seed.mp4
for hours in 1 8 24; do
  ffmpeg -hide_banner -loglevel error -nostdin -stream_loop -1 \
    -i /tmp/thumbnail-fixtures/seed.mp4 -t "$((hours * 3600))" \
    -c copy -n "/tmp/thumbnail-fixtures/${hours}h-long-gop.mp4"
done
```

Allow roughly 10 GiB for all three generated inputs. Supply representative
production recordings for codec/bitrate-specific results. Repeat on the oldest
supported Apple Silicon Mac with UHD/HDR inputs and active playback/inspection
before closing the roadmap performance gate.

## Local baseline — 2026-09-06

Apple M5 Pro (18 CPU cores), 64 GB RAM, macOS 27.0 (26A5425a), Xcode 26.6
(17F113), optimized Release build based on `b32a378` plus this continuation.
The generated inputs above were profiled sequentially in one test-host process.
All 120 requests passed, with 32 cached images and a 3.96 MiB pixel-storage
upper bound for every file.

| Duration | Median | p95 | Maximum | Initial resident | Sampled peak resident |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 hour | 235.5 ms | 240.7 ms | 298.6 ms | 116.45 MiB | 122.31 MiB |
| 8 hours | 237.4 ms | 240.0 ms | 248.1 ms | 120.66 MiB | 123.47 MiB |
| 24 hours | 215.7 ms | 219.0 ms | 220.3 ms | 130.86 MiB | 138.98 MiB |

The 24-hour file was not slower in this small workload; differing seek positions
within each GOP and cache warm-up prevent interpreting that as a duration-based
speed improvement. Full process memory still rose across the run, even though
pixel-cache storage stayed capped. This is a local baseline on newer hardware,
not release-floor or long-session acceptance.

Local raw artifacts: `/tmp/aagedal-timeline-profile-20260906-c`, including
`summary.json`, the fixture hashes, and `TimelineProfile.xcresult`. Temporary
artifacts may be removed by the operating system; the table and recipe above
are the durable record.

Final integrated verification passes all 400 Release tests, static analysis,
and 61 release-preflight checks. The profile script also rejects an existing
artifact directory and a missing media input before starting a build.
