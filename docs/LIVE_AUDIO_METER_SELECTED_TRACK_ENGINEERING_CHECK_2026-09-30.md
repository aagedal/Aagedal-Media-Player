# Selected-track live-meter engineering check

This is generated-fixture harness plumbing evidence, not representative-media,
meter calibration, audible-output, long-play, or base-M1 release acceptance.
The actual profile runner used its Debug configuration with the production
metadata, PlayerController, MPV backend, meter session, bundled FFmpeg, DSP and
schema-2 validator. No clock-drift or decoded-ahead bounds were changed.

The host was a MacBook Pro (Mac17,8), Apple M5 Pro, 64 GB RAM, macOS 27.0.1
(26A434), Xcode 27.0 (27A266a), on battery. Native audio inventory reported the
built-in two-channel MacBook Pro Speakers at 48 kHz as the default output.
Initial runs occurred September 29; the temporary output diagnostic occurred
September 30. Their directory names retain the original September 29 suffix.

## Passing selected-track plumbing run

The generated 24-second MP4 has 64×64 MPEG-4 video at 24 fps and two AAC stereo
tracks: ordinal 0 at 44.1 kHz (440 Hz, different left/right amplitude), and
ordinal 1 at 48 kHz (880 Hz, equal left/right amplitude). The source SHA-256 is
`dfa0cc691d2b3455226b4521c973e06397a3a8220f99ae3dbd5fe541d708950e`.

```bash
LIVE_AUDIO_METER_PROFILE_CONFIGURATION=Debug \
LIVE_AUDIO_METER_PROFILE_DERIVED_DATA=/tmp/aagedal-phase139-derived \
scripts/profile-live-audio-meter.sh /tmp/live-meter-track-video-smoke-20260929 \
  --audio-stream-order 0 /tmp/live-meter-engineering-multitrack-video-20260929.mp4 \
  --audio-stream-order 1 /tmp/live-meter-engineering-multitrack-video-20260929.mp4
```

The test and validator passed, retaining two rows for the same hash with
different deliberate track requests. Both rows reported two available tracks,
matched requested/resolved ordinals, invariant monitor routing, successful
resume, child cancellation to zero RSS, and authoritative final EOF snapshots.
The runner's power check reported no sleep during the measured interval.

| Retained observation | Ordinal 0 | Ordinal 1 |
| --- | ---: | ---: |
| Selected sample rate | 44,100 Hz | 48,000 Hz |
| Published snapshots during five seconds | 104 | 101 |
| First snapshot latency | 64.47 ms | 170.08 ms |
| Maximum sampled snapshot interval | 191.86 ms | 297.04 ms |
| Maximum decoded-ahead interval | 241.67 ms | 241.67 ms |
| Cancellation latency | 0.51 ms | 1.25 ms |
| EOF start/end frame | 793,800 / 1,058,400 | 864,000 / 1,152,000 |
| EOF timestamp-authorized frame count | 264,600 | 288,000 |

The observation track identity comes from the production player's resolved
source before starting its meter session. The EOF ordinal also comes from the
completed decoder request provenance. The differing source rates and EOF
intervals independently exercise the second track's decoder configuration.
The sampled Debug snapshot intervals do not establish a release drawing-cadence
claim, and this run includes no trusted numerical-reference comparison.

Artifacts remain in `/tmp/live-meter-track-video-smoke-20260929`: input manifest,
environment, build/profile logs, `.xcresult`, attachments, power records and
validated `summary.json`. The generated source remains in `/tmp` and is not
copied into the repository.

## Retained mono audio-only failure

A separate generated 24-second audio-only MP4 contains AAC mono at 44.1 kHz
(ordinal 0) and AAC stereo at 48 kHz (ordinal 1). Selecting ordinal 0 failed
twice with the original production output configuration:

| Artifact directory | Observed result |
| --- | --- |
| `/tmp/live-meter-track-smoke-20260929` | CoreAudio rejected the mono input channel layout; the meter became unavailable with decoded source drift of −294.6 ms before routing checks. |
| `/tmp/live-meter-track-mono-recheck-20260929` | The same CoreAudio channel-map rejection recurred. AQME reported a failed output start after 15 seconds; the test then timed out waiting for paused meter state. |

Both logs contain `channel mapping input channel '1' for output channel '2' is
out of range` and MPV's `unable to set the input channel layout on the audio
unit` diagnostic. These observations identify native output negotiation as a
suspect; they do not prove an isolated DSP defect or establish that all mono
media fail.

One temporary Debug-only MPV initialization override set
`audio-channels=stereo`, using the same mono source and original meter bounds.
The run passed observation and pause/routing/resume without the original MPV
input-layout rejection, but subsequently threw `CancellationError` before EOF
and retained an Audio Unit converter-map warning. It therefore did not pass
the harness or establish a safe production correction. Its artifacts and exact
temporary patch are retained in
`/tmp/live-meter-track-mono-stereo-output-probe-20260929`. The override was
removed; the production MPV source has no change from this experiment.

A standalone ctypes probe using the linked MPV symbols lacked the native app
run loop and produced inconclusive clock behavior. Its `/tmp` logs are not
acceptance or causal evidence.

Mono audio-only native output initialization, meter freshness under failed
output, and pause/resume behavior remain open for investigation on this host
and other supported systems. A future correction must preserve multichannel
monitoring and decoded source PCM measurement; forcing every source to stereo
or weakening the freshness policy is not justified by these results.
