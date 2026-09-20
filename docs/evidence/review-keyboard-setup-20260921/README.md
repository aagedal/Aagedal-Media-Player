# Keyboard comparison setup and distinct-frame review — Phase 127

Checked on 2026-09-21 using the unchanged Phase 126 optimized Release app.
The executable and all five Phase 126 changed-source hashes match the retained
verification record and current source at `5dfaae5`. No new build, XCTest run,
or clean-candidate verification is claimed.

## Accepted sequence

Fresh byte-identical copies of the generated 640 × 360, 24 fps, ten-second
MPV fixtures were placed in `/private/tmp/aagedal-phase127-keyboard` without
a review sidecar. The following sequence used keyboard input only, with native
accessibility-tree observations between actions:

1. Escape, Cmd–N, Cmd–O opened a native file picker. Cmd–Shift–G opened Go to
   Folder. Clipboard paste timed out without changing the selected old path;
   typing the full source-A path succeeded. Separate Return actions selected
   and opened the file.
2. Cmd–Option–O opened the comparison picker with its source-A comparison
   message. Typing `s` selected source A; Up selected source B, confirmed by
   the native selected-file URL. Return loaded the comparison. The player
   exposed `A source-a B source-b`.
3. After comparison initialization, Cmd–Option–N focused the new-note field.
   Typing `Phase 127 frame zero` and Return created a finding at frame 0.
4. Escape dismissed review; Down stepped ten frames. Cmd–Option–N, text entry
   and Return created `Phase 127 frame ten` at frame 10.
5. After Escape and a separate observation, `super+alt+bracketleft` attempted
   Previous Review Note. A subsequently created `Previous shortcut destination`
   witness remained at frame 10. This is a failed navigation observation,
   not evidence that the shortcut reached the app's command handler.
6. Cmd–Option–E opened the CSV save panel. Return saved the default filename
   in the disposable fixture directory and dismissed the panel.

The retained native sidecar and CSV contain all three findings with matching
text and A/B frames `[0, 10, 10]`, exact 24/1 rates and correct source URLs.
Both media hashes remain unchanged. CSV was parsed independently with Python's
standard CSV reader, yielding one header and three records.

## Limits and diagnostics

Before this fresh sequence, the old Phase 126 Go to Folder sheet accepted
Return and source B loaded. Exploratory review/menu interactions used a pointer
and are excluded from the keyboard acceptance above. Direct Previous Note menu
activation in that earlier comparison changed navigation availability to the
first-note boundary; the automated bracket shortcut did not. This does not
isolate keyboard layout, input delivery, focus, or application routing.

The fresh sequence closes keyboard A/B loading, distinct-frame creation and
CSV export for these MPV fixtures. Previous/Next shortcut acceptance remains
open. Structured classification/range traversal, Full Keyboard Access, spoken
VoiceOver, AVFoundation, representative media, and broader multi-window routing
remain unverified. No keyboard preferences were changed. The app is left on the
disposable comparison with its review saved and the export panel dismissed.
