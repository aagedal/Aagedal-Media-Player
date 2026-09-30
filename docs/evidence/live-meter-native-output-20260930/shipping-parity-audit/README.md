# Shipping dependency parity audit — 2026-09-30

The previous complete local dependency candidate is **not feature-equivalent to
the shipping MPVKit-GPL product**. Its immutable artifact identities and local
production playback observations remain valid diagnostic evidence. They do not
qualify that candidate for a shipping repin, or establish the cause/resolution
of the intermittent FX6 near-EOF synchronization failure.

The app selects `MPVKit-GPL` in `project.pbxproj`. The historical clean builder's
recorded Swift command omitted `enable-gpl`, selecting the upstream recipe's
non-GPL configuration. Full boolean macro comparisons against the retained
pinned cached GPL build show the same differences on arm64 and x86_64:

| Configuration | Retained GPL baseline | Historical clean candidate |
| --- | ---: | ---: |
| mpv `HAVE_GPL` | 1 | 0 |
| FFmpeg `CONFIG_GPL`, `CONFIG_GPLV3` | 1 | 0 |
| FFmpeg `CONFIG_LGPLV3` | 0 | 1 |
| FFmpeg `CONFIG_LIBSMBCLIENT`, its protocol | 1 | 0 |
| FFmpeg `CONFIG_DELOGO_FILTER` | 1 | 0 |
| Eight GPL ADPCM decoders, AHX parser and BSF | 1 | 0 |
| FFmpeg `CONFIG_METAL` | 1 | 0 |

The decoder list is ADPCM Circus, IMA Escape, IMA HVQM2, IMA HVQM4, IMA Magix,
IMA PDA, N64 and PSXC. [audit-receipt.json](audit-receipt.json) records every
changed macro, original/candidate header hashes and paths for both architectures.
These comparisons use the retained pinned cached build's generated headers;
they do not claim remote authentication of every original binary. There are no
other mpv boolean feature differences beyond GPL. Metal here refers to FFmpeg's
configuration: VideoToolbox and the mpv MoltenVK/video backends remain enabled.

## Corrected builder and external prerequisite

The repository builder now explicitly requests `enable-gpl`, records the
`MPVKit-GPL` product, and verifies Samba's required macOS architecture payloads.
It also requires a working Metal compiler **before creating a new output
directory**. A corrected fresh build attempt exits 1 with this concrete error:

```text
MPVKit-GPL requires a working Metal compiler to preserve CONFIG_METAL=1.
xcrun --sdk macosx metal -v failed:
cannot execute tool 'metal' due to missing Metal Toolchain;
use: xcodebuild -downloadComponent MetalToolchain
```

The native host probe fails identically, establishing that this prerequisite is
missing outside the sandbox too. The shown `xcodebuild` download command comes
directly from the locally executed Xcode tool; it was **not run**. Cached Samba
inputs include both architectures. No fresh GPL artifact was built, no output
directory was created and no tools were installed/downloaded.
[gpl-preflight.log](gpl-preflight.log) retains the attempted corrected build.

After this prerequisite is restored, rerun the builder into a new directory.
The independent completion verifier requires GPL/Metal/Samba, the relevant
decoder/filter features and the existing CoreAudio/video backends on **both**
architectures. It records complete boolean-configuration hashes plus header
hashes and required-feature values. Missing macros fail rather than being
treated as zero or unavailable.

Default `--verify` now always requires shipping feature parity, including old
receipts that have no `shippingProduct` field. An actual historical-candidate
verification exits 1; [its log](historical-shipping-verification.log) retains all
rejections. Explicit `--diagnose-historical` records artifact identity provenance
and failed parity into a **separate** diagnostic file. The
[historical diagnostic](historical-parity-diagnostic.json) shows the mismatch;
the old build, verification receipts, source commits and native profile evidence
were preserved.

Thirteen builder regressions pass. The added cases reject lost license/backend/
decoder/Metal features on either architecture, missing feature macros, a missing
Metal prerequisite before cloning/output creation, and a legacy receipt passing
default verification. Explicit historical diagnosis still exposes failed parity.

Artifact verification now binds every actual ZIP hash/size to the immutable
build receipt, independently of its neighboring checksum file. Replacing both
a ZIP and that checksum is rejected before inspecting the binary. Where the
receipt embeds completion verification, the verifier also binds framework,
fresh-object and generated configuration identities to that recorded snapshot.
The replacement regression and unchanged-artifact recheck pass; historical
receipts were preserved.

## Concrete public recipe and shipping repin work

1. Restore the Xcode Metal compiler, then produce and verify a fresh **GPL**
   artifact. Repeat the authentic production profiles on that exact artifact;
   investigate repeated FX6 near-EOF behavior without inferring a causal repair
   from the previous full-built pass. Actual audible output, device switching,
   supported macOS/hardware, x86_64 runtime coverage, 30-minute soak and the base
   M1/8 GB release-floor checks remain separate acceptance work.
2. Turn the local recipe into a fetchable committed build recipe: use explicit
   source URLs/revisions and an exact auxiliary input URL/checksum manifest.
   The current builder clones local cached repositories, enumerates 30 cached
   ZIPs including unused older versions, and verifies local copy parity. It
   cannot reconstruct those inputs from a fresh machine or authenticate the
   cached ZIPs against upstream release provenance.
3. Preserve the attributed IINA patch and pinned tvOS header adaptation, and
   record the existing FFmpeg Metal pixel-buffer source adjustment as a patch.
   Publish the source/recipe snapshots or commits alongside the artifacts so
   their current `/tmp` retention is no longer their only durable location.
4. Specify the build environment and feature detection. The upstream recipe
   appends host Homebrew pkg-config paths and autodetects tools/features. The
   current receipt records Xcode/Clang/Meson/Ninja versions, but not complete
   SDK/auxiliary-header identities or Swift/Python/nasm/pkg-config/SDL inputs.
   Use a declared environment/input manifest and gate resulting configuration
   identities. The current native-tool differences between architectures
   (programs/SDL/XCB enabled only on the host; x86_64 ASM disabled) are upstream
   recipe choices, not demonstrated missing universal slices. They still need
   explicit publication policy and x86_64 runtime validation.
5. Produce an installable package manifest with the correct **GPL binary target
   names**, complete auxiliary targets, final immutable asset URLs/checksums,
   existing no-Lua product policy and the repository's intended platforms. The
   local generated manifest deliberately skips auxiliary target generation,
   contains unresolved GPL placeholders and advertises unbuilt platforms; it
   cannot be repinned as-is. Decide whether the public release is explicitly
   macOS-only or builds every platform its manifest advertises.
6. Verify publication/download/checksums and ordinary SwiftPM resolution from a
   fresh cache before updating the app's package requirement and
   `Package.resolved`. The current project tracks `main` while its resolved file
   records revision `230c3174...`; use an immutable package revision/version for
   the corrected dependency. Run the existing package-cache gate and normal
   clean Release build/tests/profile path without local relinking substitutions.

Byte-identical rebuilds have not been demonstrated. Local commit timestamps,
absolute source paths embedded in artifacts/configuration, and ZIP timestamps
currently vary across builds. Define whether the public reproducibility target
is identical source/configuration or identical bytes, then fix/compare those
inputs accordingly. None of the current architecture/object-count differences
or native profile memory observations establishes CPU/resource equivalence.
