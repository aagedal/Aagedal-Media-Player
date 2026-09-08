# Native 7.1 correction and scope layout check — 2026-09-08

The local Release app based on `00c5267` was exercised on the development
Mac through native accessibility actions and keyboard events. The disposable
eight-second fixture contains a 48 kHz Float32 conventional 7.1 stream, with
a 0.1-amplitude 1 kHz sine on Back Left and silence on the other speakers.
Playback remained paused; no production media or review data was changed.

```bash
'Aagedal Media Player/Binaries/ffmpeg' -hide_banner -loglevel error \
  -f lavfi -i 'aevalsrc=0|0|0|0|0.1*sin(2*PI*1000*t)|0|0|0:s=48000:d=8:c=7.1' \
  -c:a pcm_f32le -n /tmp/aagedal-native-71-20260908.wav
'Aagedal Media Player/Binaries/ffmpeg' -hide_banner -loglevel error \
  -i /tmp/aagedal-native-71-20260908.wav -c:a copy \
  -n /tmp/aagedal-native-71-20260908.mov
```

## Observations

- Command-I opened the metadata inspector for the MOV. It identified eight
  channels and exposed the complete pre-measurement explanation of the
  BS.1770-5 correction in the accessibility tree.
- Activating **Measure loudness for audio stream 1** completed with
  **−23.0 LUFS**, **0.0 LU**, and **−20.0 dBTP**. The post-measurement text
  describes corrected rear-speaker weighting and unchanged true-peak samples.
- The post-measurement explanation wraps completely at the normal roughly
  270-pixel inspector width. Metric labels remain combined with their units
  and values in the accessibility tree.
- The same screenshot exposed a separate layout issue: the inline
  **Loudness Analysis** label was shortened to **Loud…** by the segmented
  control. This continuation places the label above the control while
  retaining the stream-specific accessible label and shared-scope hint.
- Rebuilding and reopening the fixture confirmed the complete heading above
  both scope choices, full correction text, and the same measured values.
  The accessibility tree still identifies the scope as belonging to stream 1.
- Command-I hide/reopen preserved the completed measurement before the
  rebuild. A later range-selection attempt was interrupted by an app-state
  change and is not recorded as a keyboard or range-interaction pass.

## Limits

This is focused native layout and activation evidence. It does not establish
spoken VoiceOver narration, Full Keyboard Access traversal, audible channel
monitoring, or concurrent playback performance. The original Float32 WAVE
opened for playback but the inspector reported no metadata; the MOV remux was
used for the measurement check. These observations do not expand format or
standards-conformance claims.

## Integrated verification

The isolated full Release suite passed all 426 tests with zero failures,
expected failures, or skips. Results are retained in
`/tmp/aagedal-improvements-full-isolated-20260908.xcresult` (temporary storage).
Xcode static analysis and all 61 release-preflight checks pass. An earlier run overlapped native app
automation and recorded five test-host exits rather than assertion failures;
the clean run was performed with native automation stopped.

## WAVE metadata follow-up

The missing inspector metadata was traced to `MetadataService` calling only
SwiftMediaMetadata's `readVideoMetadata` entry point. That API does not accept
standalone RIFF/WAVE. The pinned dependency also has `AudioMetadata.read` and
`WAVParser`, but the latter copies every chunk payload (including audio), does
not compute duration, and labels any eight-channel stream `7.1` without reading
its speaker mask. Using it directly would undermine both bounded metadata
memory and the explicit speaker-layout requirement for the loudness correction.

The app now reads ordinary little-endian RIFF PCM and IEEE-float WAVE headers
on a background task, seeks over audio and ancillary payloads, and maps the
result into the existing cached metadata path. WAVEFORMATEXTENSIBLE subformat
GUIDs, frame alignment, chunk boundaries, and declared rates are checked. The
conventional `7.1` label is supplied only for a matching eight-speaker `0x63f`
mask; unspecified or unknown surround placement remains unknown. RF64,
big-endian RIFX, compressed WAVE encodings, and BWF/INFO tag extraction remain
outside this reader's scope.

`WaveMetadataReaderTests` covers the original bundled-FFmpeg Float32 7.1
fixture through `MetadataService` and production loudness analysis (rear
correction, −23 LUFS, and −20 dBTP), synthetic format and mask cases, malformed
headers and chunk sizes, and a sparse one-GiB audio payload that must be skipped.
These are metadata integration regressions, not new native inspector or
VoiceOver acceptance evidence.

The Phase 53 integrated Release run passed all 435 tests with no failures or
skips in 111.298 seconds; static analysis and all 61 preflight checks pass.
Results: `/tmp/aagedal-continuation-full-verified-20260908.xcresult` and
`/tmp/aagedal-continuation-analyze-20260908.log` (temporary storage).
A further native comparison attempt encountered unresponsive picker automation;
no additional keyboard, review, or inspector acceptance pass is claimed.

## Rebuilt RIFF/RF64/BW64 acceptance

The later Phase 54 native check closes the ordinary-WAVE inspector gap: all
three container variants show correct eight-channel Float32 metadata and measure
−23.0 LUFS, 0.0 LU and −20.0 dBTP. See `WAVE_METADATA.md` for the exact scope.
The older app was explicitly quit before opening the rebuilt Release product;
test-host runs and native automation were kept separate.
