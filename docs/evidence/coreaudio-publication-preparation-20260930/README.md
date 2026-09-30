# Local immutable GPL publication preparation — 2026-09-30

The feature-qualified [fresh GPL/Metal build](../coreaudio-gpl-metal-20260930/README.md)
now has a concrete staged macOS-only GPL package and source/input release payload.
The stage remains **unpublished** at
`/private/tmp/aagedal-coreaudio-publication-prepared-20260930`. The proposed
`aagedal-2.0.0-coreaudio-20260930` asset namespace is a local preparation choice;
it does not assert that a release/tag exists or authorize publication. The app
still resolves `230c3174f1515898f24599147ad61c2a277d0dc2`.

The retained [publication manifest](publication.json) binds 46 staged files:
eight unchanged ZIPs renamed to GPL release asset names, twenty exact auxiliary
build-input ZIPs, three deterministic compressed committed source archives,
three raw Git commit objects, the GPL package manifest/wrapper sources/license,
the original build receipt/builder, the actual preparer snapshot, the attributed
IINA patch, and the explicit FFmpeg Metal source patch. The source archives retain
the adapted CoreAudio patch and original recipe license material. Large payloads
remain local; this evidence directory retains their identities and small review
artifacts, not another copy of the binaries or source archives.

The [package manifest](Package.swift) advertises only macOS 12 and the
`MPVKit-GPL` product. It declares all eight freshly rebuilt GPL binary targets
and all 21 auxiliary binary targets required by that product, preserving
upstream auxiliary release URLs/checksums and linker settings. Lua remains
disabled in the product; the recipe's LuaJIT ZIP is retained as a build-only
input because the upstream build enumerates it. Stale cached versions are
excluded from the exact twenty-input publication manifest.

Preparation independently rechecks the actual retained builder, immutable
recipe/source trees, all artifact bytes/sizes, universal binary slices, fresh
object/configuration identities and shipping GPL/Metal/Samba feature gates.
Stage verification reconstructs each archive's Git tree directly from its file
bytes, verifies the raw commit object's revision and tree, binds them back to
the retained build receipt, and reads input URLs from the committed recipe.
It binds package wrapper files/license and the retained auxiliary target
declarations to that same archive. Replacing an artifact plus its adjacent
checksum/metadata cannot replace the original build identity. Inventory,
symlink, GPL/platform/Lua policy, pending status/blockers and false remote
authentication claims also fail closed.

[Eleven regressions](regression-tests.log) pass. Native `swift package
dump-package` with isolated caches compiles the manifest successfully; the
[native validation](swift-package-validation.json) checks its single GPL
product, macOS minimum, all 31 targets, declared binary URLs/checksums and every
dependency reference. This validates manifest structure, not downloads,
artifact resolution, linking or playback. [Independent stage verification](verification.json)
and [repeat staging comparison](repeat-staging-comparison.json) retain the
actual results. Repeated source-archive preparation preserves their bytes;
this is not a second MPV/FFmpeg build or proof of byte-identical builds.

## Repeatable local commands

Choose a new output directory and a proposed immutable release tag URL. The
preparer rejects existing output directories and mutable tag names such as
`latest` or `main`; it performs no upload and changes neither the dependency
checkout nor the app's shipping pin.

```bash
python3 scripts/prepare-mpv-coreaudio-publication.py \
  /private/tmp/aagedal-coreaudio-gpl-metal-build-v2-20260930 \
  /tmp/new-coreaudio-publication \
  --release-base-url https://github.com/aagedal/MPVKit/releases/download/aagedal-2.0.0-coreaudio-20260930
python3 scripts/prepare-mpv-coreaudio-publication.py --verify /tmp/new-coreaudio-publication
python3 scripts/test-mpv-coreaudio-publication.py

CLANG_MODULE_CACHE_PATH=/tmp/coreaudio-manifest-clang-cache \
SWIFT_MODULECACHE_PATH=/tmp/coreaudio-manifest-swift-module-cache \
swift package --package-path /tmp/new-coreaudio-publication/package \
  --cache-path /tmp/coreaudio-manifest-cache \
  --config-path /tmp/coreaudio-manifest-config \
  --security-path /tmp/coreaudio-manifest-security \
  --scratch-path /tmp/coreaudio-manifest-build \
  --disable-sandbox dump-package
```

The release stage's `publication.json` is a checksum manifest, not a signature.
Preserve its externally retained SHA-256 when moving/reviewing the stage.
Verification detects changes against the retained manifest/build identities;
it does not authenticate an attacker replacing the entire evidence chain.

## Work still required before a shipping repin

The proposed source/artifact URLs are not public, and auxiliary remote assets
have not been downloaded/authenticated by this preparation. The retained exact
input ZIPs avoid losing the local build inputs, but a fresh host still needs a
public reconstruction driver, declared tool/SDK/header/environment identities,
portable Metal selection and controlled feature autodetection. The retained
recipe includes host paths and local-cache assumptions. Deterministic source
archives do not resolve varying build paths/timestamps or demonstrate
byte-identical rebuilt libraries.

Publish durable source/input/recipe material and the exact artifacts only after
reviewing the pending policy, then verify downloads/checksums and ordinary
SwiftPM resolution from a fresh cache. Use an immutable package revision/version
and run the app's package-cache gate, clean Release build/tests and production
profiles against that published package before changing the shipping pin.
Audible output, device switching, surround hardware, x86_64 runtime, supported
macOS, sustained soak and base-M1/8-GB release-floor acceptance remain open.
