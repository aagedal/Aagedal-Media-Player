# Final Cut oriented anamorphic continuation — 2026-09-19

Phase 116 corrects the exported browser-clip format for quarter-turn sources:
swap coded width/height and invert pixel aspect ratio together. The 240 × 180,
4:3-pixel source rotated 90 degrees has display aspect 180/(240 × 4/3) = 9:16.
Its oriented format is therefore 180 × 240 with 3:4 pixels. Rotation stays in
the referenced media; the exporter does not add another rotation transform.
Landscape, portrait, 180-degree and unrotated anamorphic formats stay unchanged.

## Native investigation

Final Cut Pro 12.3 was still displaying the Phase 115 source in the disposable
`Aagedal FCP 5994 DF Acceptance 20260919` library. Its viewer showed the coloured
image at approximately 3:4 proportions within the landscape browser canvas.
A diagnostic XML changed only the format to 180 × 240 / 3:4 pixels and the
event/clip names. Import through File → Import → XML created the separate
`Aagedal Geometry Diagnostic 116` event in that same library. The viewer now
labels the clip 180 × 240 / 24 fps and shows approximately 9:16 coloured content,
with green/yellow above red/blue. These are visual observations, not a calibrated
pixel measurement or a complete spatial-conform acceptance test.

The native File → Export XML operation used General metadata and Current Version
(1.14). Its unmodified `Info.fcpxml` is `returned.fcpxml`. An unrelated
cross-library timeline-copy warning encountered while selecting the clip was
cancelled; no timeline edit was accepted.

The strict comparison retains a failure: **assetPixelAspect** changes from 3:4
to 4:3 even though browser raster/PAR, asset raster, timing, all three marker
texts and source-media bytes match. Do not waive this difference or call the
entire geometry gate accepted. Test timeline placement/conform and an independent
source import before deciding how asset and browser formats should differ.

## Production verification

`production.fcpxml` comes from the modified production MetadataService/exporter
fixture test. Structural XML comparison confirms it is identical to the native
input except event/clip names. The native input was the diagnostic file, not a
fresh export through the rebuilt player's UI. That repeat remains open.

- 37 focused Debug tests pass, with no skips, failures or runtime warnings.
  The generated-media test covers ten geometry files, including reflections;
  a new unit check covers positive, negative and wrapped quarter turns.
- All thirteen Python round-trip regressions pass, including one that keeps
  this asset-PAR mismatch visible. The script-validator gate passes.
- All ten production XML exports pass the installed Final Cut FCPXML 1.9 DTD.
- Xcode static analysis passes.

The first sandboxed test attempt could not write compiler/package caches and
ran no tests. The normal-cache retry is retained at
`/private/tmp/aagedal-phase116-tests-retry.xcresult`; its summary is included here.
Test, analysis and validator logs use `/private/tmp/aagedal-phase116-*` names.
`provenance.json` records base commit, changed source, package and artifact hashes.

Reproduce the native comparison (expected exit 1):

```sh
python3 scripts/compare-fcp-marker-roundtrip.py \
  docs/evidence/fcp-oriented-anamorphic-20260919/original.fcpxml \
  docs/evidence/fcp-oriented-anamorphic-20260919/returned.fcpxml --verify-media
```

Media verification needs the original fixture and native library copy at their
retained URLs. `comparison.json` records their matching hashes. XML-only tests
do not imply source-media verification. Other native geometry cases, grouped
findings, whitespace, player UI export and broader editor acceptance remain open.
