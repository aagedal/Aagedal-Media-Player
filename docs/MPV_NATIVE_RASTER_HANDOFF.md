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

App changes and rerunning these fixtures do **not** require a dependency rebuild.
Changing the provider C patch, FFmpeg configuration, or MPVKit internals does:
use the retained source archives and arm64-only reconstruction workflow, then
publish a new uniquely named artifact with new checksums and validation evidence.
Do not overwrite this candidate asset or reuse its acceptance receipts for new
provider code. The bundle retains the original source-stage archive and the
modified mpv source archive/commit/patch under `sources/`, plus the MPVKit license
and upstream README. Qualified auxiliary source/license provenance remains the
published GPL MPVKit release referenced by the retained source stage.
