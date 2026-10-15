# Native MPV audio metering prototype

The development probe uses the existing MPV playback decoder. Open the Live
Audio Meter with `AAGEDAL_MPV_AUDIO_PROBE=1` in the app process environment to
show its readings alongside the existing source meter. Ordinary launches add no
filter, query or panel content. Shipping package pins and the native-raster
provider's default-off gate remain unchanged.

The [arm64 acceptance record](evidence/mpv-native-audio-probe-20261015/README.md)
retains the 65-test run and nine numerical comparison cases. A built candidate
is available at `build/native-audio-probe-candidate-20261015/Aagedal Media Player.app`.

This is a comparison instrument. It does **not** replace the source meter or
remove that meter's FFmpeg subprocess. Its additional filter work increases the
cost of this side-by-side prototype. Decoder-elimination performance gains have
not been established.

## Measurement identity

The panel prepends one uniquely labelled `lavfi` graph to the active player's
audio filter chain:

```text
ebur128=metadata=1:peak=true:framelog=verbose,
astats=metadata=1:reset=0:measure_perchannel=Peak_level+RMS_level:measure_overall=Number_of_samples
```

Sample/true peaks are cumulative filter maxima; RMS averages the filter's
segment. These are deliberately not the source meter's 50-ms peak buckets or
display ballistics. Cumulative peaks survive gaps in UI polling. Momentary and
Short-term readings require at least 400 ms and 3 s of filter samples. Unknown
or malformed values never become zero levels. A true-peak amplitude rounded to
zero displays “below precision,” rather than claiming exact digital silence.

The probe follows only the selected A/B player's active playback track, with
forward 1× playback. Independently selected meter tracks, grouped programmes,
AVPlayer, pause, buffering and unsupported speeds leave the source meter as
the measurement path. Seek, loop, source/track changes, meter resets and panel
closure cancel outstanding results and remove only the probe's own filter.
Resume starts a fresh filter segment. Source format/readiness revisions also
reset it. One asynchronous query can be outstanding, at most ten per second;
the model retains one reading and no growing history.

The `af pre` position precedes this app's ordinary channel audition pan filter.
It does not establish a decoder-output tap before every MPV conversion or
processing operation. Filter input may already have been negotiated or
converted. The displayed player clock is the clock **at query time**, not the
measurement's PTS. Even cumulative filter sample counts are not source-frame
provenance.

## Why the filters cannot yet replace source QC

The [MPVKit audio release handoff](https://github.com/aagedal/MPVKit/blob/625d93cc3b4037b415d89f622effac02da202dac/docs/audio-meter/README.md)
documents that `af-metadata` returns the latest frame and can lead audible
playback. Per-frame peak polling can miss transients. Keeping cumulative peaks
solves that particular loss but does not provide timestamped peak buckets,
source-clock alignment or reliable window maxima.

The retained FFmpeg n8.1.2 `f_ebur128.c` serializes linear true-peak amplitudes
with three decimal places. Low-level peaks therefore lose substantial dB
precision. Its raw conventional 7.1 weighting also differs from Media Player's
existing Annex 3 correction: a rear-only signal demonstrates approximately
1.49 LU difference. These readings must not silently replace the existing
source DSP. The app labels raw loudness and approximate true peaks explicitly.

A subsequent native provider should expose versioned, timestamped measurements
or original PCM from a defined point before routing, with explicit speaker
layout, sample rate, track identity and seek generation. It needs bounded
delivery, an overrun failure state, complete transient/maxima retention,
full-precision values and EOF-tail handling. Reusing the existing source DSP
would preserve the current true-peak and channel-weighting behavior. The
existing FFmpeg path remains necessary for independently selected tracks,
grouped programmes, AVPlayer and unsupported native providers.

## Prepare an arm64 candidate without rebuilding MPVKit

Read [the native-raster handoff](MPV_NATIVE_RASTER_HANDOFF.md) first. Obtain its
verified baseline restoration, the restored pinned scope delta from
[the scopes handoff](MPV_NATIVE_SCOPES.md), and the retained archives plus
`release.json` for MPVKit `aagedal-1.0.0-n8.1.2-audio.1`.

```sh
python3 scripts/prepare-mpv-audio-probe-app.py \
  BASELINE_RESTORATION RESTORED_SCOPE_DELTA AUDIO_RELEASE NEW_OUTPUT

xcodebuild build-for-testing \
  -project 'NEW_OUTPUT/app/Aagedal Media Player.xcodeproj' \
  -scheme 'Aagedal Media Player' -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath NEW_OUTPUT/derived \
  -onlyUsePackageVersionsFromResolvedFile \
  ENABLE_TESTABILITY=YES ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

The preparation script verifies both pinned inventories and the checksum-pinned
audio release descriptor, then verifies each of the seven FFmpeg archive and
binary hashes. It copies the package, keeps the accepted native-scope libmpv,
and extracts only arm64 slices of the new FFmpeg libraries. Both candidates use
FFmpeg n8.1.2. `receipt.json` records each new binary hash. This combined overlay
needs its own consumer validation; the dependency's original acceptance receipts
alone do not validate it. Inputs and shipping project files are never edited.

## Validation

Parser tests cover map types, bounds, duplicate keys, units, silence, warm-up,
invalid numeric values and channel mismatches. Session tests cover default-off
behavior, missing filters, one outstanding query, stale-result rejection,
replacement and teardown.

Set `AAGEDAL_MPV_AUDIO_PROBE_TESTS=1` in the hosted test target's xctestrun
`EnvironmentVariables`, then run `MPVNativeAudioMeterIntegrationTests` for arm64
with parallel testing disabled. Require the
`MPV_NATIVE_AUDIO_PROBE_ACCEPTANCE` marker, successful XCTest and zero failures.
The test compares actual native filter output with the existing Swift DSP for
mono/stereo/5.1/7.1, 44.1/48/96 kHz, silence, LFE isolation, a brief transient and
intersample peaks. It deliberately waits over three seconds before polling,
checks mute/volume and a downstream audition filter, then checks filter removal
and exact seek/restart. A fresh post-seek filter must not restore old maxima.
The 7.1 case requires the known weighting difference, rather than hiding it.

These generated PCM cases do not establish compressed-decoder gain equivalence,
physical output latency, long-duration boundedness or a performance improvement
over the shipping meter. Those remain gates for a future replacement provider.
