# Fresh production UI Final Cut round trip — 2026-09-19

Phase 120 completes the rebuilt-player UI export/import/re-export repeat for
rotated anamorphic media. It reproduces the native asset-PAR mismatch in a new
library. It does not resolve the Phase 118/119 rendered Fit failure or close
broader geometry acceptance. No shipping Swift implementation changed.

## Native workflow

1. Build Debug from `b3dc79b` with the pinned package graph. The first sandboxed
   attempt failed on compiler/package cache permissions; the normal-cache retry
   succeeded (`build.log`). Quit and relaunch the built Debug application.
2. Open `Test Fixtures/Generated/loupe/rotate-90-par.mp4` as source A and add
   the same file as source B. Playback remains paused at frame zero.
3. Use Review → New Review Note and save the exact text
   `Phase 120 native UI: rotated anamorphic source frame 0`.
4. Export using the review panel's Final Cut Pro Markers command to
   `/private/tmp/phase120-player-ui.fcpxml`. `original.fcpxml` is that unmodified
   UI export; `review.aagedal-compare.json` is the saved production sidecar.
5. In Final Cut Pro 12.3, create the separate disposable library
   `/private/tmp/aagedal-resolve-5994-20260919/Aagedal FCP Production UI Phase 120.fcpbundle`.
   Import the unmodified XML with File → Import → XML. No import warning appears;
   the browser shows the review clip at 180 × 240 / 24 fps.
6. Select the imported event and use File → Export XML, General metadata,
   Current Version (1.14). `returned.fcpxml` is the unmodified `Info.fcpxml`
   from `/private/tmp/aagedal-phase119/phase120-returned.fcpxmld`.

## Results

The strict comparator exits **1**, failing only `assetPixelAspect`: original
3:4 becomes native 4:3. Browser raster and PAR remain 180 × 240 / 3:4. Both
asset and clip duration remain exactly two seconds (48 frames); the frame-zero,
one-frame marker retains its exact title and complete note text. Original and
native media SHA-256 match. This single-line note does not exercise the earlier
multiline attribute-whitespace issue or grouped/range findings.

The fresh UI format matches the Phase 116 production fixture format. This
closes the outstanding fresh UI browser-export repeat, not a new timeline render:
no Phase 120 rendered-output measurement is claimed. The earlier calibrated
padding failure, asset-PAR discrepancy, broader rotations/reflections and
producer-authentic geometry remain open. Do not compensate scale or waive PAR
based on this round trip.

## Verification

- Fresh Debug build succeeds; binary, source revision, package graph and native
  artifact hashes are retained in `provenance.json`.
- Sixteen focused Python round-trip regressions pass, including the retained
  fresh-UI case. The XML-only regression deliberately does not claim media
  verification; the native comparison separately hashes both media files.
- The complete script-validator suite passes (`script-validators.log`).
- The fresh export passes the installed FCPXML 1.9 DTD.
- No new XCTest run or static-analysis result is claimed for this evidence-only
  continuation.

Reproduce from the repository root (expected exit **1**):

```sh
python3 scripts/compare-fcp-marker-roundtrip.py \
  docs/evidence/fcp-production-ui-anamorphic-20260919/original.fcpxml \
  docs/evidence/fcp-production-ui-anamorphic-20260919/returned.fcpxml --verify-media
```

Media verification requires both original fixture and native library media at
the retained URLs; the XML regression works without that external library.
