# Native-pixel MPVKit development integration — 2026-10-14

A restricted, opt-in provider now passes a clean universal dependency rebuild,
native pixel tests, and the app's real loupe capture path. This is local
development acceptance, not a published dependency or completion of the general
MPV native-pixel feature. Shipping dependency pins are unchanged.

## Accepted results

- The published portable source bundle was downloaded and checked against
  SHA-256 `726d1b7bffcc4d7cfaf73a489140870c2bacda2fd55cb5454d4deabec1e08ade`
  and size 447,822,975 bytes. Its full publication inventory was verified before
  reconstruction. The retained publication manifest digest is
  `3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c`.
- Both arm64 and x86_64 mpv/FFmpeg slices were rebuilt from those source inputs,
  with the updated provider patch and existing CoreAudio repairs. Builds ran
  inside a network-denying sandbox. GPL/Metal/Samba requirements and every
  qualified boolean configuration digest pass; configuration differences are
  empty. Three provider C units and two CoreAudio units have fresh object and
  source identities per architecture in `portable-build.json`.
- Nine native cases pass for each architecture: enabled provider, default decoder
  queue, provider omitted, provider explicitly disabled, container rotation,
  anamorphic geometry, 50 load/unload cycles, duplicate PTS, and video-track
  changes. Successful captures verify all 256 BGRA pixels at independently
  defined frame times, including accurate/keyframe seek, frame-step and EOF.
  Invalid state checks require both capture and freshness to return unavailable.
- The x86_64 clients ran through Rosetta on this arm64 macOS 27.0.1 host. They
  establish this translated runtime case, not acceptance on Intel hardware.
  The retained executable link command uses host libraries and emits deployment
  target/architecture warnings for optional Homebrew libraries; this is not
  minimum-macOS or optional-feature runtime qualification.
- 38 focused Release app tests pass with the shipping dependency, with no skips
  or failures. The isolated candidate app then passes its hosted native loupe
  test with explicit opt-in and the independent numbered-grid fixture: all
  pixels at frame 0 and frame 5 (PTS 1) match, and resume removes source-raster
  proof. The test's native-branch acceptance marker is present in the XCTest
  action log; an unavailable provider cannot count as a native acceptance pass.
- Repository script-validator checks pass, including new source snapshot,
  patch/archive retention, and framework extraction checks.

## Fixes found by the broader checks

The original candidate returned the previous frame immediately after `stop`,
before teardown. The provider now rejects any pending stop/replacement state.
The original cache could also certify a later unique frame after duplicate
timestamps had fallen out of its four-slot ring. Timestamp ambiguity now clears
the ring and persists until decoder reset. Both tests fail against the earlier
provider and pass against the corrected rebuild. Negative logs are retained.

The isolated app preparation initially dereferenced auxiliary framework links,
causing signing to reject an unsigned subcomponent. The preparation tool now
preserves auxiliary symlinks and safely restores contained links from rebuilt
framework ZIPs. The accepted build signs and executes successfully.

## Identities and artifacts

The accepted workspace is
`/private/tmp/aagedal-native-raster-20261014/build-v3`. Its provider source commit
is `b59abb68730f4ed804b721ade1a3d13bf6724777`, tree
`84cf4151ea572513bdf2e6ae921a6cc27fb593d0`. The universal Libmpv binary SHA-256 is
`3d08a28d5b48f8f5f1d1efdaa9e803bb87990af5c467f748774b974dbe3b8943`.
The source archive, raw commit object, and consumed patch remain under that
workspace's `decoder-raster-source/`; binaries and source archives are not
committed here. The active patch's blank context lines were normalized after
reconstruction; all five resulting source files match the built provider exactly,
as recorded in `acceptance.json`.

`portable-build.json` retains source/tool/environment/configuration identities.
`runtime-verification.json` retains fixture hashes, compile/link vectors and
case outcomes. `app-candidate.json` binds the isolated source copy and actual
macOS dependency binaries. `acceptance.json` binds the app executable, explicit
test environment, test-run configuration and active source identities. XCTest
summaries and compressed native/action logs are retained alongside these receipts.

The locally signed app is
`/private/tmp/aagedal-native-raster-20261014/app-candidate/DerivedData/Build/Products/Release/Aagedal Media Player.app`.
To exercise native capture, launch its executable with
`AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1`. The opt-in must be set before the player
is created. It applies software decode and disables deinterlacing for this
development process. A stock MPVKit dependency still has no provider.

## Reproduction

Use the published portable source stage and the retained manifest digest with
`scripts/build-mpv-coreaudio-from-stage.py`, adding
`--decoder-raster-candidate`. Supply the installed Metal toolchain and explicit
pkg-config/header directories as in `portable-build.json`. Reconstruction checks
the published source commit/tree instead of requiring unavailable upstream history.

Then run:

```sh
python3 scripts/validate-mpv-decoder-raster-runtime.py BUILD NEW_RUNTIME_OUTPUT
python3 scripts/prepare-mpv-decoder-raster-app-candidate.py \
  APP_REPOSITORY VERIFIED_PACKAGE_CACHE BUILD NEW_APP_OUTPUT
```

The preparation command copies the app and creates local binary targets for all
29 dependencies, replacing the eight GPL mpv/FFmpeg frameworks with the rebuild.
Use a separate package cache for the copied project's Sparkle and metadata
dependencies. Build for testing, then set the generated test-run target's
`EnvironmentVariables` to `AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1` and
`MPV_DECODER_RASTER_FIXTURE=NEW_RUNTIME_OUTPUT/numbered-grid.mkv`. Run only
`LoupeTrackDecoderTests/testMPVNativeRasterOptInUsesCurrentDecoderFrameAndRevokesOnResume`
and require the native acceptance marker in the XCTest action log.

## Remaining scope

Native certification remains limited to paused software frames with square
pixels, no transforms/filters/crop, and the existing 4096-axis/4,194,304-pixel and
16-MiB retained-image limits. Normal UHD rasters exceed this pixel limit.
Ring eviction returns unavailable. High-depth/HDR color, hardware transfer,
rotation/reflection, larger rasters, broad readahead/presentation workloads,
sanitizer ownership testing, long memory profiling, Intel hardware, dependency
publication and ordinary fresh remote resolution remain open. The 50 small-grid
cycles exercise cleanup but do not prove the absence of leaks under sustained
production-resolution workloads.
