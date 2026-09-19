# Native Final Cut conform isolation — 2026-09-19

Phase 119 narrows the Phase 118 padding failure to the rotated anamorphic
combination in this generated fixture family. Final Cut Pro 12.3 renders the
unrotated anamorphic, rotated square-pixel and baked square-pixel controls at
expected Fit bounds. The original rotated anamorphic case still fails.
**This is diagnostic evidence, not shipping-exporter or editor acceptance.**

## Controlled native render

Imported `input.fcpxml` through native File → Import → XML and opened
`Aagedal Conform Isolation 119 Validated`. Its four consecutive two-second
clips use the same 1080 × 1920, square-pixel, 24 fps timeline, with no explicit
transform or spatial-conform adjustment. Export File used Source – Apple
ProRes 422, Standard Rec. 709, over the complete eight-second project.
The unmodified native General/Current Version (1.14) project re-export is
`returned-project.fcpxml`. All four native media hashes match their respective
inputs; the transcoded controls intentionally differ from the original.

An initial diagnostic import warned about its project format. That attempt is
excluded: the retained input has an explicit Rec. 709 project format and a
conventional project resource ID, and imported without a warning. The first
attempt's event remains in the disposable library; native media resources were
reused. Only the subsequently imported `Validated` project was rendered here.

Bounds use exclusive right/bottom coordinates. Measurements sample each clip's
midpoint, at 1, 3, 5 and 7 seconds. Thresholds 40, 60 and 80 all pass the three
controls; the original fails Fit at every threshold.

| Input | Expected aspect | Measured content at threshold 60 | Bounds | Result |
| --- | --- | --- | --- | --- |
| Original 240 × 180, PAR 4:3, rotation 90° | 9:16 | 813 × 1444 | [134, 238, 947, 1682] | Fit fails |
| Existing unrotated 240 × 180, PAR 4:3 | 16:9 | 1080 × 610 | [0, 655, 1080, 1265] | Pass |
| Re-encoded 240 × 180, PAR 1:1, rotation 90° | 3:4 | 1080 × 1444 | [0, 238, 1080, 1682] | Pass |
| Original baked to 180 × 320, PAR 1:1, no rotation metadata | 9:16 | 1080 × 1920 | [0, 0, 1080, 1920] | Pass |

Quadrant orientation and solid content pass in all four cases. Native XML keeps
the original asset at 180 × 240 / PAR 4:3 while its timeline clip retains PAR
3:4. The controls have matching asset/clip geometry. These observations narrow
the failure to native handling of the rotation/PAR combination in these inputs;
they do not prove the editor's internal cause. The baked control also changes
codec, and the square-pixel rotation control is re-encoded. No automatic media
conversion, exporter scale compensation, or asset-PAR waiver is introduced.

## Diagnostic correction

The unrotated control exposed an axis-dependent false failure in the aspect
check: its 610-pixel saturated height differs from the ideal 607.5 by only 2.5
pixels, but the old width residual amplified that to 4.44 pixels. The check now
measures the perpendicular distance of `(width, height)` from the expected
aspect line, in pixels, retaining the three-pixel threshold. This is invariant
under transposition. `aspectErrorPixels` records that residual explicitly.
The independent per-edge Fit check is unchanged and still rejects the original
large margins. Ten regressions cover transposition, real aspect distortion,
native padding, blank/truncated images, orientation and sparse content.

## Reproduce

From the repository root, prepare the two derived controls (existing files must
be removed or a new output directory used before repeating):

```sh
mkdir -p /private/tmp/aagedal-phase119
ffmpeg -v error -noautorotate \
  -i 'Test Fixtures/Generated/loupe/rotate-90-par.mp4' \
  -vf setsar=1 -an -c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv420p \
  /private/tmp/aagedal-phase119/rotated-square.mp4
ffmpeg -v error -i 'Test Fixtures/Generated/loupe/rotate-90-par.mp4' \
  -vf 'scale=180:320,setsar=1' -an -c:v prores_ks -profile:v 2 \
  -pix_fmt yuv422p10le /private/tmp/aagedal-phase119/baked-square.mov
```

Import the retained input XML (adjust absolute media URLs for another checkout),
then perform the native render as above. Example measurement:

```sh
python3 scripts/measure-quadrant-render.py \
  /private/tmp/aagedal-phase119/phase119-native-conform.mov \
  --times 1 --aspect 9/16 --colors green yellow red blue
```

Expected exit: **1**. At seconds 3 use `--aspect 16/9 --colors red green blue
yellow`; at seconds 5 use `--aspect 3/4`; at seconds 7 use `--aspect 9/16`.
The latter two use the original command's colors. Each control exits **0**.
Retained JSON includes decoder identity, render SHA-256, stream metadata and
full decoded-frame hashes; `provenance.json` binds original/native media and
retained evidence. PNGs are decoded full-resolution render frames.

The full script-validator suite passes, including ten geometry regressions
(log: `/private/tmp/aagedal-phase119-script-validators.log`). No Swift code
changed and no new Xcode verification is claimed.

Remaining: a fresh rebuilt-player UI export, broader rotations/reflections and
producer-authentic geometry, the asset-PAR mismatch, and an evidence-backed
resolution of native Fit padding. The normalization control is not a proposed
source-replacement workflow; non-destructive source identity remains required.
