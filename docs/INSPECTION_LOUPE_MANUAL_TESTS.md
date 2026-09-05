# Inspection loupe manual acceptance

Status: **Not performed.** This run sheet covers the remaining hands-on 1.7
loupe gates. Automated decoder, geometry, and rendering tests do not
replace these checks on the shipping app and release-floor hardware.

## Preparation

- Record the Release build commit, macOS version, Mac model/memory, display
  resolution and backing scale, and actual A/B decoder backends.
- Run `scripts/generate-test-fixtures.sh` from the repository root if needed
  (requires a full FFmpeg installation). Default fixtures are in
  `Test Fixtures/Generated/loupe/`:
  `landscape.mp4`, `portrait.mp4`, `par.mp4`, `rotate-90-par.mp4`,
  `rotate-180.mp4`, `rotate-270.mp4`, `mirror.mp4`, `mirror-vertical.mp4`,
  `mirror-90.mp4`, and `mirror-270.mp4`.
- Start with `landscape.mp4` as A and `portrait.mp4` as B, then replace each
  source with the remaining transformed fixtures. Record actual backends;
  ordinary app selection does not necessarily exercise both AVFoundation and
  MPV. Include representative production media on each backend.
- Press Command-Shift-M and enable **Show loupe**. Exact source-pixel **1:1 is
  unavailable**; the offered 2×/4×/8× modes magnify the fitted display picture.
  HDR previews are not color/code-value measurements, and A/B captures are
  independent rather than frame-locked.

## Picture registration and presentation

- [ ] In single-source playback, move the real pointer through each colored
  quadrant and near each picture edge for every fixture at 2×, 4×, and 8×.
  **Expected:** the lens shows the region under the pointer with the same
  orientation as the live picture. At the image boundary it shows black
  outside the image without shifting the selected point inward.
- [ ] Repeat with mismatched A/B aspects in all seven Compare Mode views:
  A, B, side by side, vertical wipe, horizontal wipe, overlay, and display
  difference. Sweep the wipe divider and test both panes/sides.
  **Expected:** A/B lenses inspect the same normalized picture coordinate.
  Side by side and wipes follow the visible source under the pointer;
  overlay/difference use A coordinates, except 100% B overlay uses B.
  Transformed sources can have different colors at the same coordinate;
  compare each lens against its own source, not against the other lens's color.
- [ ] Move into letterbox/pillarbox bars, including B's bars in side by side,
  wipes, and 100% B overlay.
  **Expected:** the last valid picture coordinate remains selected. Bars do
  not select a new region or cause a lens jump.
- [ ] Repeat corner/edge checks while resizing, after entering/exiting
  fullscreen, and with **Full Frame** and **Reduced Frame (1/2)** rendering.
  Where available, move the window between Retina and non-Retina displays.
  **Expected:** pointer registration remains correct; magnification is relative
  to the fitted picture. Enabling/moving the loupe does not resize the window,
  shift controls, or replace the active playback surfaces/backends. Record any
  surface identity that cannot be verified manually as unverified.

## Controls, lifecycle, and accessibility

- [ ] Pin a noncentral point, then operate play/pause, scrub, and frame step.
  **Expected:** the inspected coordinate stays fixed and the preview updates
  to the resulting picture. **Center and pin** selects the center and stays
  pinned; either position slider changes the coordinate and pins it.
- [ ] Pin near the bottom-right corner of a large window, then shrink the
  window substantially, including in paired A/B mode.
  **Expected:** lenses remain visible within the smaller canvas and the
  inspected picture coordinate stays fixed. Automated placement regressions
  cover stale pointer coordinates; verify native resizing here.
- [ ] Hide using **Show loupe**, then show it again, including rapid repeats.
  **Expected:** hiding retains magnification, pin state, and chosen position;
  no obsolete capture appears on reopening. Hidden loupes stop scheduling
  capture work; an already-running capture may finish but cannot publish.
- [ ] Replace B while pinned, then replace A with a different file. Close the
  window during playback/capture and repeat with scopes open.
  **Expected:** B replacement retains the coordinate and clears its old image;
  A replacement disables the loupe and resets pin/position. Window closure
  leaves no repeating loupe work or crash. Scopes continue while the loupe is
  hidden and retain their own outputs.
- [ ] With macOS **Full Keyboard Access** enabled, use Command-Shift-M, then
  navigate and operate Show loupe, magnification, pinning, both sliders, and
  Center and pin without a mouse. Dismiss and reopen the popover.
  **Expected:** focus is visible, traversal reaches every control, slider keys
  update the picture position, and focus returns to usable playback controls.
- [ ] Repeat with **VoiceOver** enabled.
  **Expected:** the loupe button announces its shown/hidden state; controls
  have meaningful labels and values, including slider percentages. The loupe
  announces source(s), magnification, and pinned/following state. Playback keys
  do not unexpectedly fire while operating popover controls.

## Production performance

- [ ] Follow [Compare Mode performance validation](COMPARE_MODE_PERFORMANCE.md)
  for separate ordinary and reflected 120-second-per-scenario profiles on the
  base 2020 M1 MacBook Air (8 GB, 7-core GPU), at Full Frame. Retain reports and
  Instruments traces using that document's preparation and run sheet.
- [ ] With UHD/HDR A/B sources and scopes running, move/pin the loupe, cycle
  magnifications, scrub/step, and close/reopen during playback.
  **Expected:** controls and scopes remain responsive, images refresh, and
  capture cleanup succeeds. The profiler requires at least two fresh captures
  per second per source, no capture gap above one second, and at most 250 ms
  main-actor delay. “Up to 10 fps” is a ceiling, not a guaranteed cadence.
- [ ] Record CPU/GPU median and peak, peak resident memory, drift/recovery,
  interaction delay, and thermal state using Instruments. If Full Frame fails,
  retain the failure and record Reduced Frame separately; it does not pass the
  Full Frame gate. The [M5 Pro development profile](INSPECTION_LOUPE_PROFILE_2026-09-05.md)
  supplies context, not release-floor acceptance evidence.

## Results template

Copy this section into the retained test report. Leave untested checks open;
record failures and blocked coverage explicitly.

- Date / tester:
- Commit / Release app path:
- macOS / hardware / memory:
- Display(s), resolution / backing scale:
- Fixture or production files / actual A and B backends:
- Full Keyboard Access / VoiceOver settings:
- Profile report / Instruments trace locations:

| Check | Modes / fixtures / render setting covered | Pass, fail, or untested | Observation / evidence / issue |
| --- | --- | --- | --- |
| Native picture registration and black bars | | Untested | |
| Resize, fullscreen, display scale, surface continuity | | Untested | |
| Pinning, hide/show, source replacement, teardown | | Untested | |
| Full Keyboard Access | | Untested | |
| VoiceOver | | Untested | |
| Ordinary base-M1 Full Frame profile | | Untested | |
| Reflected base-M1 Full Frame profile | | Untested | |
| Instruments and representative UHD/HDR media | | Untested | |

Remaining failures or untested combinations:

Release-gate decision and evidence:
