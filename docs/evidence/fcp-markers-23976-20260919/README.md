# Final Cut Pro 23.976 native marker round trip — 2026-09-19

Result: **failed interoperability; export integrity guard implemented**.

Final Cut Pro 12.3 imported the unmodified `original.fcpxml` through Finder’s
Open command into a new disposable library, **Aagedal FCP Marker Acceptance
20260919**, under `/private/tmp/aagedal-resolve-23976-20260919`. File → Import →
XML left its Import button disabled in this run; Finder opening presented the
library chooser and completed the native import. The existing QuickEdit library
was not used for the import. File → Export XML exported the selected **Aagedal
Compare Review** event as version 1.14, General metadata, to
`fcp-roundtrip.fcpxmld`. `returned.fcpxml` is its unchanged `Info.fcpxml`.

The input was exported through the development app’s Review → Export → Final
Cut Pro Markers control, using the original **eight-finding** review from Phase
108, not the seven-finding Resolve copy. The existing September 19 Debug build
was used before this phase’s guard was added. All eight exported anchors and
inclusive durations match the original review. The input passes Final Cut’s
bundled `FCPXMLv1_9.dtd` using `xmllint --dtdvalid`.

Native re-export contains only **five** markers:

| Marker | Relative frame | Duration | Result |
| --- | ---: | ---: | --- |
| QC 001 | 0 | 1 | Retained |
| QC 002 | 1 | 1 | Retained |
| QC 003 | 1439 | 3 | Retained |
| QC 004 | 1440 | 1 | Missing |
| QC 005 | 1440 | 1 | Missing |
| QC 006 | 14399 | 3 | Retained |
| QC 007 | 14400 | 1 | Missing |
| QC 008 | 14624 | 1 | Retained |

The missing markers fall inside the retained three-frame ranges. The result
supports rejecting overlapping marker intervals, including shared anchors,
until a lossless representation is verified. It does not independently isolate
Final Cut’s behavior for duplicate points without an enclosing range. The new
guard conservatively rejects that case too. It preserves the original review
and recommends CSV/PDF rather than merging, shifting, or shortening findings.

`native-roundtrip-comparison.json` records exact file hashes and missing records.
All four fixture inputs still match the retained manifest. Final Cut copied
source A into its library; that imported file’s SHA-256 matches source A.
The manifest’s selected `reviewFile` still describes the earlier Resolve copy;
this run deliberately selected `original-review.json` (original filename and
hash are recorded in the manifest) and checked all eight original notes.

Additional open issues exposed by the re-export:

- Final Cut writes literal tab/newline characters into XML attributes. Standard
  XML parsing normalizes those characters to spaces; exact parsed note text
  therefore differs for all five surviving markers. Input uses numeric entities.
- The source asset has the correct 160×90 raster, but Final Cut assigned the
  browser clip a 1280×720 format because the input format only supplied its
  frame duration. Native source-raster preservation remains unaccepted.
- Final Cut clamps the declared clip duration from 14,626 to the actual 14,625
  frames. The app’s duration rounding needs separate investigation.

No passing FCP interoperability claim follows from the export guard. Repeat
with non-overlapping findings, then cover fractional DF rates/source starts,
source raster and text fidelity. Avid acceptance remains separate.

Validation: all 30 `CompareReviewReportExporterTests` pass, including new
rejections for duplicate anchors, range interiors, inclusive endpoints and
nested ranges, preservation in CSV/PDF, and adjacent non-overlapping exports.
Result bundle: `/private/tmp/aagedal-phase109-exporter-tests-retry.xcresult`.
