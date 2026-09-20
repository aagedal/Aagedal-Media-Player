# Keyboard comparison setup — Phase 126

Checked on 2026-09-20/21 with an optimized Release build from `2f4aaed`
plus the changes recorded in `verification.json`, on macOS 27.0 (26A428).
This is working-tree evidence, not clean-candidate verification.

## Change and reproduced defect

Ordinary Tab navigation did not reach Add comparison file with the host's
current keyboard preferences. File → Add Comparison File now exposes the
existing picker through Cmd–Option–O. The menu requires a loaded source A and
an inactive comparison; the handler checks the same conditions and the active
player window. Existing comparison replacement remains in Comparison Controls.

The first native shortcut attempt revealed that the player's local key monitor
consumed Cmd–Option–O as Option–O (clear Out). The I/O/X trim handlers now
exclude Command/Control combinations before considering Option or Shift.

## Final native observations

The final tested build was restarted after Xcode verification. Disposable
640 × 360, 24 fps, ten-second MPV sources are identified in the fixture manifest.
The following sequence used keyboard events only; accessibility-tree reads
verified the resulting dialogs, timecodes and paused state:

1. Cmd–O and native path entry opened source A, paused at frame 0.
2. Down moved to frame 10. O stored an Out point; Up returned to frame 0.
3. Cmd–Option–O opened a native picker with the message **Choose a file to
   compare with source A**.
4. Escape cancelled. Shift–O returned to `00:00:00:10`, proving that the
   existing Out point survived the shortcut and cancellation. Playback remained
   paused.
5. Option–O, Up and Shift–O left the playhead at `00:00:00:00`, confirming
   that the ordinary clear-Out shortcut still works.
6. Cmd–Option–O opened the comparison picker again.

Further Go to Folder interaction became unreliable: path entry was truncated,
Command–A did not select it, and Return/Escape did not consistently dismiss the
sheet. Accessibility-based recovery did not complete source-B selection. This
does not establish whether the remaining problem is in input delivery or native
panel behavior. Complete keyboard A/B loading and subsequent distinct-frame
review navigation are **not accepted** by this run. Earlier diagnostic menu
clicks and duplicate-player cleanup are also outside the keyboard-only sequence.

Both media hashes remain unchanged. No keyboard-navigation preferences were
changed. Structured review controls, Full Keyboard Access, spoken VoiceOver,
multi-window native routing, AVFoundation and representative media remain open.
The native picker may still be open after the incomplete source-B selection.

## Regression verification

The final optimized Release run passes 31 tests across AppCommandTests,
CompareReviewTimebaseMigrationControllerTests, CompareReviewNavigationTests and
WindowManagerTests, with no skips, failures, expected failures or runtime
warnings. Release static analysis passes. Test summary, source/executable hashes
and local full-result/log identities are retained alongside this report.

An initial restricted invocation could not write Xcode caches. The permitted
rerun passed 23 tests, but its `CompareReviewTests` selector did not match the
actual navigation class. A corrected run passed the navigation/routing checks;
the final 31-test run includes all four actual classes after the trim-handler
fix. No full-suite or final clean-candidate verification is claimed.
