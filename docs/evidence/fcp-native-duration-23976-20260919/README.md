# Native player / Final Cut duration acceptance — 2026-09-19

The player UI now exports **14,625 frames**, and Final Cut Pro 12.3 preserves
that exact duration through native import/re-export. The 160 × 90 raster,
24000/1001 rate, zero start, NDF display, seven marker anchors and eight findings
also survive. Exact parsed note whitespace still differs; full interoperability
is not accepted.

## Reproduction and correction

1. Launch the Debug player, open the existing generated `source-a.mov` in
   `/private/tmp/aagedal-resolve-23976-20260919`, and add `source-b.mov` using
   **Add comparison file**. The default sidecar loads all eight findings.
2. **Comparison review notes → Export → Final Cut Pro Markers** saves
   `fcp-native-player-113.fcpxml`, retained unchanged as `before-fix.fcpxml`.
   This native export declares 14,626 frames. Phase 112's inaccurate XCTest
   snapshot therefore was not the only way to trigger the duration discrepancy.
3. Correct the report snapshot to prefer a positive metadata frame count when
   a video rate exists and the count agrees with playback duration within one
   frame. Container/playback duration rounding must not add a phantom frame.
   Missing, invalid or substantially disagreeing counts retain the existing
   duration estimate. Findings beyond the source still extend the report extent.
   This does not establish general VFR duration support: the metadata count can
   itself be estimated, and substantially differing sample/timebase counts are
   deliberately not substituted.
4. Rebuild, restart the player, reopen the same pair and export again through
   the same UI to `fcp-native-player-113-fixed.fcpxml`, retained as `original.fcpxml`.
   Both asset and browser clip now declare `39039/64s` (14,625 frames).
5. Open that unchanged XML in Finder. Choose **New** in Final Cut's import
   library dialog and create **Aagedal FCP Native Duration Acceptance 20260919**
   in the fixture directory. The imported event shows one browser item and
   `160 × 90 | 23,98 fps` in the viewer.
6. With that event selected, use **File → Export XML**, General metadata,
   Current Version (1.14), saving `fcp-native-duration-113-roundtrip.fcpxmld`.
   Retain its unmodified `Info.fcpxml` as `returned.fcpxml`.

```sh
python3 scripts/compare-fcp-marker-roundtrip.py \
  docs/evidence/fcp-native-duration-23976-20260919/original.fcpxml \
  docs/evidence/fcp-native-duration-23976-20260919/returned.fcpxml \
  --verify-media
```

The retained `comparison.json` reports only `exactMarkerContent: false`.
Exit 1 remains expected: Final Cut re-exports literal tabs/newlines in XML
attributes, which parse as spaces. Replacing only those attribute whitespace
characters produces matching content for every marker, including both grouped
findings and textual inclusive ranges. The comparator does not silently waive
this difference. Imported source bytes match, and all four original fixture
inputs still match their manifest hashes.

`provenance.json` records the base commit, modified exporter and executable
hashes, package identity, test result location and original-input hashes.
The initial stale development process exposed no player content; quitting and
relaunching restored the UI before these exports. No keyboard-only or spoken
VoiceOver acceptance is claimed.

Validation: 35 focused Debug exporter tests pass, including metadata-count
agreement and fallback cases. Nine Python round-trip regressions pass, including
this retained before/fixed/returned comparison. The native result is limited to
this generated landscape 23.976 NDF source; portrait, anamorphic, rotated,
other-rate, exact whitespace and broader editor acceptance remain open.
