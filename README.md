<img width="200" height="200" alt="AagedalMediaPlayer" src="https://github.com/user-attachments/assets/e2234529-3fe6-458b-98ae-87761418c8d2" />

# Aagedal Media Player
![SCR-20260221-pzdf](https://github.com/user-attachments/assets/5c066416-8542-402f-83df-f49cc01a9bc4)

A fast, private professional media inspection player for macOS. Compare masters,
inspect picture and sound, verify metadata and timecode, and export review evidence
without uploading your media.

## Inspect a reference against an encode

1. Open the reference file as A, then use the toolbar's **Add comparison file**
   control to load its delivery encode as B. B starts silent.
2. Check the alignment status and overlapping interval. **Source timecode**
   aligns embedded timecodes; **Relative start** aligns file starts when either
   timecode is missing. Use [manual alignment](docs/COMPARE_MODE_ALIGNMENT.md)
   for an intentional offset in seconds or A frames.
3. Play, pause, scrub, or frame-step with the shared transport. Choose
   **Vertical Wipe** from **Compare view** and drag the divider across fine
   detail, or press **B** to switch between A and B. **Display Difference**
   highlights visible differences; it is not an objective quality score.
4. Press **Command-Shift-M**, enable **Show loupe**, and inspect a detail at
   2×, 4×, or 8×. **Pin picture position** keeps that location while you operate
   playback. The paired previews use the same normalized picture coordinate;
   their captures are independent, not frame-locked or exact source-pixel 1:1.
5. Pause at a useful comparison point and choose **File > Export Comparison
   Still** (**Command-S**). The annotated PNG places A and B side by side with
   filenames, timecodes, alignment, inspection view, and technical details. It uses that fixed
   layout regardless of the live wipe, overlay, or difference selection.

Loupe and still imagery are display-space previews; HDR appearance can differ
from the live display. For a repeatable local example, generate the reference
and encode pair in [the demo guide](docs/COMPARE_MODE_DEMO.md).

Ordinary windows can also share transport commands; see
[window synchronization](docs/WINDOW_SYNCHRONIZATION.md) for its scope and the
separate one-time timecode alignment command.

## Roadmap

See [PRODUCT_ROADMAP.md](PRODUCT_ROADMAP.md) for the release sequence from the
1.6.1 reliability foundation through Compare Mode, Audio QC, and review/report
workflows.

## Local verification

Media integration tests use tiny, locally generated clips so large binary
fixtures are never committed:

```bash
scripts/generate-test-fixtures.sh
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS"
```

The generator requires a full ffmpeg installation with libx264/libx265. Set
`FFMPEG=/path/to/ffmpeg` to select one explicitly. If fixtures are absent, only
the generated-media tests are skipped; all pure unit tests continue to run.

Scope rendering has an optimized profiling matrix covering every available
scope resolution and the full 5–30 fps update-rate range:

```bash
scripts/profile-scopes.sh
```

The report includes luma and RGBY parade render time, sustainable update rate,
and estimated renderer load for every supported update-rate setting. Timings
are machine-dependent, so compare changes on the same hardware and profile on
the oldest Mac supported for release when changing scope capture or rendering.

Compare Mode has a separate opt-in production-resolution profile:

```bash
scripts/profile-compare-mode.sh | tee compare-mode-profile.txt
```

It generates disposable UHD 10-bit HDR sources, exercises all four MPV and
AVFoundation backend pairings with extended drift assertions, and drives the
real mixed-backend comparison canvas through every visual mode. See
[the Compare Mode performance methodology](docs/COMPARE_MODE_PERFORMANCE.md)
for configuration, pass criteria, and the complementary Instruments run.

Long-recording audio waveform aggregation has a separate 1, 8, and 24-hour
multichannel profile:

```bash
scripts/profile-audio-waveforms.sh
```

Its report includes decode time, fixed accumulator size, and resident-memory
growth. See [docs/AUDIO_WAVEFORM_PERFORMANCE.md](docs/AUDIO_WAVEFORM_PERFORMANCE.md)
for the current baseline and methodology.

Release builds support Apple Silicon (`arm64`) on macOS 15 or later. Maintainer
preflight, signing, architecture, entitlement, and ffmpeg provenance guidance is
in [docs/RELEASE.md](docs/RELEASE.md).

## Features

### Compare Mode
Load a second master in the same window and inspect both with shared, frame-accurate
transport. Compare Mode aligns sources by embedded timecode when possible and offers
side-by-side, instant A/B, draggable wipe, opacity overlay, and display-space
difference views. Source B stays silent unless you explicitly switch monitoring,
with optional matching-channel isolation for multichannel A/B checks. Annotated
stills and review reports keep filenames, timecode, alignment, and technical
context attached. Selected-track audio details show A/B channel labels, layout
mismatches, and unmatched speaker roles; see [audio inspection](docs/COMPARE_MODE_AUDIO.md)
for semantic versus positional channel pairing. Review storage, schema, and
portability limits are documented in [comparison review sidecars](docs/COMPARE_REVIEW_SIDECAR.md).

### Inspection loupe
Open the magnifying-glass control (Command-Shift-M) to enable a 2×, 4×, or 8×
preview. Move over the fitted picture, or pin the position to operate playback
controls. Position sliders and Center and pin support inspection without precise
pointer movement. Compare Mode shows paired A/B loupes at the same normalized
picture coordinate.

The preview uses display-space captures at up to 10 fps. HDR appearance may
differ from the live display, and the A/B samples are not frame-locked. Exact
source-pixel 1:1 inspection and whole-viewport zoom remain planned. See
[the loupe validation guide](docs/INSPECTION_LOUPE.md).

### File support
Playback (almost) every audio and video file in existence, through a combination of the mpv and AVFoundation.
As of 2026-02-21, it supports more codecs than IINA; ProRes RAW, Advanced Professional Video (APV), and VVC (H.266).

Some of the supported formats here:
| Containers | Video Codecs | Audio Codecs |
| :--- | :--- | :--- |
| MOV | ProRes / ProRes RAW | WAV |
| MXF | DNx and APV | ALAC |
| MP4 (`.mp4`, `.m4v`) | H.264 (AVC) | AAC |
| MKV (`.mkv`) | H.265 (HEVC) | MP3 |
| WebM (`.webm`) | VP9 | Opus |
| AVI (`.avi`) | AV1 | FLAC |

(Notable exceptions are other professional RAW video codecs.)

### Speed
Launches faster than IINA and QuickTime. 1 second vs 2 seconds.
Tested 2026-02-21 on an M1 Max MacBook Pro.


### Professional Shortcuts
Use proper JKL playback controls with up to 8x playback speed. Professionals can finally feel at home in a free and open source video player.
You can also hold Option while dragging the playhead for 10x more precise dragging. Useful for finding an exact scene in longer videos.


### Timecode display and input
Display timecode, with quick switching between source timecode, relative timecode and a frame counter view.
You can also input both absolute timecode, and use + and - before a number to jump relative to the current playhead position.


### Lossless Trim
One of the most missed features from QuickTime is now available in an open source app. Quickly set an in and out point using I and O keys, then use Command + E to export.
Select a default export location in the settings, or save next to the original, or always be asked where to save it. Including a few settings for format. Default is lossless trim.


### Screenshots
Take quick screenshots at source resolution in JPEG XL, JPEG or PNG. Command + S.
Select a default export location in the settings, or save next to the original, or always be asked where to save it.


### Video Scopes
Real-time waveform, waveform RGBY parade and vectorscope overlays for monitoring exposure and color. Toggle with Command + Shift + W. Configurable resolution and frame rate in scope settings. By default the waveform is overlayed over the video, but can also be opened in a separate window.
![SCR-20260309-ucop](https://github.com/user-attachments/assets/9fc2e4fb-8407-4b87-b71e-eb6d47ee383b)


### Audio waveform
Preview multichannel audio tracks as waveforms, with one waveform per channel. Toggle with Command + Shift + A. Supports multi track files. Changing the audio output track will update the preview to the audio channels from the selected audio track. Navigate by clicking on a point in the audio waveform to jump to that location in the video. By default the audio waveform is overlayed over the video, but can also be opened in a separate window.
![SCR-20260309-uczb](https://github.com/user-attachments/assets/55a05fce-6dd8-4fde-9c66-2b4ef312fd20)


### Metadata
Quickly check basic metadata like resolution, frame rate, codec, color space and chroma sub sampling information. Command + I. Includes button to analyze LUFS levels (EBU 128).
<img width="1227" height="691" alt="SCR-20260309-udpk" src="https://github.com/user-attachments/assets/52a86143-f944-4137-988a-e7a2c585bbaa" />




## Keyboard Shortcuts

### Playback

| Shortcut | Action |
| :--- | :--- |
| Space | Play / Pause |
| J | Reverse playback |
| K | Pause |
| L | Fast forward |
| Option + J | Slow reverse |
| Option + L | Slow forward |
| F | Toggle fullscreen |
| M | Mute / unmute |
| Control + Up Arrow | Increase volume |
| Control + Down Arrow | Decrease volume |

### Navigation

| Shortcut | Action |
| :--- | :--- |
| Left Arrow | Step back 1 frame |
| Right Arrow | Step forward 1 frame |
| Up Arrow | Step back 10 frames |
| Down Arrow | Step forward 10 frames |
| Shift + Left Arrow | Seek backward 10 seconds |
| Shift + Right Arrow | Seek forward 10 seconds |
| Cmd + Up Arrow | Seek to start |
| Cmd + Down Arrow | Seek to end |
| Cmd + [ | Open previous media file in folder |
| Cmd + ] | Open next media file in folder |

### Trim

| Shortcut | Action |
| :--- | :--- |
| I | Set in point |
| O | Set out point |
| Shift + I | Go to in point |
| Shift + O | Go to out point |
| Option + I | Clear in point |
| Option + O | Clear out point |
| Option + X | Clear all trim points |
| Cmd + E | Export trim |

### Timecode

| Shortcut | Action |
| :--- | :--- |
| T | Cycle timecode display mode |
| 0–9, +, -, ., :, ; | Activate timecode input |
| Cmd + Shift + C | Copy timecode |
| Cmd + Shift + V | Paste timecode |

### General

| Shortcut | Action |
| :--- | :--- |
| Cmd + O | Open file |
| Cmd + N | New window |
| Cmd + W | Close window |
| Cmd + S | Save screenshot, or export an annotated still in Compare Mode |
| Cmd + I | Toggle inspector |
| Cmd + Shift + W | Toggle video scopes |
| Cmd + Shift + S | Sync timecode across windows |
| Cmd + Shift + R | Reload player |
