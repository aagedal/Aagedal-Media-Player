# 2.0 dependency publication and repin handoff

Publication continuation, 2026-10-02: SwiftMediaMetadata 3.0.2 is public at
`9e8e912deb8d941da66a4b76854a90e3e9f01e3f`; the GPL CoreAudio dependency
prerelease is public at `1d44b9a0aa9e8faa5b8bf222173f6cc2930ed233` and tag
`aagedal-2.0.0-coreaudio-20260930`. The app worktree now requires that exact
MPVKit revision and exact SwiftMediaMetadata version. A fresh remote package
resolution succeeds with Sparkle unchanged. The portable offline CoreAudio
rebuild passes both architectures and every qualified boolean configuration
digest. All 49 declared binary/input URL downloads and the corrected metadata-free
source stage now pass fresh remote hash/inventory verification. Canonical app
acceptance is being retried after generating this worktree's missing fixtures. See [publication receipts](evidence/dependency-publication-20261002/README.md).

The preparation record below is retained as historical context. Its local-only,
unpublished and old-shipping-pin statements describe the earlier handoff,
not the publication continuation above.

## Historical preparation record

Prepared 2026-10-02. Both corrections remain local candidates. This handoff
records retained inputs, local upstream preparation and the next acceptance
steps; it adds no CoreAudio rebuild, publication, fresh-resolution or runtime
acceptance claim.

## Current shipping identities and retained payloads

The app currently resolves MPVKit `230c3174f1515898f24599147ad61c2a277d0dc2`
from `https://github.com/aagedal/MPVKit` and SwiftMediaMetadata 3.0.1
`8662054299a3e13c49c65f74c564360559d1bf7f` from
`https://github.com/aagedal/SwiftMediaMetadata`. The Xcode project selects
`MPVKit-GPL`, tracks MPVKit `main`, and permits SwiftMediaMetadata versions
from 3.0.1. Repinning must change the project requirement and resolved revision
together, using an immutable revision or version.

| Input | Local location and identity |
| --- | --- |
| Feature-qualified CoreAudio build | `/private/tmp/aagedal-coreaudio-gpl-metal-build-v2-20260930`; recipe revision `42cf977668f4b20f7423993d3eea9232077481d5`; [build receipt](evidence/coreaudio-gpl-metal-20260930/build-receipt.json) |
| Publication stage | `/private/tmp/aagedal-coreaudio-publication-prepared-20260930`; [manifest](evidence/coreaudio-publication-preparation-20260930/publication.json) SHA-256 `3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c` |
| Offline reconstruction | `/private/tmp/aagedal-coreaudio-reconstructed-v2-20260930`; additional attributes-isolated workspace `/private/tmp/aagedal-coreaudio-reconstructed-attributes-isolated-20260930` |
| Bounded MXF patch | [portable six-file patch](evidence/bounded-mxf-candidate-20260930/swift-media-metadata-bounded-mxf.patch), SHA-256 `5da87e3d3dd7e40f93ae25cf0b57528c02684f59a6552244898875f1bbbed883`, against SwiftMediaMetadata revision `8662054299a3e13c49c65f74c564360559d1bf7f` |
| Historical bounded MXF working candidate | `/private/tmp/aagedal-bounded-mxf-candidate-20260930`; HEAD remains the unpatched base revision, with the correction and temporary probe changes local |
| Normal upstream package preparation | Local commit `8297324bb00ad1358b4070575c1ea59e698d3f2f` on `codex/bounded-mxf-reader` at `/private/tmp/aagedal-bounded-mxf-upstream-preparation-20261002/SwiftMediaMetadata`; portable patch only, original manifest/Benchmark/lockfile preserved; [source/test receipt and standalone bundle](evidence/bounded-mxf-upstream-preparation-20261002/README.md) |
| Historical app/reimport products | `/private/tmp/aagedal-metadata-reimport-dd-20260930`; result bundles `/private/tmp/aagedal-metadata-reimport-artifacts-20260930/runs/input-{0,1,2}/Profile.xcresult`; independent package cache `/private/tmp/aagedal-metadata-reimport-packages-20260930` |

Read-only inspection on 2026-10-02 found those directories present, the staged
manifest digest unchanged, all 46 declared stage files present with their
recorded sizes, the patch digest unchanged, and all six bounded-MXF candidate
source hashes matching [source-identities.json](evidence/bounded-mxf-candidate-20260930/source-identities.json).
This inspection did not rehash every large payload or rerun historical profiles.
Temporary storage is the sole retained location for the large CoreAudio
payloads; copy and independently verify them before cleanup or host migration.
The bounded-MXF source commit now has a verified standalone bundle retained
in this repository; it restores the exact commit independently of that checkout.

## CoreAudio: local work that can proceed before publication

Run these commands from the app repository. Verification reads retained inputs;
reconstruction writes only a new workspace. Choose a new output path if the
example already exists. Keep the manifest digest outside the copied stage.

```bash
python3 scripts/prepare-mpv-coreaudio-publication.py \
  --verify /private/tmp/aagedal-coreaudio-publication-prepared-20260930
python3 scripts/verify-mpv-coreaudio-reconstruction.py \
  /private/tmp/aagedal-coreaudio-publication-prepared-20260930 \
  /private/tmp/aagedal-coreaudio-reconstructed-v2-20260930 \
  --expected-publication-sha256 3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c
python3 scripts/prepare-mpv-coreaudio-publication.py \
  --reconstruct /private/tmp/aagedal-coreaudio-publication-prepared-20260930 \
  --reconstruction-output /private/tmp/aagedal-coreaudio-reconstruction-handoff-20261002 \
  --expected-publication-sha256 3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c
python3 scripts/test-mpv-coreaudio-publication.py
python3 scripts/test-mpv-coreaudio-reconstruction.py
python3 scripts/test-mpv-coreaudio-clean-candidate.py
```

The stage contains eight GPL framework ZIPs under `assets/`, twenty exact
auxiliary build-input ZIPs under `inputs/`, and three source archives/raw commit
objects under `sources/`. Its package exposes macOS 12+, one `MPVKit-GPL`
product, 31 targets including 29 binary targets, and the existing disabled-Lua policy. The app
continues to require macOS 15+ and arm64. Twenty-one auxiliary binary targets
still refer to upstream URLs: their payloads are distinct from the twenty
retained build-input ZIPs. Both sets need remote authentication.

The exact patched source revisions are mpv
`50fd4f2fb9e4bed909cef5c9648a1bd33aaef72f` and FFmpeg
`c7aba78212570ed0bd693a441d917d86f2744ad6`. Preserve the attributed IINA patch,
the tvOS header adaptation, FFmpeg Metal adjustment, original receipt and
retained builder. See [publication preparation](evidence/coreaudio-publication-preparation-20260930/README.md),
[offline reconstruction](evidence/coreaudio-offline-reconstruction-20260930/README.md)
and the later [exact inventory checks](evidence/coreaudio-stage-inventory-20261001/README.md).

Before executing `candidateBuildCommand` from a reconstruction receipt, complete
a portable public build driver: select/probe Metal on the current host, record
recipe path relocation, remove local-cache assumptions, control network/tool
installation fallbacks and optional feature autodetection, and declare tools,
SDK and external headers. Original Swift/Python/Git/pkg-config/nasm/SDL2
identities, complete SDK/header hashes and inherited environment were not
recorded; do not fill them in retrospectively. Capture the new environment and
fresh build/configuration/object receipts, then verify GPL/Metal/Samba and both
binary architectures. Source reconstruction alone does not establish compilation
or byte-identical builds.

## Bounded MXF: prepare a publishable upstream change

Use a fresh SwiftMediaMetadata checkout at the exact base revision. Apply the
portable patch, preserving the normal upstream manifest, CLI, Benchmark and
lockfile. The retained working candidate additionally modifies `Package.swift`
and `Sources/Benchmark/main.swift` and deletes `Package.resolved`; those were
temporary workarounds/probes and are excluded from the portable correction.

```bash
git -C /path/to/fresh/SwiftMediaMetadata checkout --detach \
  8662054299a3e13c49c65f74c564360559d1bf7f
git -C /path/to/fresh/SwiftMediaMetadata apply --check \
  /Users/truls.aagedal/Developer/Aagedal-Media-Player/docs/evidence/bounded-mxf-candidate-20260930/swift-media-metadata-bounded-mxf.patch
git -C /path/to/fresh/SwiftMediaMetadata apply \
  /Users/truls.aagedal/Developer/Aagedal-Media-Player/docs/evidence/bounded-mxf-candidate-20260930/swift-media-metadata-bounded-mxf.patch
git -C /path/to/fresh/SwiftMediaMetadata diff --check
swift test --package-path /path/to/fresh/SwiftMediaMetadata \
  --scratch-path /private/tmp/aagedal-bounded-mxf-upstream-tests-20261002
```

The 2026-10-02 fresh preparation resolves the pinned ArgumentParser 1.7.1 from
a separate cloned valid Git cache, preserving all upstream targets. Its normal
library suite passes 1,674 tests with 21 opt-in skips; the opted-in CLI suite
passes all 50 tests without skips. Before/after source hashes match. The earlier
broken-alternate checkout and stripped-manifest candidate were not reused.
Exact commands and cache/input identities are retained in the new receipt;
this offline check does not authenticate remote payloads. The CLI harness uses
its existing `SWIFT_EXIF_CLI_BINARY` override for the isolated scratch path.
The local source commit is prepared; no released version or published immutable
revision exists yet. Prepare version/release material and run
checks on that final tree before a release commit/tag. Review the FX6
positional-read syscall cost, then repeat
authentic exporter parity, app-model/cache parity and repeated imports against
the released package. [Library candidate](evidence/bounded-mxf-candidate-20260930/README.md),
[production integration](evidence/bounded-mxf-app-production-20260930/README.md)
and [reimports](evidence/bounded-mxf-reimports-20260930/README.md) distinguish
their measured improvements from uncompleted acceptance.

## Ordered publication and shipping acceptance

1. Finish the portable CoreAudio reconstruction/build environment and bounded-MXF
   final-version release checks. The normal local upstream library/CLI checks
   now pass as recorded above. Review final immutable package revisions,
   release names, platform/license policy and reproduction target. The staged
   CoreAudio URL namespace
   `https://github.com/aagedal/MPVKit/releases/download/aagedal-2.0.0-coreaudio-20260930`
   is a proposal, not evidence that a release exists. If it changes, prepare a
   new stage with `prepare-mpv-coreaudio-publication.py BUILD NEW_STAGE
   --release-base-url FINAL_URL`; preserve the historical stage.
2. Publish durable source/input/recipe/driver/environment material and the exact
   eight assets named `Libmpv-GPL`, `Libavcodec-GPL`, `Libavdevice-GPL`,
   `Libavfilter-GPL`, `Libavformat-GPL`, `Libavutil-GPL`, `Libswresample-GPL` and
   `Libswscale-GPL`, each ending `.xcframework.zip`. Preserve stage-relative
   paths when packaging the complete 46-file stage; its manifest cannot verify
   a flattened collection. Commit the prepared package wrapper/manifest to the
   published MPVKit revision, and publish the bounded-MXF upstream revision.
   Remote publication requires a chosen final commit/tag and authorization.
3. Download every final asset into a fresh directory and verify hashes/sizes
   against the externally retained manifests. Authenticate all 29 declared
   binary-target URLs and twenty auxiliary build-input URLs; record redirects
   and returned identities. Do not mark adjacent local checksums as remote
   authentication. Resolve each package normally from an empty SwiftPM cache.
4. Change the app's package requirements and `Package.resolved` to the final
   immutable revisions, retaining `MPVKit-GPL`. Use entirely new DerivedData.
   Copying historical Xcode build databases can affect their absolute output
   paths; the previous restoration incident remains documented in the
   production-MXF evidence. A package cache is separate from a build database.
5. Commit the integration, then run the canonical clean candidate verifier:
   `scripts/verify-release-candidate.sh /private/tmp/aagedal-repinned-candidate-NEW_ID`.
   If an offline package cache is used, set `AAGEDAL_CANDIDATE_PACKAGE_CACHE` to
   a newly resolved `SourcePackages` directory; the verifier checks every
   checkout against the new committed pins. Historical local relinking is not
   shipping integration evidence.
6. Run fresh production metadata and live-meter profiles with the repinned app,
   retaining unchanged validators, exact sources/sidecars, actual linked binary
   identities, resource observations and EOF/cancellation evidence. Complete
   audible output, device switching, surround hardware, supported macOS,
   sustained soak and base-M1/8-GB acceptance. Universal dependency slices do
   not imply x86_64 app support or x86_64 runtime acceptance.

The three original production metadata inputs are present locally:

- `/Users/truls.aagedal/Movies/TestVideo/testmappe_agedal_media_stitch/M4ROOT/CLIP/rre_8073.MP4`
- `/Users/truls.aagedal/Movies/TestVideo/Sony A1 Card/M4ROOT/CLIP/20260502_TRA_MOV_0240.MP4`
- `/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF`

Use `scripts/profile-production-metadata-memory.sh NEW_OUTPUT MEDIA...` with a
new `METADATA_MEMORY_PROFILE_DERIVED_DATA`. For the retained reimport scope,
set `METADATA_MEMORY_PROFILE_REIMPORT_COUNT=30`,
`METADATA_MEMORY_PROFILE_MAX_RESIDENT_GROWTH_MIB=32` and
`METADATA_MEMORY_PROFILE_MAX_DESCRIPTOR_GROWTH=4`. These are the historical
diagnostic budgets, not universal RSS limits. Use
`scripts/profile-live-audio-meter.sh NEW_OUTPUT --audio-stream-order 0 FX6
--audio-stream-order 7 FX6` with a new
`LIVE_AUDIO_METER_PROFILE_DERIVED_DATA`, then representative stereo/surround
inputs and sustained observations. Real-volume and multi-hour MXF scaling,
same-size concurrent changes and release-floor performance remain separate
acceptance inputs; directory aliases do not exercise external-volume I/O.
