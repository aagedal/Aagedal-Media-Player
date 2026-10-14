# Secondary-player live loupe prototype

The experimental loupe plays the same file in a silent independent MPV instance
and renders directly to a lens-sized Metal surface. GPU zoom/pan reproduces the
existing picture-coordinate magnification and edge behavior. No per-frame pixel
readback is used while the live viewer is ready. Pausing restores the main
player's captured/native-raster inspection; reverse and AV playback retain the
capture path. The second player never enables the candidate native-raster cache.

Playback synchronization is intentionally approximate. Pause is the inspection
boundary: the overlay hides the independent viewer and captures the primary
player's paused frame. With the candidate native provider enabled, readiness is
verified against the primary's presented raster PTS and selected track, rather
than the follower's playback clock. Paused seeks refresh that primary capture.
This does not require frame lock between the two decoders during playback.

The [pause follow-up run](pause-followup-summary.json) passes all seven live
loupe tests with the native provider enabled. The overlay test keeps live mode
enabled through pause, verifies the primary raster, seeks while paused and
requires a replacement verified image after MPV reaches the target, then
resumes live playback. [The receipt](pause-followup-receipt.json) records this
test-only follow-up; no production behavior changed from the tested candidate.

`LiveLoupeSession` follows transport and samples the two playback clocks using
the comparison clock-bracketing/drift policy. Small errors produce bounded rate
nudges; startup, large errors, and paused changes use accurate seeks. Loop phase
comparison handles EOF wrap. Source identity rejects stale viewers immediately.
Closing, disabling, replacing a file, or rebinding a surface destroys obsolete
contexts. Resizing debounces for 150 ms and recreates only the follower against
the settled drawable size, avoiding MPV's retained output-rectangle issue.

## Accepted validation

[104 regression tests](regressions-summary.json) pass with no skips or failures.
They include all seven new live-viewer tests, existing consumer/loupe/scopes,
AV tracks, and mixed-backend rendering. New checks cover:

- GPU crop pixels at 2×, 4×, 8×, and 16×, including rotations, reflections,
  quadrants, and black outside image edges.
- Output resizing with an unchanged zoom factor; the obsolete follower is
  destroyed and the primary context remains intact.
- Immediate rejection on file replacement, surface rebinding, and handle cleanup.
- Actual SwiftUI overlay switching: after readiness, capture request counts stay
  constant; disabling live mode restores capture, and closing stops it.
- Loop clock phase, play/pause, accurate seeks, speed changes, and teardown.

[Four UHD60 workloads](live-uhd-summary.json) pass inside one XCTest. The clips
are SDR H.264, software-primary PQ HEVC with silent AAC driving the primary audio
clock, hardware-primary PQ HEVC, and hardware-primary HLG HEVC. Every follower
reports actual `hwdec-current=videotoolbox`. Main/follower target primaries,
transfer, and extended-dynamic-range mode match. Both HDR sources use the main
renderer’s BT.2020/PQ output target on this display.

Actual Metal **completed presentation rates** were approximately **59 fps in
both viewers**. `CAMetalDrawable.addPresentedHandler` counts completed output;
this benchmark does not count timers, property updates, or screenshots as video
frames. [Per-case results](live-uhd-acceptance.txt) record rates and maximum
effective clock drift of **16.7–33.3 ms**. The fixed acceptance criteria are at
least 45 presented fps for each viewer, at most 100 ms effective clock drift,
VideoToolbox for the follower, and matching output color configuration. These
bounded measurements establish neither frame lock nor exact presentation-PTS
agreement between independent decoders.

[All 20 restored native fixtures](native-summary.json) also pass inside one
XCTest, preserving paused reference pixels, transforms, color tagging, accurate
seeks, cached image reuse, and resume revocation. The live UHD test separately
checks return to native inspection after pausing and confirms that stopping the
follower destroys its context while preserving the primary context.

## Test build and reproduction

The locally signed arm64 Release app and launcher are in
`build/live-video-loupe-candidate-20261014/` (ignored build output). Quit the
previous app and run `Launch Live Video Loupe.command`. The launcher sets
`AAGEDAL_MPV_LIVE_LOUPE=1` and the existing native-provider candidate flag.
**Live MPV loupe (experimental)** can be switched off in the loupe controls for
comparison. Ordinary launches leave the experimental toggle off.

Follow the [restore/build handoff](../../MPV_NATIVE_RASTER_HANDOFF.md), then run
`scripts/validate-mpv-native-app.py --live-viewer` with a UHD60 manifest.
[The workload manifest](live-viewer-fixtures.json) references the previous
[UHD60 generation receipt](../mpv-loupe-hdr-playback-20261014/playback-fixture-generation.json)
and [the added silent AAC variant](audio-fixture-generation.json). Its video
bitstream is copied unchanged; media/reference binaries remain under
`/private/tmp/aagedal-loupe-playback-60fps`.

[The candidate receipt](candidate-receipt.json) binds source/runner and app/test
binary hashes, arm64 architecture, successful signature verification, criteria,
and measurements. Compressed logs and action acceptance markers are retained.

MPVKit binaries were restored unchanged, with no dependency rebuild or package
repin. This is a development prototype on macOS 27.0.1. It adds a decoder per MPV
source while enabled, including while paused for quick resumption. The measured
workloads have no active scopes. Simultaneous UHD A/B loupes, long-duration memory,
sanitizers, arbitrary media, and physical HDR calibration need further testing.
