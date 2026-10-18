# LUFS over the waveform

The arm64 Release candidate builds and passes deep/strict signature verification.
All **77 focused hosted tests** pass with zero failures, skips or runtime warnings.
[Test summary](test-summary.json) and [source/binary receipt](candidate-receipt.json)
identify the accepted code. The existing checksummed local MPVKit baseline/scope
delta was verified and reused, with shipping pins and provider gate unchanged.
The first sandboxed signature check could not access trust services
(`CSSMERR_TP_NOT_TRUSTED`); the normal permitted check passes.

Six new waveform checks cover source-time range placement, independent momentary
and short-term warm-up, gaps/invalid samples, fixed-scale clipping, media identity,
audio-ordinal result ownership, programme/track selection, and actual rendered
trace pixels above waveform images. A seventh check verifies that programme
completion callbacks publish only a current successful measurement. The remaining
checks exercise waveform lifecycle, track selection, programme analysis and real
bundled-FFmpeg loudness references, including the existing bounded history tests.
`run-tests.py` retains the exact suites/configuration and enables optional renderer
previews in the local output directory. Rendering tests attach their images to
XCTest; the standalone ImageRenderer cannot render the native Menu control, so
its placeholder is not treated as native menu evidence.

## Native check

The built signed app was opened through native computer-use tools. A generated
24-second stereo PCM fixture was opened via File → Open:

```sh
'Aagedal Media Player/Binaries/ffmpeg' -hide_banner -loglevel error \
  -f lavfi -i 'aevalsrc=0.15*sin(2*PI*440*t)*(0.55+0.45*sin(2*PI*t/8)):s=48000:d=24' \
  -ac 2 -c:a pcm_s16le /private/tmp/aagedal-waveform-lufs-20261018/lufs-demo.wav
```

The inspector's Measure LUFS action completed at −23.1 LUFS integrated and
11.8 LU range. Both cyan momentary and dashed yellow short-term traces appeared
above the waveform. The real native LUFS menu showed the selected track and
checked Show LUFS graph action. Activating that action with Return removed the
traces and graph accessibility description; repeating restored both. The
waveform accessibility Increment action sought to one second with the graph
visible, confirmed by both waveform and transport timecode. Closing the
inspector preserved the graph after the sidebar/layout transition settled.
Native screenshots and accessibility states were inspected in the task session.
This is focused generated-media acceptance, not full VoiceOver or a multitrack
native acceptance matrix. Window/overlay modes share AudioWaveformView; the
floating panel was not separately qualified by this hands-on check.

Completed results are player-owned and keyed by source media identity and audio
ordinal. Graph rendering reuses the existing bounded history and starts no audio
analysis. Range results retain their original source interval when trim points
change. Display is clipped to −70…0 LUFS. Single-channel rows show their selected
track; combined programme graphs identify the assigned tracks. See
[audio loudness documentation](../../AUDIO_LOUDNESS.md) for usage and limits.
