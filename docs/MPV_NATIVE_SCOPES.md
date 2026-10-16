# Native MPV video scopes candidate

The arm64 development candidate computes the waveform, RGBY parade, and
vectorscope inside libmpv. It reads a reference to the current VO input frame;
it does not call `screenshot-raw`, wait for a renderer screenshot, or open another
decoder. The app receives only the three diagnostic images and frame metadata.
The [acceptance record](evidence/mpv-native-scopes-20261015/README.md) includes
signal checks, hardware/software cases, hosted tests and measured timings.

The source is now pushed to the separate MPVKit branch
[`feature/native-video-scopes-arm64-20261015`](https://github.com/aagedal/MPVKit/tree/feature/native-video-scopes-arm64-20261015),
commit `f548fea78e67e163f4024df9e7b3759e2dd638c9`. It includes an opt-in GPL
macOS arm64 build option, the combined provider/prerequisite/CoreAudio patch,
native tests and acceptance evidence. Its patched mpv source matches all 835
files in this accepted candidate. At the user's request, MPVKit `main` was
subsequently fast-forwarded to `7bab3c83af8b278a1eafc3ab52f009dbbca07b59`,
including the Converter compatibility record. Published package URLs remain
unchanged. Media Converter's project and resolved file both pin the preceding
`400202b687841fb394cbf0ef59ad8c6fcfc1275b` revision; its dependency was not changed.
Selecting the new source revision as a Swift package still resolves
the existing released binaries until a separate candidate publication/repin.

This is a local development dependency. The shipping MPVKit pins and
`AAGEDAL_MPV_DECODER_RASTER_CANDIDATE` default-off gate are unchanged. The scope
command needs no decoder-raster cache and works during playback or pause.
Shipping packages without the command retain their existing capture backend.
Audio waveform generation is unchanged.

## Try the built app

The candidate is at
`build/native-scopes-candidate-20261015/Aagedal Media Player.app`.
Open video and enable the existing scopes panel or overlay; no environment flag
is required for native scopes in this candidate. Waveform/parade switching reuses
the same native result. `AAGEDAL_SCOPE_BACKEND=screenshot` forces the previous
backend for development comparisons.

A/B **display-space difference** scopes deliberately retain their screenshot
inputs and current difference semantics. AVPlayer/ProRes RAW scopes also retain
their existing outputs. Unsupported MPV color representations fall back to
capture. Single-source native HDR scopes measure the encoded source signal,
which can differ substantially from the tone-mapped screenshot backend.

## Restore without rebuilding MPVKit

The uniquely named local delta is
`build/native-scopes-candidate-20261015/mpvkit-native-scopes-arm64-20261015-r3.tar.gz`.
Its exact size, archive hash and inventory hash are pinned in
[mpv-scopes-handoff.json](mpv-scopes-handoff.json). It contains the rebuilt arm64
libmpv archive, complete modified mpv sources, an applicable patch, compilation
receipt, newly linked native clients, independent signal fixtures and the
three UHD 60 fps workloads used for validation. The delta is local; it has not
been uploaded as a GitHub release. Retain it separately from this worktree.

First restore the original checksummed development bundle using
[the native-raster handoff](MPV_NATIVE_RASTER_HANDOFF.md). Then:

```sh
python3 scripts/prepare-mpv-scopes-app.py \
  /private/tmp/aagedal-mpv-restored \
  build/native-scopes-candidate-20261015/mpvkit-native-scopes-arm64-20261015-r3.tar.gz \
  /private/tmp/aagedal-scopes-restored \
  --prepare-app "$PWD" --app-output /private/tmp/aagedal-scopes-app

xcodebuild build-for-testing \
  -project '/private/tmp/aagedal-scopes-app/Aagedal Media Player.xcodeproj' \
  -scheme 'Aagedal Media Player' -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/aagedal-scopes-derived \
  -onlyUsePackageVersionsFromResolvedFile \
  ENABLE_TESTABILITY=YES ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Both inventories are verified before the overlay. The script creates a new
package and changes only the prepared app copy to reference it. The other 28
binary targets come from the verified baseline unchanged. A new restoration
was checked byte-for-byte against this candidate's archive. No new minimum-OS
or cross-machine native-client compatibility claim follows from this run;
clients were exercised on macOS 27.0.1 with the retained build dependencies.

## Provider contract and bounds

`aagedal-scopes <width>` accepts widths 64–1440 and returns protocol 1. Waveform
and parade dimensions are `width × round(width × 9/16)`; vectorscope is square
at that height. Each image is tightly packed premultiplied BGRA8 diagnostic
color in sRGB. The map also carries the source frame's PTS, active track ID,
primaries, transfer, scale peak, and hardware-transfer flag. The Swift consumer
checks protocol, dimensions, track, transfer/primaries/peak combinations,
finite PTS, duplicate/missing/type-invalid fields and exact payload sizes before
copying. These plots are analysis results, not source-pixel inspection proof.

App screenshot fallback processing runs explicitly in detached utility tasks,
including the synchronous mpv screenshot wait and SDR/HDR conversion. This
avoids inheriting the main actor through nonisolated async helpers under the
project's approachable-concurrency settings. Completed results still validate
capture generation and backend identity on the main actor before publication.
The shared one-shot HDR format diagnostic is synchronized.

The provider takes a VO frame reference under mpv's core lock, then releases
that lock while downloading, scaling and computing. A spawned command lets
playback continue. It reacquires the lock and rejects pending seeks, stop,
replacement and track changes. The app admits one request per capture session,
rejects obsolete completions, and restarts its generation-tagged timer when
switching capture modes. Diagnostic image history does not retain native plots.

Comparison scopes request analysis only for the selected source; display-space
difference requests both. Both capture sessions retain their running intent so
backend replacement can restore capture correctly. Changing selection revokes
old requests and timer ticks, clears old samples, and schedules ticks for the
new generation. An unselected source skips analysis, including screenshot
fallback. AV outputs remain attached until normal capture teardown so selection
does not change the ProRes RAW decode pipeline.

The app publishes completed native plot image references directly on the main
actor, including waveform/parade switches, without scheduling another scope
computation. A native submission first invalidates active and pending screenshot
computations so their late completions cannot replace the newer native plots.
The HDR scale is published before the render notification. This app-side change
needs no MPVKit rebuild or shipping package pin change; the earlier acceptance
throughput is not a measurement of this publication change.

Input is post-filter, pre-display-rendering video. Crop and orthogonal rotation
or reflection are applied to the analysed column ordering. Samples are scaled
once to RGBA16 while preserving source transfer values. Analysis uses the
existing resolution setting, so peaks narrower than that sampling grid can be
missed; this is not full-resolution peak certification. Inputs are bounded to
8192 per axis and 33,554,432 pixels before hardware download. UHD/DCI performance
is qualified here; 8K performance is not.

BT.709 SDR and BT.2020 PQ/HLG are supported. Luma/chroma coefficients and
vectorscope targets follow those primaries. PQ uses the ST 2084 EOTF and a
10,000-nit logarithmic axis. HLG uses the existing fixed 1.2 system-gamma,
1,000-nit display assumption. ICC/Dolby Vision and unsupported combinations
remain outside this provider. Physical HDR calibration and general colorist
instrument qualification are not established by these software fixtures.

This implementation performs native CPU analysis, including a shared pass for
all three plots and an EOTF lookup table. VideoToolbox surfaces still incur a
hardware download. GPU histogram analysis is a possible further optimization;
it is not needed to obtain the measured gain, and is not implemented here.
Direct publication does not remove the native analysis, pixel conversion,
VideoToolbox download or plot payload copies for selected sources. Unselected
capture sessions retain a lightweight timer and their existing AV outputs.
GPU analysis remains a possible further improvement.

## Rebuild only when changing provider source

With the retained validated build objects available:

```sh
python3 scripts/build-mpv-scopes-candidate.py \
  /path/to/validated-arm64-build /private/tmp/aagedal-mpv-restored \
  /private/tmp/new-scopes-candidate
```

This verifies the baseline inventory and clean declared source revision, copies
sources/objects, compiles only changed libmpv objects using the retained commands,
and overlays only libmpv in a new package. FFmpeg and auxiliary dependencies do
not need recompilation for this provider change. It emits a source patch,
compiler commands and archive hashes. The original build is never modified.

Without those objects, the retained offline reconstruction driver now accepts
`--scopes-candidate --decoder-raster-candidate --apple-silicon-only`, in addition
to its existing stage/hash/toolchain/header arguments. The provider sources are
in `docs/dependency-patches/scopes/`. That full reconstruction entry point has
source-retention tests; the candidate recorded here used the incremental path.

Changing provider code requires a new uniquely named artifact, checksums and
fresh validation. Do not reuse these acceptance receipts for changed code.
Use `package-mpv-scopes-candidate.py` to retain the new binary/source closure.

## Repeat validation

Link new clients with `scripts/link-mpv-scopes-harness.py BASELINE CANDIDATE`,
adding `--gpu` for the Metal/VideoToolbox client. The delta already includes both
clients for reruns on a compatible host. Client arguments are input video,
output prefix, hardware mode, scope width, and optional `play`.

`scripts/validate-mpv-scopes.py CLIENT NEW_OUTPUT --ffmpeg PATH` generates lossless
RGB16 SDR/PQ/HLG neutral ramps and color bars and independently checks all three
plots' occupied bins. `scripts/test-native-scope-math.c` covers all eight
orientations and all five analysis resolutions under ASan/UBSan.

Run `MPVScopePlotsTests`, `MPVNativeScopeIntegrationTests`,
`ScopeFrameDifferenceTests` and `MPVDecoderRasterTests` in the prepared app.
Set these values in the xctestrun target's `EnvironmentVariables` (under
`TestConfigurations[].TestTargets[]` for format 2):

```text
MPV_SCOPE_TEST_FIXTURES=/private/tmp/aagedal-scopes-restored/delta/validation/signal-fixtures
MPV_SCOPE_PLAYBACK_FIXTURE=/private/tmp/aagedal-scopes-restored/delta/validation/playback-fixtures/hlg-tagged.mp4
```

Run tests for arm64 with parallel testing disabled. Require successful XCTest
exit, no skips, `MPV_NATIVE_SCOPE_APP_ACCEPTANCE` and
`MPV_SCOPE_PLAYBACK_ACCEPTANCE`. Fixture-dependent integration tests otherwise
skip intentionally. The separate retained native-raster hosted acceptance also
passes with this rebuilt libmpv, with its existing opt-in environment and rebased
fixture manifest.
