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

### Completed native continuation

The corrected Release app was exercised again after the Mac became available.
The migration sheet now shows its 320-point scroll area, wrapped source/copy
paths, visible note/rate details, complete explanations and both action buttons.
**Save and Use Migrated Copy** published the `-exact-EC037D84.json` copy and
the Review popover identified it as the active sidecar with all eight findings.

Independent inspection of the saved JSON verifies all note UUIDs, text,
classifications, creation timestamps, source identities and A/B frame indexes,
including inclusive range endpoints. Both stored rates are `30000/1001`, with
seconds recomputed exactly from those frame indexes. Both original movies and
the original sidecar still match every hash in `original-hashes.json`.

Native Resolve-marker export succeeded from the migrated copy. The save panel
default was `source-a_vs_source-b_review.edl`, and the actual file has a single
`.edl` extension and eight events. Its drop-frame boundaries and range durations
include frame 59 at `00:00:59;29` with duration 3, duplicate frame 60 at
`00:01:00;02`, and the final playable frame at `00:11:08;00`.

Exiting and reopening Compare Mode loaded the original sidecar as documented.
**Notes → Open Notes Copy…** then reopened the corrected copy explicitly; the
popover again displayed that copy's full path and all eight findings. Cancelling
a later copy picker retained the active review. This closes focused native
layout, save/adoption, explicit reopening and default EDL-name acceptance.
It does not complete editor import/re-export or full keyboard/VoiceOver coverage.

The final rebuilt app also passed a pending-edit export check. Keyboard Tab
navigation selected the existing frame-0 note in the migrated copy; its text
was replaced with `Native pending edit — æøå` without pressing Return.
The accessibility tree showed that draft while an independent disk read still
contained the old text. Selecting **Export → CSV Report…** then saved an
eight-row report containing the new text, and the active copy persisted it.
Original movie/sidecar hashes remained unchanged. This checks the native
text-to-export transition; delayed save failures and retry behavior are covered
by injected-store regressions, not an induced native filesystem failure.

### Final continuation verification

The final combined Release suite passed **513 tests with zero failures** in
114.991 seconds (115.250 including suite overhead), including both original ITU
reference sets. Release static analysis and all 61 release-preflight checks pass.
Artifacts are `/tmp/aagedal-review-final-full-20260909.xcresult`, its adjacent
log, and `/tmp/aagedal-review-final-analyze-20260909.log`. No app source changed
after this verification; subsequent edits only record evidence and remaining work.

### Earlier Phase 66–67 verification

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

## Native failure and retry continuation — 2026-09-10

The rebuilt Release app was checked on macOS 27.0 (26A428) using disposable
29.97 source pairs generated by `generate-review-interchange-fixtures.py`.
The app contains the Phase 69 production code and the two Phase 70 controller
regressions. Interaction used native menus, pickers, keyboard text entry and
accessibility actions; screenshots confirmed both failure alerts were readable.
This is focused native failure/retry acceptance, not spoken VoiceOver or a
complete keyboard-only workflow.

### Corrupt copy opening

At `/tmp/aagedal-interchange-20260910`, `retry-copy.json` initially contained
invalid JSON. **Notes → Open Notes Copy…** displayed **Could Not Complete
Review Action**, explaining that the data was not in the correct format.
Dismissing the alert retained all eight findings and the original active path;
the review popover also retained the error until a successful action.
Original source and sidecar hashes still matched the fixture manifest.

Only the disposable retry file was then repaired by copying the original
sidecar bytes. Repeating the native copy-opening action succeeded, cleared the
error, and showed **Sidecar: retry-copy.json** with eight findings. Typing
`Native repaired-copy retry — æøå` in the new-note field and pressing Return
saved a ninth note to that copy. Independent JSON checks confirm the original
eight notes' fields remain preserved in the copy (UUID case normalizes on
encoding), while both source movies and the original eight-note sidecar still
match every original hash.

### Migration publication collision

At `/tmp/aagedal-migration-retry-20260910`, generated with
`--rate 29.97 --historical-rounded`, preview showed eight notes and a proposed
`-exact-20C46D51.json` copy. After preview, a disposable sentinel file was created
at that exact destination. **Save and Use Migrated Copy** refused publication
with a readable alert explaining that an existing file is never replaced.
The original review stayed active with eight findings and unchanged bytes.

Retrying **Migrate Rounded Timebases…** proposed a different
`-exact-2AC7764F.json` path. Saving succeeded and the popover identified that
copy as active, with the old error cleared. Independent checks confirm all
eight IDs, A/B frames, inclusive endpoints, text, classifications, creation
dates and source identities were retained; both rates became `30000/1001`
and seconds match `frame × 1001 / 30000`. The original movies/sidecar and the
conflicting sentinel file remain unchanged. No existing destination was removed
to make the retry pass.

The full Release suite passes **515 tests with zero failures and zero skips**,
including both original ITU reference sets, in 117.247 seconds (117.494 with
suite overhead). Release static analysis and all 61 release-preflight checks
pass. Artifacts: `/tmp/aagedal-continuation-full-final-20260910.xcresult` and
its log, `/tmp/aagedal-continuation-analyze-20260910.log`, and
`/tmp/aagedal-continuation-preflight-full-20260910.log`.

These results close the focused corrupt-copy and migration-conflict native
failure/retry checks. Broader keyboard/VoiceOver coverage, disk-full or
permission-denied native save failures, and actual NLE round trips remain open.
