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
