# Native loupe control check — 2026-09-06

This is a partial desktop-automation check, not completion of the hands-on
acceptance matrix. The tested Release app was built from `cd260a3` with
`ENABLE_TESTABILITY=YES`, using Xcode's normal app target. Hardware was an
Apple M5 Pro MacBook Pro (Mac17,8), 64 GB, running macOS 27.0 (26A5425a).
The native canvas widths reported by accessibility were 270 and 1728 points.
Display backing scale was not independently recorded.

The generated `loupe/landscape.mp4` and `loupe/portrait.mp4` fixtures were
opened through the normal file dialogs. These H.264 files use the normal MPV
selection path; decoder identity was inferred from that path, not read from a
runtime diagnostic. No production or private media was opened.

## Observations

- Command-Shift-M opened the loupe controls. Show loupe changed the toolbar's
  accessible value from Hidden to Shown and exposed the lens.
- Setting both accessible position sliders to 25 percent pinned the point.
  The visible lens showed the landscape fixture's upper-left red quadrant.
- Center and pin set both values to 50 percent and retained pinning. The
  visible center lens contained all four quadrants in the expected order.
- Native menu keyboard navigation selected 4×. The picker and lens accessible
  description both reported 4×.
- Hiding removed the lens from the accessibility tree and changed the toolbar
  value to Hidden. Reopening restored 4× and the pinned center.
- Native window zoom from 270 to 1728 points and back kept the single-source
  pinned lens visible. Adding portrait B retained 4× and pinning and exposed
  paired A/B lenses. At 1728 points both lenses showed their picture centers.

## Coverage limits and findings

The automation API provides clicks and drags, but no plain pointer-move action.
A click placed the visible pointer in the green quadrant without changing the
loupe coordinate. This is insufficient evidence of a native hover failure or
success: click dispatch does not establish delivery of the required mouse-move
stream. Actual hover registration remains open.

The baseline also exposed a separate live-surface issue: after adding portrait
B in the narrow window and enlarging it, the live A/B pictures stayed small
inside their panes. Starting playback did not correct their size. The loupes
continued showing the selected centers. This observation prompted a targeted
comparison-surface investigation; it must not be recorded as a resize pass for
the live pictures.

Full Keyboard Access and VoiceOver were not enabled or certified. This check
only establishes the listed accessible values and explicit menu-key actions.
All seven presentation modes, transformed fixtures, fullscreen, real pointer
movement, display changes, simultaneous scopes, teardown instrumentation, and
base-M1 performance remain in the
[manual acceptance run sheet](INSPECTION_LOUPE_MANUAL_TESTS.md).
