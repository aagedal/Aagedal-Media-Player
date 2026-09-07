# Native timeline acceptance check — 2026-09-07

A focused check used the Release app built from `f0ba95e`, on the local M5 Pro
with macOS 27.0. Native accessibility actions, pointer drags, and key events
were sent through the computer-use interface. The generated demo fixtures in
`/tmp/aagedal-compare-demo-root-smoke` have 320 × 180 pictures at 24 fps; the
reference is four seconds long and the delivery encode is two seconds long.
This extends the September 6 check without claiming the full release matrix.

## Observed results

- With the reference as the sole source, 2× displayed seconds 0–2. Dragging the
  scrubber to its midpoint sought to source timecode `01:00:01:00`.
- Dragging the overview to the right displayed seconds 2–4 while playback
  remained paused at `01:00:01:00`. Left Arrow with the overview focused moved
  the viewport to seconds 1–3 without changing playback.
- Entering fullscreen retained that interval and the visible overview focus
  ring. Dragging the scrubber to its midpoint and pressing Right reached
  `01:00:02:01`, confirming one-frame keyboard adjustment after the pointer seek.
- Replacing the primary file with the delivery encode while fullscreen reset
  the timeline to Entire duration and removed the overview.
- Adding the reference as comparison B retained both pictures. At 2×, dragging
  the timeline to 0.5 seconds and pressing Right reached `01:00:01:13`; Left
  returned to `01:00:01:12`. The overview reported the source-A interval 0–1
  seconds of its two-second duration. The source-timecode offset was +1 second.

The heavily compressed delivery fixture's tiny burned-in frame counter appeared
stuck at frame 38 across those steps. Independent FFmpeg extraction confirmed
that delivery frames 12–14 contain that same damaged counter while their moving
bars match reference frames 36–38. This is fixture compression damage, not
sufficient evidence of stale playback. Use moving image features or lossless
counter fixtures when checking registration; do not rely on this encode's text.

## Still required

- Actual hover alignment/no-seek behavior and exit/replacement cancellation.
  The current computer-use interface exposes dragging but no pointer-only move,
  so this session did not exercise hover.
- Option-drag, overview dragging during playback, all zoom levels, clipped
  chapter/trim/review ranges, audio-only hover behavior, and narrow layouts.
- Native fractional-rate long-recording checks, transformed loupe pointer
  registration, Full Keyboard Access traversal, and VoiceOver narration.
- Concurrent UHD/HDR thumbnail workloads and the oldest-supported-Mac profile.

The focused arrow-key checks establish behavior after a control acquires focus;
they do not establish complete keyboard traversal or spoken accessibility.
