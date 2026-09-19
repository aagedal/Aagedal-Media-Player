# Final Cut source-raster round trip — 2026-09-19

Final Cut Pro 12.3 preserves the explicit **160 × 90** browser-clip raster,
24000/1001 rate, zero source start, NDF display and all seven marker anchors.
The eight original findings remain in those seven markers, including the grouped
same-frame findings and textual inclusive ranges. Full interoperability remains
open: exact parsed note whitespace and clip/asset duration differ.

## Native procedure and provenance

1. Open `/private/tmp/aagedal-phase111-raster.fcpxml` from Finder. This is the
   unchanged Phase 111 production-exporter XCTest output from commit `0a905b6`,
   retained here as `original.fcpxml`. This run does not establish player UI export.
2. Choose New Library and save **Aagedal FCP Raster Acceptance 20260919** in
   `/private/tmp/aagedal-resolve-23976-20260919`. Other libraries are not modified.
3. The newly imported event is selected; the viewer reports `160 × 90 | 23,98 fps`.
   The earlier Phase 110 native import reported 1280 × 720 for this browser clip.
4. File → Export XML, General metadata, Current Version (1.14), to
   `fcp-raster-roundtrip.fcpxmld` in that directory. Copy its unchanged
   `Info.fcpxml` to `returned.fcpxml` here.
5. Compare exact rational times, raster, pixel aspect, source starts, timecode
   display, marker multiplicity/titles/content and original-media bytes:

   ```sh
   python3 scripts/compare-fcp-marker-roundtrip.py \
     docs/evidence/fcp-raster-markers-23976-20260919/original.fcpxml \
     docs/evidence/fcp-raster-markers-23976-20260919/returned.fcpxml \
     --verify-media
   ```

`comparison.json` retains this output. Exit **1** is expected: differences are
reported, never silently accepted. Exit 0 means exact equality for the compared
fields only; exit 2 means invalid/unavailable input. Without `--verify-media`,
media identity is explicitly unverified. The tool is limited to one event browser
asset-clip and does not validate arbitrary project graphs, color or orientation.

The original and imported media hashes match. All four original fixture inputs
still match the retained Phase 109 manifest, including both review sidecars.
`provenance.json` records this check. Native media paths must remain accessible to
repeat byte verification; XML-only regressions work without those media files.

## Remaining differences

- Final Cut writes literal tabs/newlines into XML attributes on re-export. Parsed
  note strings therefore differ. Replacing only tab, CR and LF by spaces makes
  every note match; no general whitespace collapsing or text omission is allowed.
- The input declares 14,626 frames while the native result contains 14,625,
  matching the generated fixture manifest. The XCTest snapshot used 610 seconds,
  whose ceiling at 24000/1001 is 14,626 frames; the media has 14,625 frames.
  This identifies a fixture/snapshot mismatch, not proof of an editor rounding
  defect or a production-duration fix. Accurate-metadata/native-player export
  still needs its own acceptance run.
- Portrait, anamorphic, rotated, DF and other-rate cases remain open. This
  focused result closes only the previously defaulted landscape browser raster.

Eight new Python regression tests cover native differences, exact equality,
missing/extra/shifted markers, content loss, raster/PAR/timecode/duration changes,
ambiguous or invalid XML structures, rational arithmetic and media identity.
