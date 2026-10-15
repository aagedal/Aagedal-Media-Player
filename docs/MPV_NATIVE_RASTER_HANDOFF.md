# Continue native-pixel loupe work without rebuilding MPVKit

Restore the validated **arm64-only development candidate** from the separate
[MPVKit candidate prerelease](https://github.com/aagedal/Aagedal-Media-Player/releases/tag/mpvkit-decoder-raster-arm64-20261014).
The [committed descriptor](mpv-decoder-raster-handoff.json) pins its URL, size,
archive SHA256 and inventory SHA256. It remains available when the original
`/private/tmp` build, this worktree, or the original package cache is gone.
This is an opt-in dependency artifact, not an app update or shipping package repin.
The restore path was verified at a new location: 31 native cases passed, and a
fresh-cache app build passed all 20 hosted fixture cases without MPVKit compilation.

## Restore and build the current app sources

From a checkout of this PR on an Apple Silicon Mac with Xcode and Python 3.12+:

```sh
python3 scripts/restore-mpv-decoder-raster-candidate.py \
  /private/tmp/aagedal-mpv-restored \
  --prepare-app "$PWD" --app-output /private/tmp/aagedal-native-app

cd /private/tmp/aagedal-native-app
xcodebuild build-for-testing \
  -project 'Aagedal Media Player.xcodeproj' -scheme 'Aagedal Media Player' \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/aagedal-native-derived \
  -clonedSourcePackagesDirPath /private/tmp/aagedal-native-packages \
  -onlyUsePackageVersionsFromResolvedFile \
  -only-testing:'Aagedal Media Player Tests/LoupeTrackDecoderTests/testMPVNativeRasterOptInUsesCurrentDecoderFrameAndRevokesOnResume' \
  ENABLE_TESTABILITY=YES ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

The download is about 838 MiB; allow about 4 GiB for extraction plus Xcode build
space. It includes the self-contained local MPVKit package (all 29 binary
targets), source archives and patch, original build receipts, independent
fixtures and three prelinked native clients. The eight rebuilt mpv/FFmpeg
frameworks are arm64 only; unchanged qualified auxiliary frameworks retain their
original slices. No MPVKit compilation or Metal compiler installation is needed.
Only Sparkle and SwiftMediaMetadata resolve remotely into the fresh app cache.

Use `--bundle /path/to/mpvkit-decoder-raster-arm64-20261014.tar.gz` for an
already-downloaded asset. Verification is mandatory in both paths. The script
requires new output directories, rejects escaping archive entries, preserves
framework links, and verifies every restored file against the pinned inventory.
It copies the app, changes only that copy to local MPVKit, and removes only the
now-local MPVKit entry from the copy's resolved file. Source shipping pins stay
unchanged. Keep the restored package while using that app copy.

Make app changes in the source checkout, then prepare another fresh app copy
without downloading or rebuilding the dependency:

```sh
python3 scripts/restore-mpv-decoder-raster-candidate.py \
  /private/tmp/aagedal-mpv-restored --reuse \
  --prepare-app "$PWD" --app-output /private/tmp/aagedal-native-app-next
```

## Rerun native and hosted validation

The retained clients can rerun all 31 original native cases at any restored path:

```sh
python3 scripts/validate-restored-mpv-decoder-raster.py \
  /private/tmp/aagedal-mpv-restored /private/tmp/aagedal-native-runtime-next
```

This verifies the pinned payload again, rebases fixture paths, and executes the
clients without compiling MPVKit, compiling a harness, or generating media.
Hardware cases require an interactive macOS session and active VideoToolbox;
software fallback does not count. The clients were accepted on macOS 27.0.1;
this is not a minimum-OS compatibility claim. New provider code or changed native
harness code is not tested by these prelinked binaries.

For the hosted XCTest, the prepared app contains `native-fixtures.json` with
paths rebased to the restored bundle. Add these values to the generated
`DerivedData/Build/Products/*.xctestrun` target's `EnvironmentVariables`:

```text
AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1
MPV_DECODER_RASTER_CASES=/private/tmp/aagedal-native-app/native-fixtures.json
```

Then run `xcodebuild test-without-building -xctestrun PATH_TO_XCTESTRUN
-destination 'platform=macOS,arch=arm64'` for
`LoupeTrackDecoderTests/testMPVNativeRasterOptInUsesCurrentDecoderFrameAndRevokesOnResume`.
Require the action-log marker `MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases`.
A passing test without that marker can be the stock preview-only branch and
does not establish native integration. To manually launch the built app, set
`AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1` in its process environment before launch.

The hosted runner configures a temporary copy of the xctestrun, disables parallel
testing, and requires both a successful XCTest exit and the acceptance marker:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-native-app/native-fixtures.json \
  /private/tmp/aagedal-native-hosted-next

python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-native-app/native-fixtures.json \
  /private/tmp/aagedal-native-stress-next --stress-cycles 6

python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-native-app/native-fixtures.json \
  /private/tmp/aagedal-loupe-playback-next --playback
```

Stress mode repeats all ten positive UHD/DCI/HDR cases with software and actual
VideoToolbox decoding. Each lifecycle checks independently decoded sample pixels,
seek freshness, paused-image reuse, three rapid loupe close/reopen sequences,
and resume revocation, followed by complete capture/controller teardown.
It measures `TASK_VM_INFO.phys_footprint` after each cycle and bounds subsequent
cycle-end samples to 256 MiB above the first complete warmup cycle. This is a
process growth check, not a total-memory ceiling, a peak-allocation measurement,
or sanitizer coverage of MPVKit. `--stress-cycles` accepts 3 through 100.
Look for `MPV_NATIVE_STRESS_ACCEPTANCE` and the per-cycle byte measurements.

Playback mode checks UHD SDR, PQ, and HLG previews with software/VideoToolbox
decoding, independent first-frame pixels for HDR, live color-space/depth tags,
and return to native inspection on pause. It measures delivered updates against
the screenshot backend alone: require more than the old 10 fps cap and at least
80% of backend throughput (capped at the 60 Hz scheduler target). The retained
fixtures are 2 fps, so they do not establish high-motion cadence. The subsequent
[playback evidence](evidence/mpv-loupe-hdr-playback-20261014/README.md) includes a
separate 3840×2160, 60 fps workload with changing luma, verified stream metadata,
independent decoded references, and a fresh-frame check. `--playback` and
`--stress-cycles` are separate runs.

## Default live secondary viewer

**Live video during playback** is enabled by default in the loupe controls.
It can be switched off without restarting to use captured previews instead.
No live-loupe environment flag is required. Forward MPV playback uses a silent second decoder
and a lens-sized Metal surface with GPU zoom/pan. Once ready, the ordinary loupe
capture stops; pausing restores the captured/native-raster path. Reverse and AV
playback retain capture. The second decoder never enables the native-raster
cache, even when the main candidate provider is enabled.

The [default-on candidate](evidence/mpv-live-loupe-default-20261014/README.md)
passes 28 loupe/rendering/fallback tests. Its arm64 app is available locally at
`build/default-live-loupe-candidate-20261014/Aagedal Media Player.app`.

Use a UHD 60 fps workload manifest for its presented-frame/clock acceptance:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/aagedal-live-viewer-next --live-viewer
```

For sustained concurrent decoder qualification, use the same UHD60 manifest:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/aagedal-live-viewer-soak-next \
  --live-viewer --soak-seconds 30 --soak-cycles 3
```

This opt-in XCTest runs two independent source/loupe pairs simultaneously
(four decoders), for each of the four SDR/PQ/HLG hardware/software-primary
workloads. `--soak-seconds` accepts 10–3600 seconds per workload;
`--soak-cycles` accepts 3–100 complete cycles and defaults to three.
Every three-second measurement window must deliver at least 45 completed Metal
presentations per second in each of the four surfaces. Each pair must keep
sampled effective clock drift within 100 ms, with at least 95% usable clock
samples. Followers must report VideoToolbox; primary decoding and output color
configuration are also checked. No screenshot readback is used during sampling.
After each complete cycle, physical footprint must stay within 256 MiB of the
first warmup cycle. In-playback samples are logged separately; they are not a
peak-memory measurement or an enforced total-memory ceiling.

Require `MPV_LIVE_LOUPE_SOAK_ACCEPTANCE` with the requested duration and cycle
count and a successful XCTest exit. This measures concurrent independent viewer
load, not the comparison UI, frame lock, sanitizer coverage, or HDR calibration.
The short `--live-viewer` test remains a separate transport/paused-native-raster
acceptance run.

The [prototype evidence](evidence/mpv-live-loupe-prototype-20261014/README.md)
records matching SDR/HDR output, VideoToolbox use, actual Metal presentations,
clock drift, crop pixels, lifecycle, and suppression of background screenshots.
This is independent-player synchronization, not frame lock. It adds one decoder
per MPV source while the loupe is open and live video is enabled.
The [concurrent soak run](evidence/mpv-live-loupe-soak-20261015/README.md)
adds three cycles of four 30-second UHD60 workloads with two source/loupe pairs
and bounded cycle-end memory growth. Longer loads still need qualification. The subsequent
[different-file comparison check](evidence/mpv-comparison-live-loupe-20261015/README.md)
qualifies short SDR/PQ and PQ/HLG comparison-canvas workflows with paired live
loupes; sustained comparison UI loads remain open. Shipping pins and the native provider's default-off gate
remain unchanged.

## Different-file comparison canvas qualification

[The accepted arm64 run](evidence/mpv-comparison-live-loupe-20261015/README.md)
passes both pairs in all three modes, with at least 58.99 loupe presentations
per second, 33.34 ms maximum follower drift and all 360 clock samples usable.

The comparison runner mounts the production `ComparePlayerView` and
`InspectionLoupeOverlay` together with the real comparison controller. It uses
SDR/PQ and PQ/HLG different-file UHD60 pairs, exercises side-by-side, vertical
wipe and overlay, and requires both live lenses to present at least 45 fps in
each three-second measurement. Each lens must follow its own source within
100 ms with at least 29/30 usable clock samples. Both screenshot workers must
remain idle during the measurements. Paired pause/seek must restore fresh
verified native rasters; closing and reopening must release and recreate both
followers while the comparison sources stay alive.

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/aagedal-comparison-loupe-next --comparison
```

Require successful XCTest exit and
`MPV_LIVE_LOUPE_COMPARISON_ACCEPTANCE: 2 pairs, 3 modes, paused seek and reopen`.
This is a short integration check. Its presentation counters measure the loupe
surfaces, not the comparison canvas. It does not establish composite pixel
correctness, A/B frame lock, sustained memory behavior, active scopes,
producer-authentic media, or physical HDR calibration.

## Sustained different-file comparison qualification

[The completed three-cycle run](evidence/mpv-comparison-live-loupe-soak-20261016/README.md)
**failed** the 100 ms drift gate: source B reached 133.3 ms and 166.7 ms in
the first SDR/PQ side-by-side windows. All 358 cadence windows met 45 fps and
cycle-end memory growth stayed within 256 MiB, but sustained comparison remains
unqualified. Investigate source/follower startup and comparison-loop transport;
keep the gates unchanged and rerun after a verified fix.

The comparison workload can also repeat both different-file pairs and all three
modes for sustained playback, including paused native-raster seek and loupe
close/reopen after every pair:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/aagedal-comparison-soak-next \
  --comparison --soak-seconds 30 --soak-cycles 3
```

`--soak-seconds` specifies 10–3600 measured seconds **per mode per pair**;
`--soak-cycles` specifies 3–100 complete cycles (default three). Measurements
finish the last three-second window, so each mode may run slightly longer than
requested. Every window requires both loupe surfaces to deliver at least 45
completed Metal presentations per second, no more than 100 ms effective
source/follower clock drift, at least 29/30 usable samples, and idle screenshot
workers. Between cycles, after host/controller teardown and a one-second
retirement allowance, physical footprint must remain within 256 MiB above the
first complete warmup cycle. In-playback physical footprint samples are logged
separately; they are neither peak measurements nor an enforced total-memory
ceiling.

Require successful XCTest exit and
`MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE` with the requested duration and cycle
count. A short comparison receipt cannot qualify this run. The workload uses
the production comparison canvas at 960×540 with UHD60 source decoders and
paired loupe surfaces. Presentation counters measure lenses, not canvas cadence
or unique video frames. Generated looped media, independent decoder clocks,
active scopes, composite pixel correctness, sanitizer coverage and physical HDR
calibration retain their existing qualification limits.

## Accepted state and next work

[Acceptance evidence](evidence/mpv-native-raster-expanded-20261014/README.md)
records 31/31 native cases, 20/20 hosted fixtures inside one XCTest, and 70/70
consumer/loupe tests with no skips. Hardware H.264 and 10-bit PQ/HLG HEVC match
independent references exactly in the accepted run. UHD/DCI bounds, all eight
orthogonal rotations/reflections, invalid matrix rejection, correct HDR tags,
seek freshness, paused-image reuse and resume revocation are covered.

The [provider document](MPV_DECODER_RASTER_PROVIDER.md) describes protocol 2,
cache/payload budgets and unsupported geometry/color combinations. Next work
includes sustained UHD/HDR memory and sanitizer checks, broader media/presentation
workloads, and physical HDR display qualification. Publishing a shipping provider
package and repinning the app remain separate work. The reusable development
bundle does not enable the default-off feature in ordinary builds.

[The subsequent app lifecycle run](evidence/mpv-native-raster-stress-20261014/README.md)
adds 66 passing consumer/loupe tests, all 20 hosted fixtures, and six repeated
UHD/HDR cycles (60 lifecycles, 180 rapid reopen sequences). Cycle-end physical
footprint stays below the first warmup cycle. Peak memory, long-duration load,
sanitizers, and physical HDR display qualification remain open.

App changes and rerunning these fixtures do **not** require a dependency rebuild.
Changing the provider C patch, FFmpeg configuration, or MPVKit internals does:
use the retained source archives and arm64-only reconstruction workflow, then
publish a new uniquely named artifact with new checksums and validation evidence.
Do not overwrite this candidate asset or reuse its acceptance receipts for new
provider code. The bundle retains the original source-stage archive and the
modified mpv source archive/commit/patch under `sources/`, plus the MPVKit license
and upstream README. Qualified auxiliary source/license provenance remains the
published GPL MPVKit release referenced by the retained source stage.
