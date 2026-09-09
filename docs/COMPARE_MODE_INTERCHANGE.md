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

Fixture generation and successful app exports do not establish editor acceptance.

Decimal metadata rates within 0.001 fps of a known broadcast rate use its
exact rational timebase, matching the existing timecode engine. Explicit
fractions remain exact. The September 9 correction fixes decoded decimal
rates previously rounded to thousandths of a frame per second, which caused
false editor-export mismatches and missing source timecodes. Historical review
notes retain their stored rates. If they use the former rounded fractions,
CSV/PDF preserve them but editor export refuses the differing timebase; no
automatic migration is performed.

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

| Target | Export | Expected marker anchor |
| --- | --- | --- |
| DaVinci Resolve | Marker EDL | A's source timecode, or relative zero when unavailable; inclusive range duration, or one frame for a point finding |
| Final Cut Pro | FCPXML | Browser clip for source A, rational source start plus relative frame, explicit DF/NDF display and rational inclusive range duration |
| Avid Media Composer | Marker text | Zero-based source-A relative start frame on V1; inclusive range annotated in marker text |

1. Import source A into a fresh editor project with the matching rate and
   timecode interpretation. Import the exported markers using the editor's
   supported marker/clip interchange workflow. Record that workflow because
   import destinations and behavior vary by editor version.
2. Check every marker against the CSV's primary frame and source/relative
   timecode, especially adjacent frames and drop-frame boundaries. Confirm
   count, text, classification labels, source identity, and any duplicate-frame
   behavior. Check that range duration is `end − start + 1` frames in Resolve
   and Final Cut Pro, and that Avid retains the textual inclusive range. A file
   importing without errors is not sufficient evidence of correct timing.
3. Re-export the markers where supported. Compare frame positions and note
   content with the saved record; retain both exports. If the editor cannot
   re-export the format, record the limitation and retain visible frame/count
   evidence instead of claiming a completed round trip.
4. Confirm the source media and original review sidecar were not changed.

FCPXML range durations use source A's rational metadata rate, just like marker
start positions. Resolve's event out is exclusive and its `|D:` field carries
the inclusive frame count. Avid's five-column marker text retains a point
anchor and includes `A frames start–end (inclusive)` in its text; no native
Avid range duration is claimed.

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
| Resolve | Pending | | | | | Not run |
| Final Cut Pro | Pending | | | | | Not run |
| Media Composer | Pending | | | | | Not run |

Do not mark editor acceptance complete until the relevant rows contain actual
results. Parser-based XCTest coverage does not establish editor compatibility.
