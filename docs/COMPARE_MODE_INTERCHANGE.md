# Compare Mode marker interchange validation

Automated exporter tests verify rational marker timing, drop-frame labels,
escaping, ordering, classifications, inclusive ranges, and format limits. Importing and re-exporting through an
editor remains a separate acceptance gate. Record the exact app revision,
editor version, macOS version, source pair, and exported files for every run.
Use disposable editor projects and generated or permission-cleared media.

## Test cases

For a reproducible eight-finding editor acceptance review, run:

```bash
python3 scripts/generate-review-interchange-fixtures.py /tmp/new-review-fixtures --rate 29.97
```

The new directory contains a 610-second generated source pair, a schema-2
sidecar, and a manifest with input hashes. Open source A and compare source B,
then export CSV and the desired editor format through the app. The findings
cover first/adjacent/final frames, duplicate positions, Unicode and multiline
text, every classification, and one/three-frame inclusive ranges. The 29.97
and 59.94 variants start at `00:00:58;00` and straddle both minute and ten-minute
drop-frame boundaries. `--rate 23.976` omits embedded source timecode. The
generator uses Foundation's canonical paths to match the app's sidecar identity
rules, including macOS's `/tmp` alias. Existing directories are rejected.

Add `--historical-rounded` to generate a migration acceptance review: media
keeps its exact rate, while both note snapshots use the old three-decimal
timebase and corresponding seconds. Frame ordinals and inclusive endpoints stay
the same. The manifest distinguishes stored note rates from source rates. This
option works with all three `--rate` choices and leaves the default exact-rate
fixture behavior unchanged.

Fixture generation and successful app exports do not establish editor acceptance.

For a repeatable read-only check of Resolve's loaded media and marker records,
open **Workspace → Console**, select Lua, and run this helper after native import
(substitute the checkout and new evidence paths):

```lua
dofile("/path/to/checkout/scripts/capture-resolve-marker-snapshot.lua")("/path/to/fixtures/native-snapshot.json")
```

The helper does not create/import markers. It records the editor version,
project/timeline names, frame-count mode, start/end frames, V1 clip identity and
placement, and every timeline marker's anchor, duration, color, name and note.
It refuses an existing output path. The native marker import and re-export
remain editor actions; do not substitute scripted `AddMarker` calls for them.
Pass `--native-snapshot /path/to/fixtures/native-snapshot.json` together with
`--fixture-manifest` to the EDL comparator after native re-export. Validation
requires one full, untrimmed source-A clip on a single video track, exact fixture
start/rate/duration, and every expected marker record. Source B remains note
provenance; it is not claimed to be loaded in Resolve. Keep the original
snapshot and both EDLs unchanged beside the workflow record.

As of September 19, Resolve EDL export deliberately rejects this full fixture's
same-frame findings. Confirm that the error identifies source A frame 60 and
recommends CSV/PDF, and retain the complete CSV as the lossless reference.
For further Resolve acceptance, add `--resolve-copy` to generate a separate
`resolve-unique.aagedal-compare.json` with seven unique start frames. Open it
through **Notes → Open Notes Copy…** before exporting. Only Fixture 5 (the
duplicate minute-boundary anchor) is omitted; all other finding fields stay
unchanged. The manifest records its ID, both review hashes, and the selected
copy's count. The original eight-finding sidecar remains the default review.
That reduced diagnostic does not establish complete eight-finding acceptance.

Decimal metadata rates within 0.001 fps of a known broadcast rate use its
exact rational timebase, matching the existing timecode engine. Explicit
fractions remain exact. The September 9 correction fixes decoded decimal
rates previously rounded to thousandths of a frame per second, which caused
false editor-export mismatches and missing source timecodes. Historical review
notes retain their stored rates. If they use the former rounded fractions,
CSV/PDF preserve them but editor export refuses the differing timebase; no
automatic migration is performed. **Review → Notes → Migrate Rounded
Timebases…** now previews a deliberate correction for recognized historical
broadcast decimals. It preserves recorded frame numbers and inclusive ranges,
saves a new sidecar, and activates that copy for edits and exports. The original
remains unchanged. Use **Notes → Open Notes Copy…** to reopen a migrated copy
in a later session. See [the sidecar migration workflow](COMPARE_REVIEW_SIDECAR.md).

Use `scripts/generate-test-fixtures.sh` for the existing rate and timecode
fixtures. Keep the source media in place while importing: FCPXML references
source A's file URL. Notes belong to source A; source B's filename, aligned
timecode, and frame are carried in the note text. Editor notes also retain both
current source URLs and each finding's stored rational A/B rates. B timecode
is explicitly labelled SRC or REL so missing or incompatible metadata cannot
make relative positions look like source timecodes. Severity, category, and status
labels are also carried in marker text; these are not editor-native workflow
fields. CSV appends `Severity`, `Category`, `Status`, and `A End Frame (Inclusive)`
after its existing columns, followed by `A Rate Numerator`, `A Rate Denominator`,
`B Rate Numerator`, `B Rate Denominator`, `Source A URL`, and `Source B URL`.
The rate columns preserve each note's stored capture timebase exactly, including
when replacement media has different metadata. The URLs distinguish equal
filenames in different directories; they identify the currently loaded source
pair, while the JSON sidecar retains filesystem identity. These appended fields
leave the original column positions intact. PDF reports show classification
labels and the inclusive A frame range beside the finding text.

Report relative timecodes are derived from each finding's stored frame and
rational rate, even after relinking to shorter media. Source timecodes are
shown only when the current source rate agrees with the stored rate; otherwise
they are unavailable. Reports do not retime findings to replacement metadata.
If either recorded A/B frame is outside the available media duration, the PDF
keeps the finding and explains that its still is unavailable rather than
substituting a different frame.

For each supported target editor, create a review containing:

- Notes on the first frame, adjacent frames, and the final playable frame.
- A source with a nonzero embedded start timecode and a source without one.
- Fractional-rate media, including 29.97 and 59.94 drop-frame notes immediately
  before and after a minute boundary. Include a ten-minute boundary where the
  source duration permits it.
- Range findings with an end equal to the start, a multi-frame range, and a
  range spanning a drop-frame minute boundary. Include all classification
  values and verify them against the CSV.
- Multiple notes at the same frame and notes entered out of timeline order.
- Unicode, quotes, ampersands, tabs, and multiline text. FCPXML preserves tabs
  and line breaks; EDL and Avid flatten line breaks, Avid flattens tabs, and
  EDL replaces the `|` delimiter. XML-invalid characters become `�`.

Save the pair-specific JSON sidecar and a CSV report as the comparison record
before exporting the target marker format.

## Import and round trip

### Installed editors available for acceptance — 2026-09-19

The user confirms that Final Cut Pro, Adobe Premiere Pro, and Avid Media
Composer First are installed alongside Resolve. Record exact versions when
running each check; installation alone does not establish format compatibility.

- Final Cut Pro: continue the existing FCPXML import/re-export gate. Earlier
  launch-automation timeouts do not mean the editor is unavailable.
- Premiere Pro: investigate a supported marker interchange path and retain
  native results before claiming support. The app currently has no dedicated
  Premiere exporter; Resolve marker EDL extensions must not be assumed compatible.
- Media Composer First: the user observed that EDL import was unlocked. Exercise
  that available path in a disposable project and check whether it imports review
  markers or only edit events. Separately check availability of the app's existing
  Avid marker-text import workflow. Record First-specific limitations and do not
  generalize its results to full Media Composer.

These installed applications provide additional native acceptance routes. An
enabled EDL import command does not yet prove marker text, ranges, or source
identity survive import; inspect the resulting records and re-export where available.

| Target | Export | Expected marker anchor |
| --- | --- | --- |
| DaVinci Resolve | Marker EDL | A's source timecode, or relative zero when unavailable; inclusive range duration, or one frame for a point finding |
| Final Cut Pro | FCPXML | Browser clip for source A, rational source start plus relative frame, explicit DF/NDF display and one-frame duration; inclusive ranges retained in note text; same-frame findings grouped |
| Avid Media Composer | Marker text | Zero-based source-A relative start frame on V1; inclusive range annotated in marker text |

1. Import source A into a fresh editor project with the matching rate and
   timecode interpretation. Import the exported markers using the editor's
   supported marker/clip interchange workflow. Record that workflow because
   import destinations and behavior vary by editor version.
2. Check every marker against the CSV's primary frame and source/relative
   timecode, especially adjacent frames and drop-frame boundaries. Confirm
   count, text, classification labels, source identity, and any duplicate-frame
   behavior. Check that range duration is `end − start + 1` frames in Resolve. Final Cut
   uses one-frame markers, retaining inclusive range endpoints in the note and
   grouping same-frame findings with individual labels; verify every finding
   inside each group. Avid retains the textual inclusive range. A file
   importing without errors is not sufficient evidence of correct timing.
3. Re-export the markers where supported. Compare frame positions and note
   content with the saved record; retain both exports. If the editor cannot
   re-export the format, record the limitation and retain visible frame/count
   evidence instead of claiming a completed round trip.
4. Confirm the source media and original review sidecar were not changed.

For Resolve, compare the **unmodified** app EDL and native re-export with:

```bash
python3 scripts/validate-resolve-marker-roundtrip.py original.edl returned.edl \
  --rate 30000/1001 --editor-version 21.1.0.14 --output new-roundtrip-result.json
```

For newly generated fixtures, also pass
`--fixture-manifest /path/to/fixture-manifest.json`. This verifies the hashes
of both media files and both reviews (when a Resolve copy exists), confirms the
selected review's source paths still identify the current media, and requires
every original/returned EDL marker's appended A/B URLs to identify those files.
It also checks the exact manifest rate and selected review count. Changed inputs,
stale paths after a move, missing provenance, or old manifests without the selected
review fields fail validation. Regenerate fixtures at their intended location;
do not rewrite historical evidence to make it pass. The output retains the
manifest hash and verified input hashes. This is file provenance evidence;
native editor media loading and correct timeline setup still require observation.

The next 59.94 DF run can be prepared with:

```bash
python3 scripts/generate-review-interchange-fixtures.py /tmp/new-resolve-5994 \
  --rate 59.94 --resolve-copy
```

Export from the app using that notes copy, import into a fresh 59.94 DF editor
timeline starting at `00:00:58;00`, and compare the unmodified native re-export
at `--rate 60000/1001` with its fixture manifest. Retain native source-media
identity evidence as well as the comparison JSON before accepting this row.

Use the exact rational media rate and actual editor version. The checker exits
nonzero for missing, additional, moved, or changed markers; it retains both
file hashes and complete mismatched records in a new JSON report. It compares
record anchors, `|D:` inclusive duration, color and exact note content (including
classifications and source URLs), preserving duplicate multiplicity. It accepts
Resolve's colon-separated DF labels under `FCM: DROP FRAME` and its one-frame
event spans for range markers. Unrecognized or incomplete EDL records fail
validation rather than being skipped. Event numbers and titles are not marker
identity. Do not remove negative or unwanted events before running the check.

A passing file comparison does not prove the native workflow, original CSV
correctness, media identity, or editor version. Retain those separately using
the steps above. A deliberately reduced diagnostic EDL only establishes results
for its included findings. The checker rejects the retained September 15
eight-finding round trip with three missing exact records and eight unexpected
records (including the displaced finding and seven negative-frame leftovers).

FCPXML range durations use source A's rational metadata rate, just like marker
start positions. Resolve's event out is exclusive and its `|D:` field carries
the inclusive frame count. Avid's five-column marker text retains a point
anchor and includes `A frames start–end (inclusive)` in its text; no native
Avid range duration is claimed.

Resolve EDL rejects multiple findings starting at the same source-A frame.
The retained Resolve import lost a same-frame finding, so the exporter now
fails with an actionable CSV/PDF alternative rather than producing an EDL that
can silently lose review content. It does not merge findings, shift their
coordinates, or alter the sidecar. Point and range findings with the same start
are both covered; overlapping ranges with distinct starts remain exportable.
This guard does not resolve the separately observed adjacent-frame import issue.

Resolve EDL deliberately rejects more than 999 markers and rates above 60
nominal fps. Verify that these failures remain actionable in the app. Keep
unsupported cases distinct from failed imports at supported rates.
EDL also rejects a marker whose source position or exclusive end reaches or
passes the 24-hour timecode boundary, including the final frame before
midnight. This prevents wrapped labels from aliasing another timeline position.
CSV/PDF preserve frame coordinates, and FCPXML/Avid use rational times or
frame positions; use those formats for these findings. Include a near-midnight
source in acceptance tests and verify the EDL failure before publication.

Avid export rejects marker text exceeding the app's 32,000-character export
limit after flattening line breaks and tabs. This includes appended provenance
and classification fields. Shorten the note or select CSV, PDF, or FCPXML;
findings are never silently truncated to meet this limit.

## Evidence record

### Native export correction — 2026-09-09

On macOS 27.0, the generated 29.97 pair under
`/tmp/aagedal-fcpxml-20260909-final` reproduced an editor-export rejection in
the retained September 8 Release build: metadata reported a rounded decimal
fraction while the eight findings stored `30000/1001`. Its CSV omitted source
timecodes. The rebuilt September 9 app then opened the unchanged pair/sidecar,
showed all eight findings and saved `source-a_vs_source-b_review.fcpxml` plus
the separate `corrected-review.csv` through native menus/save panels.

Parsing the saved bytes verifies all eight positions/durations, note text
(including Unicode, tabs and line breaks), classifications and both source
URLs. FCPXML has `1001/30000s` frame duration and `DF` display. Representative
source-A coordinates are:

| Relative frame | Source timecode | Inclusive duration |
| --- | --- | --- |
| 0 / 1 | 00:00:58;00 / 00:00:58;01 | One frame each |
| 59 | 00:00:59;29 | Three frames |
| 60 (two findings) | 00:01:00;02 | One frame each |
| 16241 | 00:09:59;29 | Three frames |
| 16242 | 00:10:00;00 | One frame |
| 18280 | 00:11:08;00 | Final playable frame |

Both movies and the original sidecar match their manifest hashes after export.
`native-export-validation.json` records the assertions' results and output
hashes in that disposable directory. The 59.94 and 23.976 fixture-generation
variants also complete; the native export check above is specifically 29.97.
Generated-media XCTest separately verifies both 29.97/59.94 drop-frame rates,
source labels and all four text-based report formats. All 479 Release tests,
static analysis and 61 release-preflight checks pass.

Final Cut Pro launch automation timed out before an editor project opened.
No import or re-export was performed, and no editor acceptance row below is
marked passed. The native export result is independent of that outstanding gate.

| Editor/version | Media/rate/start | Marker count | Frame accuracy | Text/duplicates | Re-export comparison | Result/artifacts |
| --- | --- | --- | --- | --- | --- | --- |
| Resolve Studio 21.1.0.14 | Generated 29.97 DF / `00:00:58;00` | 6/8 in-range after corrected import | Five surviving anchors exact; Fixture 2 moved from frame 1 to frame 0 | Unicode/URLs and range durations retained; Fixtures 1 and 5 absent | 13 events: 7 from the earlier wrong-start import plus 6 in-range | Partial; see September 15 evidence below |
| Resolve Studio 21.1.0.14 | Fresh generated 29.97 DF / `00:00:58;00`; seven-finding diagnostic | 7/7 | All anchors exact, including first/adjacent and DF boundary frames | Exact text, colors and durations retained; duplicate finding deliberately omitted | 7/7 exact records, no missing or extra events | Focused pass; historical URLs and other rates remain outside this result; see September 19 evidence below |
| Resolve Studio 21.1.0.14 | Fresh generated 59.94 DF / `00:00:58;00`; current-source seven-finding copy | 7/7 | All anchors exact, including first/adjacent/final and DF boundary frames | Exact text, colors, ranges and current URLs retained; actual source-A media/placement verified | 7/7 exact records; unchanged fixture hashes | Focused round-trip pass; [retained evidence](evidence/resolve-markers-5994-20260919/README.md) |
| Final Cut Pro | Pending | | | | | Not run |
| Resolve Studio 21.1.0.14 | Generated 23.976, no embedded TC; zero-start timeline and current-source seven-finding copy | 7/7 imported | All actual anchors and durations exact; current source-A placement verified | Exact text, colors and current URLs retained; unchanged fixture hashes | 7/7 exact records; unchanged fixture hashes | Focused round-trip pass; [retained evidence](evidence/resolve-markers-23976-20260919/README.md) |
| Adobe Premiere Pro | Pending | | | | | Installed per user; interchange path not yet validated |
| Media Composer First | Pending | | | | | Installed per user; EDL import observed unlocked; marker behavior not yet tested |
| Media Composer | Pending | | | | | Not run |

### Resolve preparation — 2026-09-09 continuation

The native player exported the unchanged eight-finding fixture as
`/tmp/aagedal-fcpxml-20260909-final/resolve-marker-acceptance.edl` (4,312 bytes,
SHA-256 `00190f47a33dcc91f0fe1be208c2194113afcd57f7b7ec074fabf514a78db3fc`).
The EDL contains eight events, and source movies/original sidecar still match
their fixture-manifest hashes. Resolve Studio 21.1.0 (21.1.00014) opened a new
disposable project, **Aagedal Marker Acceptance 20260909**, imported source A,
and accepted 29.97 fps. Its source viewer showed `00:00:58;00` through
`00:11:08;00`. Native automation did not complete marker import or re-export;
the acceptance table therefore remains pending. Final Cut Pro launch again
timed out before an import workflow was available.

Do not mark editor acceptance complete until the relevant rows contain actual
results. Parser-based XCTest coverage does not establish editor compatibility.

### Native Resolve export repeat — 2026-09-15

The current unsigned Release build at `3c1d39e` opened a fresh generated
29.97 drop-frame pair in `/private/tmp/aagedal-review-editor-acceptance-20260915`.
Comparison Review loaded all eight findings from the untouched schema-2
sidecar. Native Save panels wrote `source-a_vs_source-b_review.edl` and
`source-a_vs_source-b_review.csv`; the player reported both saves complete.
`native-export-validation-20260915.json` checks eight ordered CSV/EDL anchors,
the adjacent and duplicate positions, minute/ten-minute drop-frame labels,
one-/three-frame inclusive durations, and source-media/sidecar manifest hashes.
The EDL SHA-256 is
`93c714a3f6181ff5ad3629feb74f2408308a290446b2d10a24653aa6d62869b6`;
the CSV SHA-256 is
`10ff29423713fb37815c5c74c2feba4591c056f50535d56d6185b532bb29bf56`.

Resolve Studio 21.1.0.14 on macOS 27.0 opened to its Project Manager; a
project-name popup was not visible to automation, so the user opened an empty
disposable project, `New Project 1`. The generated source A imported, Resolve
changed the project rate to 29.97 fps, and Append placed the complete clip on
`Timeline 1`. Its source viewer showed `00:00:58;00` on the first frame. The
media-pool timeline's custom right-click menu did not appear to automation;
the user used **Timelines → Import → Timeline Markers from EDL** and the native
file picker to import the saved EDL.

The first import occurred while `Timeline 1` still started at
`01:00:00;00`; Resolve placed seven findings at negative timeline frames. The
user changed its starting timecode to `00:00:58;00` and repeated the proper
marker import. Resolve's built-in timeline-marker API then reported six
in-range markers at frames 0, 59, 60, 16241, 16242 and 18280, alongside the
seven earlier negative-frame markers. The frame-0 marker carries Fixture 2's
text, whose saved A frame is 1. Fixtures 1 and 5 are absent from the corrected
import. Fixtures 3 and 6 retain three-frame `|D:` durations; the other four
survivors retain one-frame durations. Their Unicode text, classifications and
both source URLs remain present. The exact API dump and assertions are saved
as `resolve-marker-api-20260915.tsv` (SHA-256
`84dab192ca051a513f843ca44b3534399eb0358246b72e487c4cc468d3686d27`)
and `resolve-import-validation-20260915.json` in the disposable fixture
directory.

The user exported **Timelines → Export → Timeline Markers to EDL** to
`resolve-roundtrip.edl` (SHA-256
`86926772d61d5394ffa5dd3363c6c6582919651e14e576fa9a7ba08b10cb1ac0`).
Its 13 events match the API count: seven negative-frame events from the
wrong-start import and six corrected in-range events. Resolve writes one-frame
CMX event spans for range findings while retaining `|D:3`; it also writes
colon-separated timecode fields under `FCM: DROP FRAME`. The six in-range
events retain Unicode, classifications and both source URLs. The generated
movies and original sidecar still match every manifest hash after re-export;
`resolve-roundtrip-validation-20260915.json` records the checks.
The small original and round-trip exports, API snapshot, manifest and validation
records are also [committed as reviewable evidence](evidence/resolve-markers-20260915/README.md);
the generated movies and disposable Resolve project stay outside the source tree.

This is a **partial interoperability result**, not an accepted eight-finding
round trip. Repeat in a fresh timeline with the correct start before any import
to isolate the adjacent-frame collision from prior import state. Determine
whether same-frame findings require a grouped marker representation or an
explicit Resolve export limitation; do not silently treat missing findings as
accepted. Final Cut Pro and Avid import/re-export remain unrun.

### Fresh-timeline preparation and repeatable comparison — 2026-09-19

A new disposable Resolve project, **Aagedal Adjacent Marker Acceptance
20260919**, contains generated source A in **Unique markers semicolon**, set
to 29.97 DF and `00:00:58;00` before any marker import. Generated media and its
intact eight-finding sidecar are under
`/private/tmp/aagedal-resolve-adjacent-20260919`.
`unique-markers.edl` is the retained September 15 app export with only event
005 (Fixture 5, the duplicate at relative frame 60) omitted. Its SHA-256 is
`0536d12ccd301f0dab0dc2f28d72bd80029cb989f656432ec88ec15a0a902929`.
The diagnostic deliberately retains the historical note URLs; it is a timing
investigation, not a new app export or current-source provenance acceptance.

The user completed the native marker import through Resolve’s custom timeline
menu. Resolve’s API reports exactly seven markers at relative frames 0, 1, 59,
60, 16241, 16242 and 18280. All anchors, exact marker text (including Unicode,
tabs, classifications and historical URLs), colors and one-/three-frame
durations match the diagnostic EDL. The original generated movies and
eight-finding sidecar still match their manifest hashes. The adjacent-frame
displacement does not reproduce in this clean, correct-start import; no
coordinate change to the app exporter is warranted by this result. The earlier
failed import remains historical evidence, with its cause not established.
The user completed native **Timeline Markers to EDL** re-export. Its 3,956 bytes
have SHA-256 `7939e17ae765f1efb723adc2aaf3c2093eff11f41e1f783cbaecfd92e184d256`.
Strict comparison passes all seven exact marker records with no missing or
unexpected events, and post-export hashes confirm unchanged movies and original
sidecar. The [retained round-trip evidence](evidence/resolve-markers-20260919/README.md)
qualifies this focused pass separately from complete editor acceptance. The comparator's
regressions cover rejection of the actual retained partial round
trip, DF minute/ten-minute boundaries at both supported DF rates, exact content,
duration, duplicate multiplicity and malformed-input rejection. The complete
script-validator suite passes. Other rates, current-source provenance, and
Final Cut Pro/Avid acceptance remain open; same-frame Resolve findings remain
explicitly rejected.

### Final Cut Pro native range-overlap loss — 2026-09-19

Final Cut Pro 12.3 imports the full eight-finding 23.976 review through Finder
Open into a disposable library, but native event re-export retains only five.
The three missing findings lie inside inclusive ranges. FCPXML export now
rejects overlapping intervals, including shared anchors and inclusive endpoints,
and recommends CSV/PDF. It does not silently shorten ranges or merge findings.
Adjacent non-overlapping intervals remain exportable.

The [retained native record](evidence/fcp-markers-23976-20260919/README.md)
includes the unchanged exports, review, fixture manifest and comparison report.
Original inputs and the library’s imported media copy match their source hashes.
Native re-export also changes parsed whitespace and assigns a default browser
clip raster; duration clamping remains to be investigated. Final Cut acceptance
is **not passed**. Repeat with non-overlapping findings and the other rate/start
cases after resolving or explicitly qualifying those issues.

Apple documents [native XML interchange](https://support.apple.com/guide/final-cut-pro/use-xml-to-transfer-projects-verdbd66ae/12.3/mac/15.6)
and [XML attribute/time structure](https://developer.apple.com/documentation/professional-video-applications/document-type-definition).
DTD validation alone does not establish a lossless native round trip.

### One-frame markers and grouped findings — 2026-09-19

Phase 110 supersedes the overlap guard above. FCPXML now emits one one-frame
marker per distinct start frame, with inclusive ranges preserved in note text.
Same-frame findings share a marker whose title lists their QC numbers and count;
each complete finding is separately labelled in the note. This follows Apple’s
[one-frame marker contract](https://developer.apple.com/documentation/professional-video-applications/associating-ratings-keywords-markers-and-metadata-with-media).
No finding is moved or removed from the review, and no keyword ranges are added.

A native Final Cut Pro 12.3 import/re-export of the production-exporter fixture
retains all eight findings in seven markers with matching coordinates and titles.
All note content matches after the specifically documented XML tab/CR/LF
attribute normalization. Exact whitespace, raster/duration and other-rate gates
remain open. See [the retained verification](evidence/fcp-grouped-markers-23976-20260919/README.md)
for the production-test generation route and native editor steps.

### Explicit Final Cut raster — Phase 111

FCPXML now supplies source A's coded width/height and, when available and valid,
pixel aspect ratio (`paspH`/`paspV`). This addresses the missing format metadata
behind the observed 160×90-to-1280×720 browser-clip default. Incomplete or invalid
geometry remains omitted; display dimensions are not substituted for coded
pixels. The retained-fixture test now declares the actual 160×90 source raster.

This is an exporter correction pending a fresh native player export and Final
Cut import/re-export. Portrait, anamorphic and rotated-source native behavior,
duration clamping, whitespace and the remaining rate matrix remain open.

### Native raster and repeatable comparison — Phase 112

Final Cut Pro 12.3 now natively preserves the Phase 111 fixture's 160 × 90 browser
clip, exact 23.976 rate/start/NDF display and all eight findings in seven markers.
The imported source media and original fixture hashes match. The new
`scripts/compare-fcp-marker-roundtrip.py` records exact rational comparisons and
returns nonzero for remaining duration and parsed-whitespace differences.
The 14,626 → 14,625 duration difference reflects the XCTest snapshot's 610-second
duration versus the generated media's 14,625 frames; production metadata and
native player export still need verification. Portrait/anamorphic/rotated and
other-rate acceptance remain open. See the [retained native evidence](evidence/fcp-raster-markers-23976-20260919/README.md).

### Native player duration correction — Phase 113

A native player UI export reproduced the extra duration frame with actual media
metadata. The exporter now uses a positive metadata frame count when a video
rate exists and the count agrees within one frame of the duration estimate.
After rebuilding, the player UI and Final Cut Pro 12.3 native re-export both
retain 14,625 frames, 160 × 90, exact 24000/1001 timing, seven marker anchors and
all eight findings. Original media and sidecars remain unchanged. Exact parsed
note whitespace remains different and the comparator still returns nonzero.
This closes the focused duration/native-player gap for this source, not the
remaining rate, transformed-media or full editor gates. See the
[retained evidence](evidence/fcp-native-duration-23976-20260919/README.md).

### Native Final Cut 59.94 DF — Phase 114

Native player export and Final Cut Pro 12.3 import/re-export preserve source
start 00:00:58;00, 60000/1001 rate, DF display, 160 × 90 raster and 36,563-frame
duration. All eight findings survive at seven anchors, including the grouped
pair, drop-frame boundaries and last source frame. Media bytes and original
review hashes match. Exact whitespace remains the only comparator failure;
all ten Python regressions pass. See [retained evidence](evidence/fcp-native-markers-5994-20260919/README.md).
Other rates, portrait/anamorphic/rotated media and broader editor acceptance stay open.

### Independent Final Cut asset-format verification — Phase 115

Ten actual generated geometry fixtures now pass the production metadata/exporter
regression. A native 24 fps rotated anamorphic round trip retains all three point
findings, duration, browser-clip format and original media bytes, but changes the
asset raster from 240 × 180 to 180 × 240 while retaining 4:3 PAR. The comparator
previously missed this because it only inspected the browser-clip format. It now
compares asset raster, PAR and frame duration independently and returns nonzero
for this case. Native display-aspect correctness and the appropriate treatment
of the changed asset format remain unresolved; no shipping exporter adjustment
is inferred solely from this difference. See [retained evidence](evidence/fcp-rotated-anamorphic-20260919/README.md).

### Oriented browser formats — Phase 116

Quarter-turn sources now export oriented raster dimensions and inverted pixel
aspect ratio, preserving the source's display aspect without adding a second
rotation. Real generated fixtures and signed/negative rotation cases pass.
A Final Cut Pro 12.3 diagnostic import/re-export preserves that browser format,
all three point findings and media bytes, but rewrites asset PAR. Production XML
matches the diagnostic apart from names; a rebuilt player UI repeat and timeline
conform check remain open. See [retained evidence](evidence/fcp-oriented-anamorphic-20260919/README.md).
