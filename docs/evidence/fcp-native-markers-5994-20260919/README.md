# Native Final Cut 59.94 DF marker acceptance — 2026-09-19

The native player export and Final Cut Pro 12.3 import/re-export preserve the
60000/1001 rate, 160 × 90 raster, square pixels, DF display, source start at
00:00:58;00 (3,480 frames), and exact 36,563-frame asset/browser duration.
All eight findings survive in seven one-frame markers. Exact whitespace still
fails, so this is focused timing/geometry/content evidence, not full acceptance.

## Native workflow

1. Relaunch the existing Phase 113 Debug player, open `source-a.mov` from
   `/private/tmp/aagedal-resolve-5994-20260919`, and add `source-b.mov` for comparison.
   The active default sidecar contains eight notes; the separate seven-note
   `resolve-unique` copy is not used for this export.
2. Open **Comparison review notes → Export → Final Cut Pro Markers** and save
   `source-a_vs_source-b_review.fcpxml`. Retain its unchanged bytes as `original.fcpxml`.
3. Open that XML through Finder, choose **New** in Final Cut's library prompt,
   and create `Aagedal FCP 5994 DF Acceptance 20260919.fcpbundle` in the fixture folder.
   The imported event contains one browser clip; the viewer reports 160 × 90
   and 59.94 fps.
4. With the imported event selected, use **File → Export XML**, General metadata,
   Current Version (1.14), saving `fcp-5994-df-114-roundtrip.fcpxmld` in that folder.
   Retain its unmodified `Info.fcpxml` as `returned.fcpxml`.

The initial player window exposed incomplete content and dialog input was
unreliable; quitting and relaunching restored the workflow. File rows were
selected with keyboard navigation. This mixed-input run does not establish
keyboard-only or spoken VoiceOver acceptance.

## Results and reproduction

```sh
python3 scripts/compare-fcp-marker-roundtrip.py \
  docs/evidence/fcp-native-markers-5994-20260919/original.fcpxml \
  docs/evidence/fcp-native-markers-5994-20260919/returned.fcpxml \
  --verify-media
python3 scripts/test-fcp-marker-roundtrip.py
```

The comparator exits 1, with only `exactMarkerContent` false. Final Cut emits
literal attribute tabs/newlines that parse as spaces; the explicitly qualified
whitespace-normalized comparison matches. No difference is waived.

Relative anchors are 0, 1, 119, 120, 32,483, 32,484, and 36,562. These exercise
the first dropped-label boundary, the ten-minute boundary, and the last source
frame. Frame 120 holds individually labelled QC 004 and QC 005 findings;
inclusive ranges remain textual. Ten Python regressions pass, including a check
against all eight original review texts, so agreement between XML files alone
cannot hide findings omitted before import.

`comparison.json` records matching SHA-256 hashes for source A and Final Cut's
imported media copy. All four original media/review input hashes still match
`fixture-manifest.json`; that historical manifest describes the separate Resolve
copy, while `original-review.json` is the actual eight-note FCP source.
`provenance.json` records the checkout, exporter and executable/library hashes.
No app code changed for this phase; the existing Phase 113 build was exercised.

This generated landscape case does not close portrait/anamorphic/rotated media,
other remaining rates, exact whitespace, VFR, accessibility or other-editor gates.
