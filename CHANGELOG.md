# Changelog

All notable changes to Aagedal Media Player.

## [2.0.0] — 2026-10-09

Version 2.0 brings reference-versus-encode comparison, structured review, picture inspection and expanded audio analysis into one local media player.

### Added
- Compare two files with shared playback, frame stepping and scrubbing; align by source timecode, relative start or a manual offset.
- Inspect A/B, wipe, overlay and display-difference views, with technical mismatch summaries, overlap guidance and annotated comparison stills.
- Record review findings with severity, category, status and inclusive frame ranges. Search and navigate notes, retain them in sidecars, and relink moved media.
- Export review reports as CSV or annotated PDF, plus marker interchange for supported Resolve, Final Cut Pro and Premiere Pro workflows.
- Inspect detail with a movable, pinnable loupe and paired A/B previews, adjustable magnification and picture-position controls.
- Zoom the timeline up to 64×, pan through its overview, and inspect hover thumbnails and chapter markers.
- Open a per-player Live Audio Meter for A or B, with sample peak, true peak, Momentary, Short-term and integrated loudness, reference guides and a 60-second loudness graph.
- Measure individual audio tracks or explicitly assigned split-mono stereo/5.1 programmes without changing audible playback selection.
- Analyze whole-file or In–Out loudness offline, with loudness range, true peak, bounded graphs and copied measurement provenance.
- Read Broadcast WAVE and iXML recording metadata, including RF64/BW64, supported RIFX files and UTF-8/16/32 recording labels.
- Navigate comparison setup, review and report export directly from menus and keyboard shortcuts.

### Changed
- Large-file MPV scrubbing coalesces seek requests and performs a precise final seek when dragging ends.
- File opening displays loading feedback and performs potentially slow container checks asynchronously, keeping network-file opening and folder navigation responsive.
- New player windows start at 100% volume. Mono tracks can be assigned explicitly for stereo or surround playback.
- Live meters reset on source discontinuities, recover from brief clock lag with bounded retries, and cancel stalled or retired decoding.
- Playback controls hide in the right-edge pointer zone and return through keyboard navigation; active editing and popovers remain visible.
- Updated pinned playback and metadata dependencies improve CoreAudio playback and bound large-container metadata memory use.
- Release verification checks the exact source and dependency pins, optimized tests, static analysis, signing, notarization and downloadable artifact identity.

### Fixed
- Corrected SMPTE drop-frame calculations, precise mapped frame seeks and comparison clock sampling.
- Preserved playback position and pause intent through inspector changes, source reloads, window resizing and surface recovery.
- Protected review drafts and correction focus during filtering, concurrent sidecar updates, deletion, relinking, migration and save failures.
- Preserved supported marker timing, source identity, field order and authored text in editor exports, with explicit errors for unrepresentable cases.
- Bounded waveform, thumbnail, scope and long-file audio analysis work; rejected malformed buffers and stale asynchronous results.
- Made screenshot and trim output atomic and collision-safe, with cancellation and actionable completion or failure feedback.

### Compatibility and limitations
- Requires macOS 15 or later on Apple Silicon.
- MPV loupe captures remain display-space previews; verified native-pixel inspection is available only for eligible AVFoundation captures. HDR previews can differ from the live display.
- Editor marker formats have geometry, timing and text-formatting limits. Follow the export guidance; CSV/PDF retain findings that cannot be represented faithfully in a chosen editor format.
- Live loudness covers the current measurement segment. Seeking, source changes, reset or clock recovery begins a new segment; the displayed reference guides alone do not establish programme compliance.

## [1.6.0] — 2026-05-24

### Added
- Sparkle in-app auto-updates.
- HDR support in the video scopes, plus active-track highlighting in the scope overlay.
- Boost slider in the audio waveform view for amplifying quiet audio.
- Show-all-waveforms option for multi-mono audio files.
- Chapter marker picker in the controls bar.
- Pixel Aspect Ratio and Display Aspect Ratio as separate rows in the metadata inspector.
- Space key as a play/pause shortcut.

### Changed
- MPV is now the default playback backend for every supported codec; AVPlayer is reserved for ProRes RAW, where VideoToolbox outperforms MPVKit.
- Reverse → forward (L / Shift+L) now switches direction instantly instead of decelerating through zero.
- Backward playback uses MPV's native reverse mode, with a timer-driven fallback for codecs that can't seek backward.
- Metadata extraction now uses SwiftExif (pure Swift) instead of bundling an `ffprobe` binary — smaller app, faster reads, no subprocess.
- Resolution row in the metadata inspector now reports the displayed dimensions for rotated videos (e.g. iPhone portrait HEVC reads `2160 × 3840` instead of `3840 × 2160`).
- Source repository and MPVKit dependency moved to Codeberg.

### Fixed
- Anamorphic AVC clips (1440×1080 with 4:3 PAR → 16:9 display) were rendering at 4:3 instead of 16:9.
- Rotated iPhone HEVC clips were rendering as small landscape strips inside portrait windows.
- Window and Vulkan swapchain sizes could drift out of sync — on first load, after a live-resize, on fullscreen enter/exit, and during the initial layout-settle. The player now auto-recovers in each case.
- Video was cropped when switching files in the same window.
- Hardened the MPV event loop and `loadfile` command against rare races on file switch.
- Memory leak from NotificationCenter observers in the scope and waveform panels.
- ffmpeg stderr pipe-buffer deadlock in long-running operations.
- Screenshots captured from interlaced sources are now deinterlaced before saving.
