# Inspector canvas and playback recovery layout — September 11, 2026

Native RIFX acceptance exposed a layout defect: at 711 × 400 with the metadata
inspector open, the error panel still laid out against the full 711-point
window, although only about 440 points remained visible. Its explanation and
Copy Diagnostics action extended behind the inspector.

The content root now ignores only vertical safe areas, retaining titlebar
coverage while respecting the inspector's trailing inset. Both native playback
surfaces use the same rule; otherwise video itself still extends behind the
inspector. The failure panel wraps its message, switches to stacked actions
when necessary and scrolls in short viewports. Actual toolbar and transport
heights are measured and reserved outside the scroll viewport. These insets
stay reserved when controls fade, preventing actions moving under the pointer,
and are scaled consistently with comparison rendering.

The Release build from `/tmp/aagedal-recovery-clearance-build-20260911.log`
was relaunched from
`/private/tmp/aagedal-player-utf32-derived-20260910/Build/Products/Release/Aagedal Media Player.app`.
At 711 × 400, with the inspector and compact transport controls visible,
`/tmp/aagedal-rifx-native-20260911b/utf32le.wav` shows the full RIFX explanation
and Retry, Reveal File and Copy Diagnostics above the transport panel.
Retry returns to the expected unsupported-playback state. Scrolling the
failure panel leaves all three actions reachable above transport, with the
complete explanation retained in accessibility. Screenshots were inspected
in the task; standalone image files were not saved.

A five-second 640 × 360, 25 fps H.264 `testsrc2` fixture at
`/tmp/aagedal-inspector-layout-20260911.mp4` (also copied as `layout.mp4` beside
the RIFX fixtures) verifies the full MPV chart initially fits beside the
inspector at a 540 × 264 window size. It also exposed MPV's documented stale
destination rectangle after inspector toggles, requiring separate transition
refresh verification.

Inspector changes now arm a window-owned, cancellable refresh, debounced until
canvas geometry settles. It requires a ready MPV surface and validates both
preparation identities, media URLs and comparison activity before using the
existing reload path. Ordinary geometry updates cannot arm it. Media or
preparation replacement, comparison transitions and disappearance cancel it.
Single-source reload now restores playing intent after readiness, guarded by
load generation and preparation identity. Stop, a superseding preparation,
failure, or explicit single-source Pause prevents that resume. Active comparison
readiness behavior is unchanged.

`testSingleSourceReloadPreservesTransportAndRejectsSupersededResume` exercises
MPV and AVFoundation with paused, playing, superseded, stopped and explicit
pause-during-reload outcomes, including actual playback-clock advancement.

The final build (`/tmp/aagedal-inspector-final-build-20260911.log`) passed a
fresh native transition check with `layout-long.mp4`, a 30-second version of
the same chart in the fixture directory. Opening the inspector while playing
retained Playing and advanced from `00:00:01:02` to `00:00:07:17`. Pausing,
hiding and reopening the inspector retained `00:00:15:19`. Settled screenshots
show the complete chart at both the 590-point full canvas and approximately
320-point canvas beside the inspector, with correct centering/aspect fit and
no stale compressed destination rectangle. This verifies a paused mid-file
frame; a final-build EOF-specific native check remains separate.

The final integrated HFS+ Release run passes all 535 tests with no failures or
skips, including all ten backend/outcome combinations in the new reload test
(2.849 seconds), both official ITU reference sets and actual disk-full recovery.
Evidence: `/tmp/aagedal-inspector-final-hfs-20260911/Tests.xcresult` and adjacent
logs/summary. Release preflight passes all 61 checks in
`/tmp/aagedal-inspector-final-preflight-20260911.log`.
Release static analysis passes in `/tmp/aagedal-inspector-final-analyze-20260911.log`.

This is focused pointer/native layout acceptance. A narrower stacked-button
layout, broad comparison-mode coverage, fullscreen/HDR hardware acceptance,
Full Keyboard Access and spoken VoiceOver are not claimed by this check.
