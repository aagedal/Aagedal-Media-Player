# Layout-independent review navigation — Phase 128

Checked on 2026-09-21 with an optimized Release build from `8993bd4` plus
the two Swift source changes identified in `verification.json`, on macOS
27.0 (26A428). This is working-tree evidence, not clean-candidate verification.

## Diagnosis and change

The Phase 127 bracket-shortcut failure reproduced in the prior Release app.
In the focused new-note field, the automation's `bracketleft` key produced
`å`, while `alt+8` produced `[`. Both diagnostic characters were removed
without creating a note. Cmd–Option–8 also failed to navigate after separately
confirming popover dismissal. This identifies an input-layout dependency but
does not establish the complete AppKit key-equivalent failure mechanism.

Previous/Next Review Note now use Cmd–Control–Left/Right, avoiding printable
bracket keys. The local playback monitor explicitly passes these combinations
through to the menu instead of interpreting them as ordinary frame steps.
The existing active-window routing, filters and navigation model are unchanged.

## Native verification

The rebuilt app reopened the disposable Phase 127 MPV sources and their saved
three-note review. All actions below used keyboard input; native accessibility
observations confirmed selection, timecode, focus and paused playback.

1. Cmd–O, file-list selection and Return loaded source A. Cmd–Option–O,
   file-list selection and Return loaded source B and the saved review.
2. Cmd–Control–Right moved from frame 0 to frame 10, skipping no distinct
   position. Repeating it stayed at frame 10 despite multiple findings there.
   Cmd–Option–N and Return saved `Phase 128 next shortcut and end boundary`.
3. Escape closed review and focused the timeline. Cmd–Control–Left moved
   from frame 10 to 0, skipping same-frame duplicates. Repeating it stayed
   at frame 0. A second note saved `Phase 128 previous shortcut and start boundary`.
4. Cmd–Option–F focused the filter. With `frame zero`, Next stayed at 0.
   Replacing the filter with `frame ten` and invoking Next moved to 10 while
   the filter field retained focus. The text was unchanged by navigation.
5. The filter was cleared and review dismissed. Cmd–Option–E exported the
   five findings. The native filename field retained its extension, so the
   resulting disposable file is `phase128-navigation.csv.csv`; its bytes are
   retained here as `review.csv`.
6. Ordinary Right then Left moved 10 → 11 → 10, confirming normal frame
   stepping. Playback stayed paused.

Independent JSON/CSV parsing confirms all five findings agree on text, A/B
frames, 24/1 rates and current source URLs. The two new witnesses record
A/B frames 10/10 and 0/0. All three original note objects and both source
media hashes are unchanged. Before/after sidecars, CSV, test summary and
source/executable/log hashes are retained beside this report.

## Regression verification and limits

All 31 focused optimized Release tests pass across AppCommandTests,
CompareReviewNavigationTests, CompareReviewTimebaseMigrationControllerTests
and WindowManagerTests. The repository's XCTest evidence validator reconciles
the summary and detailed results with zero skips, failures, expected failures
or runtime warnings. Release static analysis also passes.

This closes the focused Previous/Next shortcut gap from Phase 127 for these
MPV/MPV fixtures, including filter-field focus and timeline focus. It does not
establish complete structured-control traversal, Full Keyboard Access, spoken
VoiceOver, AVFoundation or multi-window native acceptance. No keyboard
preferences changed. The app remains paused on the disposable comparison at
frame 10 with review saved and the export panel closed.
