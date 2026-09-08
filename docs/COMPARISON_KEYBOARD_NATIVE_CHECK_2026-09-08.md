# Comparison keyboard controls — 2026-09-08

The Release app was exercised on macOS 27.0 (26A5425a), an M5 Pro MacBook Pro
with 64 GB RAM, using disposable 24 fps A/B MOV copies under
`/tmp/aagedal-keyboard-20260908`. Both sources use the ordinary MPV path.
The native player was 270 points wide. The tested build includes the RIFX and
programme-reference commits `dc364b4` / `0e4588c` plus the toolbar focus change
committed with this report.

macOS **Keyboard > Keyboard Navigation** was initially off. It was temporarily
enabled for the keyboard checks and restored to off afterward. This setting
is distinct from **Accessibility > Keyboard > Full Keyboard Access**. Neither
that accessibility feature nor spoken VoiceOver was enabled or claimed.
Native app interaction used keyboard events; accessibility-tree reads and
screenshots established focus, values and visible layout. The system setting
was changed with its native switch. No synthetic AppKit event tests substitute
for these desktop observations.

## Reproduced failures and fixes

1. In single-source playback, Tab focused **Add comparison file**. Space started
   playback instead of opening the file picker. Toolbar focus was tracked only
   for Inspector, so the playback key monitor intercepted the activation.
   Every toolbar control now reports its focus, gets a visible ring, and keeps
   the overlay visible. Space and arrow keys reach the focused controls.
2. In compact comparison settings, Tab reached **Replace comparison file**
   below the visible scroll area, leaving the focused action invisible. The
   final build scrolls to the focused control using a stable per-control ID.
   A native screenshot confirms that Replace and its entire focus ring become
   visible at the bottom of the popover. This also covers the corresponding
   exported-still action immediately above it.

## Final observed results

- Tab/Shift-Tab reaches Add Comparison, Review, compact Comparison Controls,
  Exit, Loupe and Inspector. The Add Comparison focus ring is visible.
- Space on Add Comparison opens the native picker while A stays paused at
  `01:00:00:00`. Keyboard path/filename selection and Return load B.
- Space on Review opens its draft field. Typing `Keyboard toolbar acceptance`
  and Return saves one finding. The sidecar independently confirms A frame 0,
  B frame 24, both rates `24/1`, and the entered text. It survives rebuilding
  and reopening the same pair.
- Keyboard traversal reaches Review's Export menu. Space, native `c` type
  selection, Return and the save dialog's Return create
  `source-a_vs_source-b_review.csv`. Native feedback says it was saved. Reading
  the CSV confirms the note text, frame anchors, rational rates, classifications
  and both complete source URLs. This is a complete keyboard-only point-note
  creation/save/reopen/CSV workflow, not acceptance of every structured-review
  edit or export format.
- Space opens compact Comparison Controls. Menu type selection chooses
  Vertical Wipe. Tab reaches its position slider, and Right changes 50% to 55%
  while the primary timecode stays at frame 0 and playback stays paused.
- In the final scroll-reveal build, Tab from Compare View reaches Replace and
  scrolls it into view. Space dismisses the popover and opens the replacement
  picker. Escape keeps both sources and the stored finding, returning focus to
  Comparison Controls.

## Focused loupe check

With Keyboard Navigation off, Tab from the loupe popover reached the timeline;
this is not evidence of an all-controls navigation failure with the setting
on. With Keyboard Navigation enabled, Tab/Shift-Tab reaches Show Loupe,
Magnification, Pin Picture Position, both sliders and Center and Pin. Space
changes the Show/Pin checkboxes; horizontal Right and vertical Up change their
positions from 50% to 55%. Center and Pin restores both to 50%, and Tab wraps to
Show Loupe. Playback stays paused with unchanged timecode. The magnification
menu opens by Space; selection of a different magnification was not established
in this check. The broader loupe matrix remains open.

## Other native acceptance

Opening `/tmp/aagedal-rifx-s16be-20260908.wav` shows **Playback unavailable** and
explicit RIFX-to-little-endian conversion guidance, alongside the correct
16-bit big-endian PCM metadata. Retry, Reveal File and Copy Diagnostics remain
available. This confirms error propagation, not RIFX playback support.

## Limits and reproducibility

Repeat these checks with generated fixtures from `scripts/generate-test-fixtures.sh`
and a fresh directory so existing reviews and reports are preserved. Temporary
sidecars/CSV files and Xcode artifacts may be removed; this report and fixture
scripts are the retained reproduction record.

Full Keyboard Access, spoken VoiceOver, all seven modes, nested alignment menus,
wide/fullscreen/resize focus continuity, detailed range/classification editing,
PDF/editor-format export and NLE round trips remain open. The screenshot and
accessibility tree occasionally differed during immediate SwiftUI updates;
this check records confirmed native values and saved bytes, not blanket
accessibility-tree acceptance.

## Integrated continuation verification — 2026-09-08

All **464 Release tests pass with zero failures and zero skips**, with both
original ITU reference sets enabled. The suite took 113.316 seconds (113.592
including suite overhead). Release static analysis and all 61 release-preflight
checks pass. Existing loudness/metadata/profile validators also pass, and the
fresh programme runner includes all nine independent LRA calculator checks.

Artifacts: `/tmp/aagedal-rifx-keyboard-full-20260908.xcresult`,
`/tmp/aagedal-rifx-keyboard-full-20260908.log`,
`/tmp/aagedal-rifx-keyboard-analyze-20260908.log` and
`/tmp/aagedal-programme-lra-fresh-20260908`. These temporary artifacts are
reproducible evidence, not a durable release archive. Native keyboard acceptance
and RIFX error propagation are recorded separately from the XCTest run.

