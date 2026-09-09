# Historical review migration check — 2026-09-09

The local Release build was exercised on macOS 27.0 using a disposable 29.97
drop-frame source pair and eight historical review findings. Both movies encode
`30000/1001` fps; the notes store `2997/100` and matching portable seconds.
No production reviews or media were edited.

## Reproduce

```bash
python3 scripts/generate-review-interchange-fixtures.py \
  /tmp/new-historical-review --rate 29.97 --historical-rounded
```

The generator also supports 59.94 and 23.976; the latter has no embedded source
timecode. Its manifest distinguishes exact media rates from historical stored
rates. A complete generated 23.976 run was checked for all eight notes, stored
rates and seconds, and manifest values during this continuation.

Open A, compare B, then choose **Review → Notes → Migrate Rounded Timebases…**.
Check the original and destination paths and each note's retained frame/range,
old/new rate and seconds. Cancel once and verify there is no new copy. Then
preview again, save the migrated copy, and verify the original hashes remain
unchanged. Export editor markers and inspect their frame positions. Reopen the
pair and use **Notes → Open Notes Copy…** to select the corrected copy explicitly.

## Observed native results

The native fixture at `/tmp/aagedal-native-migration-20260909` loaded all eight
findings with playback paused at `00:00:58;00`. The Notes menu exposed both
copy opening and migration; relinking stayed disabled for the nonempty review.

The migration preview's accessibility tree contained all eight findings and
their original/copy paths. It showed `2997/100 → 30000/1001`, retained both
sources' final frame 18280, and recomputed its seconds from `609.943276610` to
`609.942666667`. It also preserved the inclusive range 16241–16243 and both
independent findings at frame 60. No copy existed during preview.

A native screenshot exposed a layout failure: the sheet collapsed to 660×213
points, hiding its scroll area and truncating explanations. Cancel dismissed
the preview. Independent hash checks confirmed the original sidecar and both
movies remained unchanged and no `-exact-*.json` copy existed.

The confirmation view now reserves a 320-point scroll area and wraps its
explanations and note text. The corrected view builds and passes Release static
analysis. Before its native recheck, the Mac locked and the automation tool
reported that automatic unlock could not unlock it. The final layout, native
save/adoption, explicit reopening, and default EDL filename therefore remain
unverified; this record does not claim those native passes. Automated store and
controller coverage exercises those persistence paths separately.

## Integrated verification

The full Release suite passed **503 tests with zero failures**, with both
original ITU reference sets enabled. It took 115.063 seconds (115.336 including
suite overhead). It includes 47 WAVE reader tests and 18 migration model/store/
controller tests. The migration regressions cover known/reduced rates, retained
fields and inclusive bounds, stale reviews and replaced sources, cancellation,
exclusive publication, conflicts and dangling links, copy reopening, subsequent
edits, editor exports, and fractional timestamp persistence equivalence.

That full suite preceded the final view-only layout correction. The corrected
view then passed a fresh Release build and static analysis. Release preflight
passed all 61 checks; package revisions and bundled binaries were unchanged.

Temporary artifacts:

- `/tmp/aagedal-migration-utf16-full-20260909.xcresult` and its adjacent log.
- `/tmp/aagedal-migration-layout-build-20260909.log`.
- `/tmp/aagedal-migration-layout-analyze-20260909.log`.
- `/tmp/aagedal-migration-utf16-preflight-20260909.log`.
- `/tmp/aagedal-migration-fixture-generator-20260909` and its generator log.

The committed generator and tests provide reproduction when temporary files
are removed. Full Keyboard Access, spoken VoiceOver, and actual NLE import/
re-export acceptance remain open.
