# Native Final Cut whitespace re-import — Phase 123

On 2026-09-20, Final Cut Pro 12.3 confirms that the previously observed XML
whitespace difference becomes actual note-formatting loss on native re-import.
The first import preserves tabs, newlines and the blank line between grouped
findings. Re-importing Final Cut's own XML replaces those characters with spaces.
All eight findings in seven markers retain their text apart from that formatting,
with unchanged timing, raster, duration and source media bytes.

## Native procedure

1. Open the existing **Aagedal FCP Native Duration Acceptance 20260919** library,
   select **Aagedal Compare Review**, switch the browser to list view and expand
   `source-a.mov vs source-b.mov Review`.
2. Inspect the native Notes column. QC 001 contains a literal tab between
   `"quoted"` and `column`, then a newline before `Second line`. QC 004 + QC 005
   contains the original blank line between its individually labelled findings.
   All seven marker rows are present, including the last frame at 00:10:09:08.
3. Open the unchanged [first native re-export](../fcp-native-duration-23976-20260919/returned.fcpxml)
   through Finder. Choose New in Final Cut's destination dialog and create
   **Aagedal FCP Whitespace Phase 123** in `/private/tmp/aagedal-resolve-5994-20260919`.
4. Expand the new browser clip. Its Notes column now shows `"quoted" column
   Second line` on one line. The grouped marker separates QC 004 and QC 005
   with two spaces instead of two newlines. Seven markers remain visible.
5. Select the new event and use **File → Export XML**, General metadata,
   Current Version (1.14). Export to
   `/private/tmp/aagedal-phase123-second-generation.fcpxmld` and retain the
   unmodified `Info.fcpxml` here as `second-generation.fcpxml`.

This second export now contains literal spaces where the first native export
contained literal attribute tabs/newlines. The result is therefore not solely
an artifact of the comparison parser. No source media, review note, or XML
content was edited during this native experiment.

## Machine verification

- `original-to-second.json`: only `exactMarkerContent` fails; attribute-whitespace
  normalization makes the content match. The comparator still exits nonzero.
- `first-to-second.json`: exact parsed-content match, confirming no further
  timing, geometry or content change beyond the first XML's normalization.
- Both comparisons verify imported media bytes. All four original media/review
  files still match the original fixture manifest; see `provenance.json`.
- The focused Python comparator suite passes 17 tests, including a regression
  that requires the second export's raw marker attributes to contain spaces.

The app's Final Cut save panel now explains this round-trip limitation and
recommends keeping CSV or PDF when formatting matters. It also explains textual
ranges and grouped same-frame findings. The exporter continues to encode tabs
and newlines correctly for the first import; no destructive flattening or
comparison waiver is added. This is diagnosis and disclosure, not a fix to
Final Cut's serializer or full editor acceptance. Rotated anamorphic exports
remain restricted. Other rates, producer-authentic geometry, spoken VoiceOver,
and broader release gates remain separate.

Verification of the change: the Debug app build succeeds and the complete
`scripts/test-script-validators.sh` suite passes. Logs are retained at
`/private/tmp/aagedal-phase123-build.log` and
`/private/tmp/aagedal-phase123-validators.log`. Xcode required its normal cache
access outside the workspace sandbox. The new save-panel copy was compiled;
a fresh native player-panel inspection, full XCTest run, Release candidate
verification and spoken accessibility testing were not performed in this phase.
