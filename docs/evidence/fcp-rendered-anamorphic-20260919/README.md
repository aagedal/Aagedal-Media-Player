# Native Final Cut rendered anamorphic geometry — 2026-09-19

Phase 118 measures the unresolved Phase 117 geometry in a native Final Cut Pro
12.3 render. **Content aspect and orientation pass; default Fit placement fails.**
The editor gate remains open. No shipping exporter behavior changed.

## Native export and result

Selected `Aagedal Geometry Timeline 117` in the existing diagnostic event and
used native Export File: Source – Apple ProRes 422, 1080 × 1920, 24 fps,
Standard Rec. 709. The complete eight-second export contains 192 video frames.
It is retained at `/private/tmp/aagedal-phase117/phase118-native-timeline.mov`;
its SHA-256, settings, source identity and retained evidence hashes are in
`provenance.json`. The original and both native library source copies still
match Phase 117's SHA-256. This is the existing Phase 116 diagnostic review,
not a new production player UI export.

Measured frames at 1, 3 and 5 seconds cover the three review instances; the
7-second frame covers the independently imported byte-identical source.
All four decoded RGB frames have the same SHA-256, bounds and quadrant order.
The two retained PNGs are full-resolution frame extractions, not viewer captures.

| Measurement | Review and independent import |
| --- | --- |
| Output raster / pixel aspect | 1080 × 1920 / 1:1 |
| Saturated-content bounds, exclusive right/bottom | [134, 238, 947, 1682] |
| Content raster | 813 × 1444 |
| Left / top / right / bottom margins | 134 / 238 / 133 / 238 pixels |
| Quadrants, top-left through bottom-right | green, yellow, red, blue |
| Expected oriented source aspect | 9:16 |
| Expected default Fit content bounds | [0, 0, 1080, 1920] |

The source is 240 × 180 with 4:3 pixels and a 90-degree display rotation:
its unrotated display is 320 × 180, so its oriented aspect is 180:320 = 9:16.
That matches the portrait timeline and should fill it under Fit. Measured
content preserves this aspect within the three-pixel edge tolerance, but is
only about 75% of the expected width and height. Margins are therefore a real
rendered-output issue, not solely a viewer zoom artifact. The identical direct
import result narrows the investigation toward shared native source/conform
handling; it does not identify the root cause or justify an exporter scale
compensation. The XML asset-PAR discrepancy remains separately unaccepted.

## Reproduce

```sh
python3 scripts/measure-quadrant-render.py \
  /private/tmp/aagedal-phase117/phase118-native-timeline.mov \
  --times 1 3 5 7 --aspect 9/16 --colors green yellow red blue
```

Expected exit: **1**, `status: differences`, with only `fitBounds` failing.
The helper requires one square-pixel video stream without display side data,
complete decoded frames and in-range sample times. It records the render hash,
decoder version, decoded frame hashes, orientation, content density, aspect and
Fit bounds. Saturation thresholds 40, 60 and 80 all give identical bounds here.
This diagnostic is specific to the generated saturated quadrant fixture; it
does not validate arbitrary media, color accuracy, marker text or every frame.

Seven focused geometry regressions and the complete script-validator suite pass.
The retained validator log is `/private/tmp/aagedal-phase118-script-validators.log`.
No Swift code changed, so no new Xcode build/test acceptance is claimed.

Next: isolate the native anamorphic conform behavior, repeat fresh production
player UI export, and complete the other geometry/editor cases. Keep the Fit
and asset-PAR failures explicit until the rendered result is correct.
