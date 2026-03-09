<img width="200" height="200" alt="AagedalMediaPlayer" src="https://github.com/user-attachments/assets/e2234529-3fe6-458b-98ae-87761418c8d2" />

# Aagedal Media Player
![SCR-20260221-pzdf](https://github.com/user-attachments/assets/5c066416-8542-402f-83df-f49cc01a9bc4)

Based on the same fast engine as [Aagedal Media Converter](https://github.com/aagedal/Aagedal-Media-Converter), but now for quickly just checking playback of files.

## Features

### File support
Playback (almost) every audio and video file in existence, through a combination of mpv and AVFoundation.
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

### Timecode display and input
Display timecode, with quick switching between source timecode, relative timecode and a frame counter view.
You can also input both absolute timecode, and use + and - before a number to jump relative to the current playhead position.

### Lossless Trim
One of the most missed features from QuickTime is now available in an open source app. Quickly set an in and out point using I and O keys, then use Command + E to export.
Select a default export location in the settings, or save next to the original, or always be asked where to save it.

### Professional Shortcuts
Use proper JKL playback controls, like in all professional video editing software. Professionals can finally feel at home in a free and open source video player.
You can also hold Option while dragging the playhead for 4x more precise dragging. Useful for finding an exact scene in longer videos.

### Screenshots
Take quick screenshots at source resolution in JPEG XL, JPEG or PNG. Command + S.
Select a default export location in the settings, or save next to the original, or always be asked where to save it.

### Video Scopes
Real-time waveform, waveform RGBY parade and vectorscope overlays for monitoring exposure and color. Toggle with Command + Shift + W. Configurable resolution and frame rate in scope settings. By default the waveform is overlayed over the video, but can also be opened in a separate window.

### Audio waveform
Preview multichannel audio tracks as waveforms, with one waveform per channel. Toggle with Command + Shift + A. Supports multi track files. Changing the audio output track will update the preview to the audio channels from the selected audio track. Navigate by clicking on a point in the audio waveform to jump to that location in the video. By default the audio waveform is overlayed over the video, but can also be opened in a separate window.

### Metadata
Quickly check basic metadata like resolution, frame rate, codec, color space and chroma sub sampling information. Command + I. Includes button to

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
| Cmd + S | Save screenshot |
| Cmd + I | Toggle inspector |
| Cmd + Shift + W | Toggle video scopes |
| Cmd + Shift + S | Sync timecode across windows |
| Cmd + Shift + R | Reload player |
