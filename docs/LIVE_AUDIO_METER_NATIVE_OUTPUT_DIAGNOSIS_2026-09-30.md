# Native audio-output investigation — 2026-09-30

The retained mono failure remains unresolved. No output negotiation, driver,
channel policy, decoder option, or meter freshness bound was changed in
production. Temporary output probes were removed after their native harness
runs failed. The retained implementation adds read-only MPV decoder/output/AO
diagnostics and better failure evidence to the opt-in profiling test.

This check used the generated sources and native host described in
[the selected-track engineering check](LIVE_AUDIO_METER_SELECTED_TRACK_ENGINEERING_CHECK_2026-09-30.md).
It is generated-fixture engineering evidence, not calibrated metering,
audible-output, representative-media, surround-device, long-play, or base-M1
release acceptance.

## Temporary probes

All probes used Debug, the production controller/meter path, and unchanged
clock-drift and decoded-ahead bounds. The audio-only MP4's SHA-256 is
`af567c0e9eeedce1c08a5cd3f01759014389e4fe54ac336e3337ad822c5fdaf7`.

| Native artifact directory in `/tmp` | Temporary configuration | Retained result |
| --- | --- | --- |
| `live-meter-mono-scoped-output-native-20260930` | `on_preloaded` queried selected `aid` to choose stereo for mono; track selection also refreshed the policy | Initial and near-EOF loads still rejected the native mono channel map. Observation/routing/resume progressed, but the meter missed its 36-second EOF deadline. The hook precedes default track selection, so it cannot resolve the default source this way. |
| `live-meter-device-stereo-output-20260930` | Exactly two physical default-output channels selected `audio-channels=stereo`; other/unknown outputs retained `auto-safe`; `ad-lavc-downmix=no`; default-device listener and preloaded refresh | Mono ordinal 0 completed observation, routing, resume, cancellation and EOF. Its decoder remained one channel and output was two channels. The next stereo ordinal 1 rejected the native channel map and lost synchronization at −290.3 ms. The overall run failed; the lone completed row is not a validated passing input set. |
| `live-meter-device-avfoundation-output-20260930` | The same device-scoped policy also preferred `ao=avfoundation,`, retaining automatic fallback | The first mono observation lost synchronization at −290.4 ms without the original CoreAudio channel-map rejection. The overall run failed before routing or EOF. |

The latter two manifests also requested a generated six-channel PCM WAV after
the two AAC selections. Both runs stopped before that input; they provide no
six-channel production-playback acceptance evidence. The first sandbox-only
build failed on denied global Xcode cache writes before native playback; the
subsequent native builds succeeded.

The alternate stereo rejection included:

```text
channel mapping input channel '6619138' for output channel '0' is out of range [-1..'2')
unable to set the input channel layout on the audio unit
```

The prior successful stereo-video profile also contains this rejection when
selecting ordinal 1. A video clock can therefore permit source-meter plumbing
to pass while native output reports an initialization failure. A progressing
meter or `current-ao` value does not prove audible output.

Upstream [mpv 0.41.0 CoreAudio initialization](https://github.com/mpv-player/mpv/blob/v0.41.0/audio/out/ao_coreaudio.c)
passes channel-layout data to an Audio Unit channel-map property. This is a
suspect matching the rejected native maps, not an isolated causal proof about
the linked binary or all supported macOS versions. The
[mpv hook documentation](https://mpv.io/manual/stable/#hooks) explains that
`on_preloaded` runs before default track selection. The
[audio option documentation](https://mpv.io/manual/stable/#options-ad-lavc-downmix)
describes disabling decoder downmix when device output must preserve the
monitoring filter's source-channel input. Neither documented option probe
established a repeatable production correction here.

## Retained harness changes and passing safe baseline

The harness attaches `LIVE_AUDIO_METER_PLAYBACK_DIAGNOSTIC` JSON separately
from schema-2 profile reports. It records selected source/track, meter status,
generation, published snapshot count, available request/snapshot frames,
playback/native clocks, EOF state, native decoder/output channel counts, AO
identity, and monitoring-filter state at starts and failures. Non-finite
floating-point diagnostics become strings instead of making JSON disappear.
Unavailable meter state during sampling or pause now fails immediately with
the native diagnostic attachment. The existing timeouts and meter bounds are
unchanged.

The production routing check now verifies that decoder PCM retains the
selected source's channel count before and during the active channel mute
matrix. It checks the matrix before suppressing the audible track, so the
check actually observes an enabled decoder.

After removing all output experiments, the original generated stereo-video
input passed both deliberately selected ordinals with the revised harness:

```bash
LIVE_AUDIO_METER_PROFILE_CONFIGURATION=Debug \
LIVE_AUDIO_METER_PROFILE_DERIVED_DATA=/tmp/aagedal-mono-20260930-derived \
scripts/profile-live-audio-meter.sh /tmp/live-meter-output-diagnostic-baseline-20260930 \
  --audio-stream-order 0 /tmp/live-meter-engineering-multitrack-video-20260929.mp4 \
  --audio-stream-order 1 /tmp/live-meter-engineering-multitrack-video-20260929.mp4
```

The native XCTest passed with zero failures, both schema-2 rows validated,
routing/resume/cancellation/EOF checks passed, and the runner reported no
sleep. The diagnostics identify CoreAudio for ordinal 0 and AVFoundation for
ordinal 1 at the captured starts. The baseline still contains the native
stereo channel-map rejection; its passing source-meter profile does not close
the native-output gate.

Retained text/JSON evidence is in
[`evidence/live-meter-native-output-20260930`](evidence/live-meter-native-output-20260930).
Full build logs, `.xcresult` bundles, generated media and attachments remain
in the `/tmp` directories above. Future output corrections need repeated
audio-only mono and stereo passes, source-channel monitoring verification,
supported hardware/default-device-switch checks, and actual audible-output
acceptance without weakening meter freshness.
