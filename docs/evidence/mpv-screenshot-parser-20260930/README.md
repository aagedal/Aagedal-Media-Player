# MPV screenshot boundary and source-pixel audit — 2026-09-30

The MPV capture boundary now validates every required node's type before reading
its union payload. Missing/duplicate fields, unknown pixel formats, null/truncated
byte arrays, invalid strides and overflowing dimensions are rejected before any
pixel copy. The loupe uses the same raster-layout check. The immutable screenshot
value is explicitly nonisolated for background capture/conversion.

## Retained checks

Both runs use the Release configuration, the pinned package cache at
`/private/tmp/aagedal-itu-live-dd-20260930/SourcePackages`, disabled automatic
package resolution, and the unique derived-data directory
`/private/tmp/aagedal-mpv-raster-parser-dd-20260930`.

| Scope | Passed | Failures/skips/runtime warnings | Summary |
| --- | ---: | --- | --- |
| Eight new parser cases + ten loupe capture/gate cases | 18 | 0 / 0 / 0 | [parser-gate-summary.json](parser-gate-summary.json) |
| Real MPV oriented asymmetric decoder capture + fifteen loupe geometry cases | 16 | 0 / 0 / 0 | [live-geometry-summary.json](live-geometry-summary.json) |

The real decoder test uses the generated loupe fixtures to observe paused MPV
capture orientation and pixel colors. Geometry tests continue to reject MPV
screenshots as verified Native pixels, including when dimensions match metadata.
These focused tests do not establish native pointer/assistive-technology acceptance
or release-floor performance.

Result bundles remain at
`/private/tmp/aagedal-mpv-raster-parser-tests-final-20260930.xcresult` and
`/private/tmp/aagedal-mpv-loupe-live-20260930.xcresult`; logs use the same stems
with `.log`. [sha256.json](sha256.json) retains hashes of the tested source files,
package resolution, cached macOS GPL libmpv binary and both summary files.

## Remaining MPV 1:1 gate

The bundled MPV 0.41.0
[`cmd_screenshot_raw`](https://github.com/mpv-player/mpv/blob/v0.41.0/player/screenshot.c#L524)
calls `screenshot_get_rgb`, which calls `convert_image`. That conversion chooses
display dimensions, sets square pixel aspect and invokes swscale. The
[current upstream implementation](https://github.com/mpv-player/mpv/blob/master/player/screenshot.c)
retains this path. Software screenshots and RGB format selection do not bypass
the display conversion. The
[public render API](https://github.com/mpv-player/mpv/blob/v0.41.0/include/mpv/render.h)
renders video surfaces and does not expose a decoder-raster snapshot interface.

The actionable next step is a dependency capture API/command that retains a
decoded frame before arbitrary video filters, downloads hardware frames without
spatial resizing, and returns coded raster geometry, pixel aspect, display
orientation, source identity and frame PTS with the pixels. App conversion must
preserve spatial geometry, apply only whole-pixel rotation/reflection, and reject
stale preparation/track results. Native pixels must remain unavailable until that
path has independent anamorphic, rotated/reflected, filter and replacement
provenance checks. Screenshot dimensions alone cannot supply this proof.
