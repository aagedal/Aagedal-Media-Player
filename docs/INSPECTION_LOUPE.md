# Inspection loupe

The loupe is an optional per-window display preview. Open its magnifying-glass
control, or press Command-Shift-M, then enable Show loupe. Choose 2×, 4×, or 8×
magnification relative to the fitted picture. In side-by-side comparison each
magnification is relative to that source's fitted pane.

The pointer selects a normalized coordinate inside the visible picture. Black
bars do not change the selected coordinate. Compare Mode uses that coordinate
for both source previews, even when their display aspects differ. Wipe modes
select coordinates from the source under the pointer; overlay and difference
modes use A's picture coordinates. The loupe previews always show A and B
separately, regardless of the comparison presentation mode.

Pin picture position holds the inspected coordinate while using transport.
The horizontal and vertical sliders also pin the position. Center and pin
returns to the picture center. Closing/replacing A resets the loupe. Replacing
B retains the chosen picture coordinate and clears the obsolete B image.

## Capture and interpretation

Capture uses the existing MPV decoder or a dedicated AVPlayerItemVideoOutput.
It does not create a decoder, take ownership of scopes, or change the playback
layout. Each source has at most one capture/conversion worker, with a minimum
100 ms between starts. A worker already inside a native screenshot call cannot
be interrupted; closing invalidates its result and prevents more requests.
Stop removes the loupe's AV output and releases the published image. Window
close explicitly stops both captures before controller teardown.

Magnification uses nearest-neighbor display of the captured image. MPV's video
screenshot may already resample pixel aspect ratio and rotation. AVFoundation
capture applies the track transform and the view applies display aspect ratio.
This is not a source-code-value or objective color measurement: HDR and tone
mapping can differ from the live display. The independently captured A/B
previews are not timestamp-paired and are not evidence of continuous frame lock.
Exact source-pixel 1:1 and whole-viewport pan/zoom remain deferred.

The bundled MPV loses the reflection component of QuickTime display matrices.
Playback preparation now detects a reflected first-track transform and applies
a vertical video filter before MPV's existing rotation. Reflected files use
VideoToolbox copyback so the software filter receives CPU-accessible frames;
unreflected files keep their existing hardware decoding path. This corrects the native
picture and every decoder capture together. The probe belongs to the playback
preparation and cannot construct a backend after replacement or teardown.
AVFoundation already applies the complete transform. Production-resolution
performance of the additional filter on reflected media remains a release
profiling gate; ordinary unreflected media receives no additional video filter.

## Generated pixel fixtures

Run `scripts/generate-test-fixtures.sh` to regenerate the optional decoder
fixtures, including the `loupe/` set. Distinct red, green, blue, and yellow
quadrants make rotation, reflection, and axis inversion observable. Cases cover
landscape and portrait rasters, 4:3 pixel aspect ratio, 90° rotation with PAR,
180° and 270° rotations, container horizontal/vertical mirroring, and
horizontal mirroring combined with 90°/270° rotation. The live tests
read the images published by `LoupeFrameCapture` from each backend while paused.
They require all fixture files and report a skip if the set is missing.

The rendered-lens matrix separately checks the normalized picture positions
across four coded-raster/fitted-picture combinations, every visible
magnification, and 1×/2× display scale. This separation checks both decoder
orientation and the loupe's display-aspect mapping. It does not constitute
end-to-end pointer registration in every live comparison presentation mode.

## Validation gates

Automated checks cover normalized coordinates and black bars, magnification,
Retina placement math for a future pixel view, pin/reset state, worker ownership,
stale completion rejection, and raw raster bounds. Mixed-backend decoder checks
exercise paused capture, seek/step image changes, simultaneous scopes, stop,
restart, and teardown.

Verification on 2026-09-05: the complete Release suite passed 319 tests with
zero failures and no skips, including 32 rendered lens cases. Static analysis
and all 61 release-preflight checks passed.

Continuation verification on 2026-09-05: 329 Release tests pass with no
failures or skips, including 20 live decoder fixture cases and 128 rendered
lens cases. Static analysis and all 61 release-preflight checks pass.

Before release:

- Check visible registration with asymmetric corner/edge fixtures at all
  rotations, PARs, and mismatched A/B aspects; include mirroring.
- Sweep every comparison mode, fullscreen, resizing, and half-resolution render
  mode while confirming decoder/surface identity and unchanged control layout.
- Inspect paused, scrubbed, stepped, and playing UHD/HDR sources with scopes;
  measure cadence, CPU/GPU, memory, and thermal behavior on the base-M1 gate Mac.
- Verify keyboard activation and Tab traversal, sliders, pinning, reset, and
  close with Full Keyboard Access and VoiceOver.
- Close/reopen rapidly, replace B, replace A, and close the window during a
  capture; confirm no repeating work or stale picture remains.
