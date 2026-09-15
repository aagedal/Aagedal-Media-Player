# Resolve marker EDL evidence — 2026-09-15

This is a partial Resolve Studio 21.1.0.14 round-trip result on macOS 27.0,
not an accepted eight-finding import. The generated 29.97 drop-frame source
pair and untouched review sidecar are omitted because they are reproducible
media; `fixture-manifest.json` retains their original SHA-256 identities.

- `source-a_vs_source-b_review.edl` and `.csv` are native Save-panel exports
  from the current unsigned Release app. `native-export-validation-20260915.json`
  checks all eight source anchors, durations and original input hashes. Its
  `editor import not run` status records the time of that native export check;
  the import occurred later.
- `resolve-marker-api-20260915.tsv` is the built-in Resolve timeline-marker
  API snapshot after two imports. The first import used a timeline starting at
  `01:00:00;00`, leaving seven negative-frame markers. The user then changed
  the start to `00:00:58;00` and repeated the marker import. The corrected
  import has six in-range markers. `resolve-import-validation-20260915.json`
  compares their frame/duration/text fields against the saved review.
- `resolve-roundtrip.edl` is Resolve's native **Timeline Markers to EDL**
  export. `resolve-roundtrip-validation-20260915.json` checks its 13 observed
  events, surviving Unicode and both source URLs, and the original input hashes
  after export.

The corrected import lost Fixtures 1 and 5, and Fixture 2's text landed at
frame 0 although its saved A frame was 1. Five surviving anchors and both
three-frame durations were exact. Repeat with a *fresh* timeline starting at
`00:00:58;00` before any import to isolate the adjacent and duplicate-marker
behavior. See [the interchange run sheet](../../COMPARE_MODE_INTERCHANGE.md).
