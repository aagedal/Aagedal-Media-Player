# Native review save recovery — 2026-09-10

## Scope and setup

Focused native acceptance ran on macOS 27.0 (26A428) in the Release app built
from the Phase 71 save-recovery implementation plus the Phase 72 queued-save
generation guard. The app was restarted from
`/tmp/aagedal-continuation-derived/Build/Products/Release` after building the
fix. This checks native interaction and saved bytes; automated lifecycle and
filesystem-exhaustion tests are separate evidence.

Create a disposable source pair with:

```bash
python3 scripts/generate-review-interchange-fixtures.py /tmp/new-save-recovery-fixtures
```

This run used `/tmp/aagedal-native-save-recovery-20260910`. Before editing,
the generated sidecar was copied to `retry-copy.json`, and hashes of the
original sidecar and both movies were retained outside the fixture directory.
The app opened A and B, then **Review → Notes → Open Notes Copy…** activated
the copy with eight findings. Only this disposable directory had its mode
changed from `0755` to `0555`, then back to `0755` for each recovery check.
No user media or original review was edited.

## Observed results

1. Typing `Native Retry Save recovery — æøå` into the new-note field and
   pressing Return showed nine findings and a permission-denied save error.
   The native error identified `retry-copy.json` and its directory. The
   accessibility tree exposed **Retry saving review notes**. Independent reads
   confirmed that the copy still held its original eight findings and all
   original-file hashes matched.
2. Closing and reopening the Review popover retained the unsaved note and
   error. Enlarging the window showed the complete wrapped error, Retry Save
   action, active-copy path, and footer menus without text truncation.
   Invoking Retry Save while the directory remained read-only retained the
   error and note.
3. After restoring directory write permission, invoking Retry Save cleared
   the error. The copy contained exactly one new note with the entered Unicode
   text. Original sidecar and movie hashes remained unchanged.
4. With the directory read-only again, deleting that disposable new note
   showed eight findings and the permission error. The copy's complete bytes
   still matched the saved nine-note version. Restoring permissions and
   invoking Retry Save cleared the error and persisted the deletion.
5. Final checks found all eight original note identities and fields, including
   frames, ranges, text, classifications and dates, preserved in the copy.
   UUID casing and canonical note ordering may normalize during encoding.
   Both source identities and every original-file hash remained unchanged.
   The fixture directory was restored to `0755` before the app closed.

## Limits and evidence

Interaction combined native accessibility actions with keyboard file selection
and text entry. A Shift-Tab probe traversed text fields; this is not acceptance
of all-control keyboard navigation. Full Keyboard Access, spoken VoiceOver,
broader narrow-window layouts and native disk-full alerts remain open.
The screenshot check above used the enlarged window because the screenshot
tool cropped the small window's popover at its parent-window bounds.

Temporary evidence is in `/tmp/aagedal-native-save-recovery-baseline.json`,
`/tmp/aagedal-native-save-recovery-saved-copy.json` and
`/tmp/aagedal-native-save-recovery-validation.json`. The generated fixture
manifest and this procedure allow repetition when those temporary files are
removed. The actual bounded disk-image XCTest does not substitute for native
disk-full interaction or APFS-volume acceptance.

## Integrated verification

The final Release suite passes 524 tests with zero failures or skips, including
both original ITU reference sets and the real disk-image recovery test, in
114.710 seconds (114.957 with suite overhead). Release static analysis and all
61 release-preflight checks pass. The disk-image test verifies failed save and
delete preservation, successful retries of both operations after releasing
space, and no partial output; the harness confirms execution and clean detach.

Artifacts are retained in `/tmp/aagedal-review-recovery-verified-20260910`,
including `Tests.xcresult`, `tests.json`, `run.log`, `volume.plist`,
`environment.txt` and `status.txt`. Static-analysis and preflight evidence are
`/tmp/aagedal-review-queue-analyze-20260910.log` and
`/tmp/aagedal-review-recovery-preflight-final-20260910.log`.
