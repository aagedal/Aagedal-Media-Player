# Fresh production UI native render — 2026-09-19

Phase 121 completes the missing rendered-output repeat from Phase 120.
The fresh production UI export reproduces the known Fit padding failure.
This is a completed diagnostic task, not geometry acceptance or a shipping fix.

## Native workflow

In Final Cut Pro 12.3, use the existing separate `Aagedal FCP Production UI
Phase 120` library and its imported production review clip. Create `Aagedal
Production UI Render Phase 121` with explicit 1080 × 1920, 24p, Rec. 709,
Apple ProRes 422 settings and zero starting timecode. The append interaction
inserted two consecutive copies of the complete two-second clip; both are
retained in the four-second diagnostic timeline. No transforms, scale
compensation or spatial-conform adjustments were applied.

Export File uses Video and Audio, Source – Apple ProRes 422, Standard Rec. 709.
The resulting movie is `/private/tmp/aagedal-phase121/phase121-production-ui.mov`.
Export the event using General metadata / Current Version (1.14);
`returned-event.fcpxml` is its unmodified `Info.fcpxml`. It includes both timeline
instances and the original browser clip. The source input is the unchanged
[Phase 120 production XML](../fcp-production-ui-anamorphic-20260919/original.fcpxml).
No additional player build or player export was performed in this phase.

## Measured result

At 0.5, 1.5, 2.5 and 3.5 seconds, all decoded RGB frames are identical. At each
of thresholds 40, 60 and 80, saturated content occupies **813 × 1444** pixels,
with exclusive bounds `[134, 238, 947, 1682]` inside 1080 × 1920. The expected
9:16 Fit bounds are `[0, 0, 1080, 1920]`. Quadrant orientation, solid content
and display aspect pass; Fit fails at every sample/threshold. `render-frame.png`
is a decoded full-resolution frame. This repeats the Phase 118/119 padding
with the fresh production UI input and closes the outstanding render-repeat task.

The browser comparator verifies exact marker text/timing, 48-frame duration,
browser raster/PAR and source bytes. Its only failed check is `assetPixelAspect`
(3:4 → 4:3). It selects the browser clip explicitly; it does not claim automated
timeline-marker acceptance. Native XML retains the same marker on each timeline
instance, with offsets 0s and 2s, and contains no spatial/transform adjustment.
Original and native media hashes still match Phase 120 provenance.

## Verification and remaining work

Ten geometry diagnostic tests and sixteen FCPXML comparison tests pass.
Both diagnostic commands below correctly exit **1** for the retained failure.
No Swift code changed, and no new Xcode or whole-suite verification is claimed.

```sh
python3 scripts/measure-quadrant-render.py \
  /private/tmp/aagedal-phase121/phase121-production-ui.mov \
  --times 0.5 1.5 2.5 3.5 --aspect 9/16 --colors green yellow red blue
python3 scripts/compare-fcp-marker-roundtrip.py \
  docs/evidence/fcp-production-ui-anamorphic-20260919/original.fcpxml \
  docs/evidence/fcp-production-ui-render-20260919/returned-event.fcpxml \
  --returned-clip-name 'rotate-90-par.mp4 vs rotate-90-par.mp4 Review' --verify-media
```

The movie and native library are external local artifacts; their paths and
hashes are retained in `provenance.json`. XML, measurements and a decoded frame
remain in the repository. The next geometry task is to establish a justified
handling of the rotation/PAR conform defect, then validate broader rotations,
reflections and producer-authentic sources. Repeating this same unchanged Fit
case again would add no new diagnosis. Asset-PAR and rendered Fit acceptance
remain open; no compensating scale or comparator waiver is introduced.
