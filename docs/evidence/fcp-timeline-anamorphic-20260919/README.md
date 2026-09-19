# Final Cut timeline and independent anamorphic import — 2026-09-19

Phase 117 extends the Phase 116 native diagnostic in Final Cut Pro 12.3.
It does **not** accept the remaining geometry gate or change the shipping exporter.

## Native comparison

Created `Aagedal Geometry Timeline 117` in the existing disposable
`Aagedal Geometry Diagnostic 116` event: 1080 × 1920, square pixels, 24 fps,
zero starting timecode. The native timeline contains three consecutive two-second
appends of the oriented diagnostic review clip, followed by one two-second
independent source import. The repeated appends are retained in the unmodified
event export; they are not three independent source tests.

Importing the original source path again did not create a separate browser clip.
A byte-identical copy named `independent-rotate-90-par.mp4` was therefore imported
through File → Import → Media from `/private/tmp/aagedal-phase117`. Both native
library media copies and the original fixture have identical SHA-256 hashes
recorded in `provenance.json`.

The review clip and the independent import both show approximately 9:16 coloured
content with black margins on all four sides in the portrait timeline. Inspector
values show Fit, zero position/rotation and 100% scale. The independent browser
clip instead shows approximately 3:4 coloured content. These are visual UI
observations, not calibrated pixel measurements or rendered-output acceptance.

The native XML corroborates that both assets use the same 180 × 240 / 4:3-pixel
format. The review browser/timeline clips retain 3:4 pixels; the direct import
uses 4:3 pixels. The timeline has no explicit transform or spatial-conform
adjustments. This suggests the timeline padding involves Final Cut's source
interpretation, rather than being unique to the review XML. It does not justify
changing the exporter to match the native asset PAR or waiving the discrepancy.

## Repeatable checks

`returned-event.fcpxml` is the unmodified `Info.fcpxml` from native File → Export
XML, General metadata, Current Version (1.14). The comparison script now supports
an explicit, unique returned browser-clip name, so an event containing projects
and independent reference media can be checked without editing the native XML:

```sh
python3 scripts/compare-fcp-marker-roundtrip.py \
  docs/evidence/fcp-oriented-anamorphic-20260919/original.fcpxml \
  docs/evidence/fcp-timeline-anamorphic-20260919/returned-event.fcpxml \
  --returned-clip-name 'rotate-90-par.mp4 vs rotate-90-par.mp4 Oriented Diagnostic' \
  --verify-media
```

Expected exit is **1**, with only `assetPixelAspect` differing. All three browser
markers, timing, browser geometry and media bytes match. The selection applies
only to the returned file and only to a direct event browser clip. Timeline
markers cannot replace missing/changed browser markers. Missing or ambiguous
names fail; without the option the original strict single-clip rule remains.
This comparison does not validate the other clips or timeline.

All 15 Python comparator tests pass, including retained native timeline structure,
explicit selection, missing/ambiguous selection and unchanged timeline markers
failing to mask changed browser findings. The full script-validator suite also
passes (`/private/tmp/aagedal-phase117-script-validators.log`). No Swift source changed, so no new
app build or Xcode test run was needed.

Remaining: calibrated timeline/rendered-output geometry, a fresh rebuilt-player UI
export, other native rotation/reflection/anamorphic cases, exact note whitespace,
and broader editor/accessibility acceptance. The Phase 116 diagnostic input is
still the source of this review clip; this is not a fresh production UI export.
