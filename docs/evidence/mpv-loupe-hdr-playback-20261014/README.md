# HDR playback loupe and capture cadence

The paused loupe used the tagged native-raster provider, but playback fell back
to an untagged 8-bit screenshot. Its timer also imposed a 10 fps ceiling.

The updated arm64 Release app requests RGBA16 GPU screenshots for supported
BT.2020 PQ/HLG playback and creates CGImages with the corresponding HDR color
space. The MPV output color parameters bracket each capture. PNG's flexible
color target preserves source transfer values without invoking a PNG encoder;
the native-color option is restored before releasing the MPV queue. Ordinary
scope screenshots retain the explicit sRGB target. See the
[mpv screenshot documentation](https://mpv.io/manual/stable/#command-interface-screenshot-raw)
and the restored candidate's `player/screenshot.c` and `video/out/vo_gpu_next.c`.

Capture now schedules from completion with a 60 Hz ceiling and one worker at a
time. It avoids native-raster commands during playback and synchronous track
queries on the main actor during an active preview. Completion still checks
source identity before publication; paused source proof checks the live track
and presented PTS. Cached paused images retain their existing reuse behavior.

## Accepted results

- [97 regression tests](regressions-summary.json), no failures or skips: consumer,
  loupe, scopes, AV tracks, mixed-backend playback, and oriented preview pixels.
- [20 restored hosted fixtures](hosted-summary.json), all accepted inside one
  XCTest: native geometry/color, independent reference samples, accurate seeks,
  paused image reuse, and resume revocation.
- [Four UHD 60 fps playback cases](playback-summary.json), all accepted inside
  one XCTest: SDR H.264 plus PQ/HLG HEVC with software/VideoToolbox selections.
  HDR preview samples match independent decoded first-frame references within
  the existing 256-unit RGBA16 tolerance. Every measured playback frame has
  the expected depth/color tag; all measured updates contain changed center
  pixels. Pausing restores native-raster proof.
- [Six stress cycles](stress-summary.json), all accepted inside one XCTest:
  60 UHD/HDR load/seek/resume/teardown lifecycles and 180 rapid reopen sequences.

Delivered rates were **20.56, 20.38, 19.99, and 19.99 distinct frames/second**.
The backend-only runs measured **23.40, 19.95, 19.84, and 20.01 captures/second**,
respectively. Measurements are separate short intervals, so small differences
between app and backend-only rates are expected. The app must exceed the old
10 fps ceiling and deliver at least 80% of backend throughput, capped at the
60 Hz scheduling target. For the moving 60 fps workload, at least 90% of image
updates must contain changed center pixels. This avoids counting repeated
copies as fresh frames. The unchanged GPU screenshot path remains the principal
UHD throughput limit; this build does not establish 60 fps UHD capture.

Stress cycle-end physical footprint, in MiB: **1334.8, 1524.7, 1254.5, 1221.0,
1203.4, 1063.0**. The largest post-warmup increase is about 190 MiB, within the
unchanged 256 MiB growth limit. These samples measure the full hosted process,
not peak allocations or just the native cache. The final sample is below warmup.

## Reproduction and candidate

The [handoff](../../MPV_NATIVE_RASTER_HANDOFF.md) restores the unchanged MPVKit
bundle and builds the app. `scripts/validate-mpv-native-app.py --playback` runs
the playback/color/cadence checks. Use the retained manifest for its 2 fps cases;
use the [new workload manifest](playback-fixtures.json) for moving UHD 60 fps.
The [generation commands and file hashes](playback-fixture-generation.json)
record the six-second changing-luma source, explicit PQ/HLG bitstream metadata,
SDR variant, and independent FFmpeg references. The manifest retains ffprobe
metadata confirming 3840×2160 at 60/1 with 10-bit BT.2020 PQ/HLG for HDR inputs.
Media/reference binaries remain in `/private/tmp/aagedal-loupe-playback-60fps`.

The locally signed app and launcher are at
`build/loupe-hdr-playback-candidate-20261014/` (ignored build output). Quit the
previous player and run `Launch HDR Playback Candidate.command` to enable the
paused native provider. The HDR playback preview works with the provider gate
off as well. The [candidate receipt](candidate-receipt.json) binds source,
runner, app/test binary hashes, arm64 architecture, code-signature verification,
cadence, and memory samples. Compressed logs and acceptance markers are retained.

No MPVKit binaries were rebuilt or published. Shipping pins and the default-off
native provider gate are unchanged. This is a development build on macOS 27.0.1,
not a notarized release or physical HDR display calibration. Faster UHD capture
requires further work on the live capture backend. Sanitizers, long-duration
loads, and broader media/display qualification remain open.
