# Native timeline acceptance check — 2026-09-06

A focused native-app check used the Release build at revision `c2c5e81`,
macOS 27.0 (26A5425a), and the generated four-second, 24 fps demo pair
`Source A - reference.mov` / `Source B - delivery encode.mov`.
The app was controlled through native accessibility actions and key events.
This is a focused interaction record, not the full accessibility or media matrix.

## Observed results

- Single source: selecting 64× exposed the full-duration overview and Fit.
- Repeated overview Increment actions moved the visible interval from
  0.0–0.1 seconds to 0.1–0.2 seconds while playback stayed at source
  `01:00:00:00`.
- Playback-position Increment advanced to `01:00:00:01` and revealed the
  playhead in the viewport again.
- The narrow 270-point window retained visible zoom, overview, and Fit controls;
  enlarging the native window retained the timeline state.
- Fit restored Entire duration. With the scrubber focused, Right advanced from
  `01:00:00:01` to `01:00:00:02`.
- Comparison: selecting 2× showed 0.0–2.0 seconds; overview Increment moved it
  to 1.0–3.0 seconds while A remained at `01:00:00:02`. Playback-position
  Increment advanced exactly one frame and revealed A's playhead again.

## Separate defect discovered

Adding B to the paused, enlarged single-source player detached A's MPV drawable:
A's picture became black while the timecode advanced through seeks and playback.
B remained visible. The structural single-source/comparison branch recreated
A's view while its initialized MPV context kept the old drawable. The subsequent
continuation fixes this by retaining the same A canvas across comparison entry,
B replacement, and exit. Verification of that fix is recorded in
`COMPARE_SURFACE_NATIVE_CHECK_2026-09-06.md`.

## Still required

- Hover alignment, no-seek hover, exit/replacement cancellation, and audio-only
  behavior with actual pointer hover.
- Pointer drag and Option-drag at all zoom levels, overview drag while playing,
  clipped markers/ranges, fullscreen, and primary-replacement Fit reset.
- Long-recording fractional-rate media and release-floor thumbnail profiling.
- Full Keyboard Access and VoiceOver sessions. Accessibility Increment actions
  demonstrate the exposed adjustment path; they do not establish VoiceOver
  narration or complete keyboard traversal. Ordinary Tab in this environment
  skipped buttons, so full keyboard acceptance is not claimed.
