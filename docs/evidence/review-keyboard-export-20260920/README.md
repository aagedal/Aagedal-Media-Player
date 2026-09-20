# Native keyboard review export — Phase 125

On 2026-09-20, the optimized Release app built from `eee635e` plus the
export-command changes was exercised on macOS 27.0
(26A428), using Xcode 27.0 (27A266a). The native executable hash is recorded
separately. Final source hashes are recorded in `verification.json`. The initial
native run preceded the last request-cleanup edit; the final rebuild repeat below
covers that edit. This is working-tree evidence, not clean-candidate verification.

## Trigger and change

With the host's current keyboard settings, ordinary Tab navigation traverses
new-note, filter and saved-note text fields but skips the popover's Export menu.
The app now exposes every existing report format under **Review → Export
Review**, with **Cmd–Option–E** for CSV. Both export menus share availability;
empty, loading, relinking or busy reviews cannot start another export.

An open Review flushes existing note-text drafts through its existing save
barrier before export. A closed Review waits for session saves directly.
Requests are consumed once and cleared on dismissal or source/sidecar changes.
The new-note field still requires Return before its text becomes a finding.

## Native results

Disposable generated 640 × 360, 24 fps, ten-second MP4 sources were opened as
an MPV/MPV pair. Source-A opening used the keyboard; comparison setup used an
accessibility click on Add comparison file. Subsequent note operations and
three CSV exports used keyboard events only:

1. Cmd–Option–N and Return created a second finding. Tab reached the first
   stored note's text field. Its replacement text was left unsubmitted.
   `before-shortcut.json` proves that the sidecar still contained the old text.
2. Cmd–Option–E opened the native save panel. Typing a filename and Return
   produced `unsubmitted-edit.csv`. Both this CSV and `saved-review.json`
   contain **Unsubmitted edit exported by keyboard**, proving draft persistence
   precedes the exported snapshot.
3. Cmd–Option–F and `Second` showed **1 of 2 notes**. The same shortcut produced
   `filtered-review.csv` containing both findings, including the hidden note.
4. With Review closed, Cmd–Option–E produced `closed-review.csv`. All three
   CSVs are byte-identical: two findings at frame 0, with exact A/B 24/1 rates
   and both current source URLs.
5. A further export was cancelled with Escape. Cmd–Option–R reopened the
   filtered Review without reopening export; no default-named CSV was written.
6. An accessibility click on the app's Review menu exposed CSV, PDF, Resolve,
   Final Cut and Avid commands. This menu inventory is separate from the
   keyboard-only CSV operations above.

Both media hashes match `fixture-manifest.json`. The retained records contain
only generated media identities and test findings. Source media remains at
`/private/tmp/aagedal-phase125-keyboard`; temporary inputs may be removed by
macOS. Regenerate with bundled FFmpeg's `testsrc2=size=640x360:rate=24`, ten
seconds, libx264 and yuv420p; copy source A to source B in a fresh directory.

## Limits and next acceptance

This passes a focused keyboard create/edit/filter/CSV-export path with ordinary
text-field traversal. Classification/range controls, keyboard-only comparison
setup, note navigation across distinct frames, all formats through native menu
keyboard navigation, Full Keyboard Access, spoken VoiceOver, and the equivalent
AVFoundation workflow remain open. The test did not change keyboard preferences.
Native accessibility inventory is not spoken VoiceOver evidence. Generated
media does not establish representative-media or release-floor performance.

Initial tool input batches occasionally reached native dialogs before focus
settled; the path was re-entered and file selection refreshed before opening.
Transient accessibility capture failures when save panels appeared were followed
by fresh observations of the actual panel. These tool observations are not
counted as application failures or acceptance of unobserved actions.

## Final rebuild and regression verification

After the last dismissal/source-change cleanup edit, the final rebuild passes
61 optimized Release tests: AppCommandTests, CompareReviewReportExporterTests,
and CompareReviewTimebaseMigrationControllerTests, with zero failures, skips,
expected failures or runtime warnings. The existing save-order regression now
also verifies that pending saves permit the initial export command while a
second action is unavailable during the save barrier. Release static analysis
passes. `test-summary.json` retains the result counts; complete local logs and
result bundle paths/hashes are recorded in `verification.json`.

The first test attempt omitted `ENABLE_TESTABILITY=YES` and stopped during
compilation; the corrected run and final-source repeat passed. Existing build
warnings include an unchanged weak-variable diagnostic in the programme
loudness test and Xcode's no-AppIntents metadata notice. No full-suite or new
clean-candidate verification is claimed.

The final tested executable was then reopened with the same pair. A fresh,
unsubmitted **Final rebuild unsubmitted keyboard edit** was exported through
Cmd–Option–E. `final-before-shortcut.json` still contains the old text;
`final-rebuild.csv` and `final-saved-review.json` contain the new text and both
findings. The native UI reports **Saved final-rebuild.csv**. Closing Review,
opening the CSV save panel by shortcut, cancelling with Escape, and reopening
Review again succeeds without replay. The final executable hash is retained
separately from the initial native run. Media hashes remain unchanged.
