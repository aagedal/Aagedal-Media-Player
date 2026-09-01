# Audio Waveform Performance

Audio waveform decoding now streams Float32 PCM directly from ffmpeg into
fixed-size per-column accumulators. It no longer creates a temporary raw PCM
file or loads a duration-sized `Data` value. The reproducible long-recording
profile is:

```bash
scripts/profile-audio-waveforms.sh
```

The script creates silent 7.1 WAV inputs at a low source rate to isolate the
duration and channel-count behavior, compiles the production streaming
accumulator with optimization enabled, and decodes them with the app's bundled
ffmpeg. Set `FFMPEG` to choose the full ffmpeg used to create inputs, or
`FFMPEG_DECODER` to compare another decoder build.

## Baseline — 2026-09-01

Hardware: MacBook Pro (Mac17,8), Apple M5 Pro, 64 GB memory.

| Duration | Channels | Columns | Decode rate | Elapsed | Accumulators | Resident delta |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 hour | 8 | 24,000 | 667 Hz | 0.57 s | 2.93 MiB | 1.95 MiB |
| 8 hours | 8 | 24,000 | 100 Hz | 2.51 s | 2.93 MiB | 3.00 MiB |
| 24 hours | 8 | 24,000 | 100 Hz | 6.77 s | 2.93 MiB | 3.00 MiB |

The fixed accumulators and measured resident growth remain effectively flat as
duration increases. Elapsed work still scales with the number of decoded
samples, while the 24,000-column width cap and adaptive decode rate prevent
long recordings from producing excessive PCM traffic.

The measurements cover PCM reduction and ffmpeg pipe handling, not image
rendering or UI composition. Re-run on the same hardware before and after
changes, and validate representative compressed production media when changing
decoder selection or sample-rate policy.
