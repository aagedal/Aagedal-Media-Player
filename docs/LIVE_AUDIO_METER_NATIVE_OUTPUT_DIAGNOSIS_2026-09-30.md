# Native audio-output investigation — 2026-09-30

The retained mono failure remains unresolved in the shipped dependency. An
isolated native probe now establishes the CoreAudio property-type mismatch in
the exact linked MPVKit object and identifies a dependency repair candidate.
No output negotiation, driver, channel policy, decoder option, or meter freshness
bound was changed in production. The profiling runner now rejects retained
native-output errors even when source-meter rows pass.

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

## Isolated SDK-contract reproduction and dependency repair candidate

The project's pinned MPVKit revision is
`230c3174f1515898f24599147ad61c2a277d0dc2`. Its local build source is mpv
v0.41.0 (`41f6a645068483470267271e1d09966ca3b9f413`). The arm64
`audio_out_ao_coreaudio.c.o` extracted from the profile's actual linked framework
has the same SHA-256 as the local MPVKit build object:
`28ae6366e8b616cf1096dedbfc076325922bc24e473263324e0cb7f0cabf58bb`.
Disassembly confirms property ID 2002 with global scope, layout pointer and
layout allocation size at the failing call.

The current Xcode SDK's `AudioUnitProperties.h` documents property 2002
(`kAudioOutputUnitProperty_ChannelMap`) as an array of `SInt32` values on
input/output scopes. The linked source instead passes an `AudioChannelLayout`
structure on global scope. The stereo layout tag is 6619138, matching the
rejected "input channel" in the retained profile. This is a type-contract
defect, rather than evidence that source channel counts need changing.

The initialization-only [probe](../scripts/probe-coreaudio-channel-map.c)
repeats the malformed call and a correctly typed channel map without rendering
audio or changing system device settings. Three native repetitions per case on
the current default two-channel output produced:

| Input PCM | Malformed layout-as-map status | Typed output map status |
| --- | --- | --- |
| Mono interleaved float | −50 | 0 |
| Mono planar float | −50 | 0 |
| Stereo interleaved float | 0 | 0 |
| Stereo planar float | −50 | 0 |

Status 0 for malformed interleaved stereo does not make that value a valid map.
The probe zeroes layout padding; the production allocation contains other
layout data. It isolates the API misuse and its mono/planar failure; it does
not test the full production playback path, monitoring matrix, EOF, surround,
device switching or audible sound. A sandbox run returned −3000 before Audio
Unit construction; the retained results come from the native host run.

```bash
clang -Wall -Wextra -Werror -framework AudioToolbox -framework CoreAudio \
  scripts/probe-coreaudio-channel-map.c -o /tmp/probe-coreaudio-channel-map
/tmp/probe-coreaudio-channel-map
```

IINA independently diagnosed the same mismatch in
[issue 6378](https://github.com/iina/iina/issues/6378#issuecomment-5743963782)
and links an actual repair that builds a device-aware integer map. The
[retained candidate](evidence/live-meter-native-output-20260930/isolated-coreaudio-probe/iina-18384-audio-channel.patch)
comes from [dependency patch revision
f86d542](https://github.com/iina/deps-buildscripts/blob/f86d54276547df6d14104583ea604af67433f1e1/patches/mpv/18384-audio-channel.patch).
It passes `git apply --check` against the pinned local source; both touched C
sources also compile for arm64 and x86_64 with the current SDK and pinned build
headers. This is a checked repair candidate, not a rebuilt or shipped library.
IINA identifies remaining device-switch map-refresh work in that candidate.

The next production correction belongs in MPVKit's dependency build: retain the
patch attribution, rebuild both architectures, publish an artifact with a new
checksum and immutable revision, update this app's package pin, then rerun
audio-only mono/stereo and source-monitoring profiles repeatedly. Device-switch,
surround hardware and actual audible-output checks remain required. Do not
substitute AVFoundation or force stereo as acceptance: the prior option probes
failed. Probe results, candidate hash and source/binary/SDK identities are in
[isolated-coreaudio-probe](evidence/live-meter-native-output-20260930/isolated-coreaudio-probe).

## Stronger profiling-runner failure gate

The opt-in profile now enables MPV warning/error logs in Release and emits a
logging receipt only after the request succeeds. Its validator requires that
receipt for MPV rows and rejects AO `error`/`fatal` lines, audio-output
initialization failures, and the retained AudioConverter channel-map rejection.
Fallback-driver identity, advancing video clock and source-meter reports do not
waive those failures. The runner retains XCTest diagnostic attachments on failed
tests as well. Rejected validation removes any previous passing summary.

This is a stricter engineering-output regression requirement added to the runner,
not a claim that the source meter measures audible output. Lack of logged errors
still cannot establish audible sound or release acceptance. Existing schema-2
records remain historical source-meter evidence; the prior safe baseline is
explicitly rejected by the new native-output gate. Twenty Python validator
tests pass, including the retained false-passing baseline rejection; shell syntax
and the native probe compile checks pass.

After canonical verification, the same clean source `7bccab4` ran the actual
Release profiler against the original generated stereo-video input at both
explicit ordinals. All four logging receipts are retained; the XCTest and two
source-meter records pass, but CoreAudio channel-map failures make final
validation exit 1 with no passing summary. This supplies actual Release
integration evidence for the new rejection path, without claiming the output
defect is repaired. See [retained native run](evidence/live-meter-native-output-20260930/release-output-gate/README.md).

## Linked incremental repair candidate

The next parallel continuation provides an isolated rebuild tool and a locally
linked Release candidate. It rebuilds the two CoreAudio objects for both
architectures, verifies every unrelated archive object, preserves versioned
framework links and records source/config/compiler/database provenance. Six
builder safety regressions pass.

The unchanged production profile/output validator accepts four generated
input/track rows, then five rows in a second run including a hash-verified
authentic Sony stereo recording. Native logging receipts identify CoreAudio
and contain no output-initialization errors. Meter source identity, routing,
cancellation and EOF checks also pass. See
[the candidate build and native evidence](evidence/live-meter-native-output-20260930/incremental-rebuild/README.md).

This corrects the reproduced initialization defect in a local incremental
candidate. The app's shipping package pin remains unchanged. A full immutable
MPVKit build/repin, actual audible output, device switching, supported macOS,
surround hardware and release-floor acceptance remain open.
