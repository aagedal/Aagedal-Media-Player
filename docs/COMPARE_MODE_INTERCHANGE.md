# Compare Mode marker interchange validation

Automated exporter tests verify rational marker timing, drop-frame labels,
escaping, ordering, classifications, inclusive ranges, and format limits. Importing and re-exporting through an
editor remains a separate acceptance gate. Record the exact app revision,
editor version, macOS version, source pair, and exported files for every run.
Use disposable editor projects and generated or permission-cleared media.

## Test cases

Use `scripts/generate-test-fixtures.sh` for the existing rate and timecode
fixtures. Keep the source media in place while importing: FCPXML references
source A's file URL. Notes belong to source A; source B's filename, aligned
timecode, and frame are carried in the note text. Severity, category, and status
labels are also carried in marker text; these are not editor-native workflow
fields. CSV appends `Severity`, `Category`, `Status`, and `A End Frame (Inclusive)`
after its existing columns. PDF reports show classification labels and the
inclusive A frame range beside the finding text.

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

## Evidence record

| Editor/version | Media/rate/start | Marker count | Frame accuracy | Text/duplicates | Re-export comparison | Result/artifacts |
| --- | --- | --- | --- | --- | --- | --- |
| Resolve | Pending | | | | | Not run |
| Final Cut Pro | Pending | | | | | Not run |
| Media Composer | Pending | | | | | Not run |

Do not mark editor acceptance complete until the relevant rows contain actual
results. Parser-based XCTest coverage does not establish editor compatibility.
