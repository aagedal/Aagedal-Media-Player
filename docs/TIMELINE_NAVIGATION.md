# Timeline zoom and overview

The timeline's **Fit** menu offers 2×, 4×, 8×, 16×, 32×, and 64× zoom,
centered on the current playhead and clamped to the file's start and end.
Choose **Fit Entire Timeline**, or the **Fit** button beside a zoomed overview,
to return to the complete duration. Opening another primary file resets zoom.
Zoom is local to each player window and does not change playback speed.

While zoomed, the small bar above the scrubber shows the full duration, the
visible interval, and the playhead. Drag the overview to move the visible
interval without seeking. Focus it and use Left/Right Arrow, or VoiceOver's
adjustable action, to pan by half an interval. Playback and seeking reveal the
playhead when it leaves the interval; an active overview drag temporarily
suspends this following behavior. Pan while paused to inspect another region.

The main scrubber seeks within the visible interval. Option-drag retains
precision scrubbing, and its Left/Right Arrow and VoiceOver adjustments still
seek exactly one source frame through the existing transport commands. In
Compare Mode, A remains the authoritative timeline and B follows its mapping.
Chapter, trim, review, and overlap marks use the same viewport. Offscreen
points are hidden; ranges crossing an edge are clipped. **Show Timeline
Details** continues to control optional marks independently of zoom.

## Verification

The 382-test Release suite passed on 2026-09-06 with no failures or skips.
Static analysis and all 61 release-preflight checks also passed.

`TimelineViewportTests` covers full-duration fit, clamped panning, range
clipping, offscreen points, invalid geometry, and adjacent fractional-rate
frames in a 24-hour recording. Existing playback/compare tests protect frame
stepping and coordinated seeking. The native acceptance checks below remain
pending; model tests are not evidence of pointer or assistive-technology use.

- In single-source and Compare Mode, zoom a long recording, scrub with and
  without Option, and confirm adjacent-frame keyboard steps.
- Pan the overview while paused and playing; confirm panning itself never
  seeks, and playback follows only after an active overview drag ends.
- Check clipped chapter, trim, review range, and overlap marks near both edges.
- Use Full Keyboard Access and VoiceOver to choose zoom, pan, seek, and return
  to Fit. Confirm overview arrows pan without moving playback and all focused
  controls remain visible.
- Repeat at narrow window sizes and in fullscreen. Replace the primary file
  and confirm the timeline returns to Fit.
