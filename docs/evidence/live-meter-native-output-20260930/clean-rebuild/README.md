# Clean local macOS CoreAudio dependency build — 2026-09-30

A fresh isolated build now produces complete macOS mpv and FFmpeg libraries for
arm64 and x86_64. Every mpv and FFmpeg object was compiled in new scratch
directories. No previous object archive, framework, generated header or build
database was copied into those directories. This replaces the earlier
two-object incremental substitution with a complete local dependency build.

The shipping MPVKit pin remains unchanged. This is an unpublished local
candidate; the build itself supplies no actual production playback,
audible-output, device-switch, surround, supported-macOS or release-floor
acceptance. Follow-up app profiles must identify these exact new artifacts.

The subsequent [authentic production profiles](../../live-meter-authentic-sustained-20260930/README.md)
now identify and link all eight artifacts and pass AAC, selected FX6 mono tracks
and a sample-preserving ITU six-channel preparation. Those local observations
retain an earlier incremental-candidate synchronization failure separately.
Shipping repin and the external output/hardware gates remain open.

| Verified output | arm64 fresh objects | x86_64 fresh objects |
| --- | ---: | ---: |
| mpv | 221 | 220 |
| FFmpeg | 1,118 | 984 |

The upstream recipe also builds native command-line tools where the host
architecture supports them, so object counts include those tools. All eight
shipping ZIPs—Libmpv and the seven FFmpeg libraries—have exactly one macOS
XCFramework slice declaring both architectures. Independent `lipo -archs` checks
on the actual binary payload of **each retained ZIP** confirm both architectures;
all ZIP hashes match the generated SwiftPM checksum files.

The new universal Libmpv binary SHA-256 is
`5ebd682bfa0618694570f2f958d68ea143c4b4a1b1b98859a9374870ba4b2fc3`.
Its XCFramework ZIP checksum is
`8d34927c77f90bd8a88ffdaafa6ff8c13405ab2be1e495c183007a4b452a88aa`.
Hashes for every FFmpeg artifact, static architecture archive, CoreAudio object,
compile database and full fresh-object manifest are retained in
[verification.json](verification.json).

## Immutable source and recipe identities

The original MPVKit checkout was read only. Clean local Git clones copied
committed source objects without hard links; existing uncommitted mpv/FFmpeg
source adjustments were discarded in favor of the pinned recipe's patches.

| Source | Upstream revision | Local candidate revision |
| --- | --- | --- |
| MPVKit recipe | `230c3174f1515898f24599147ad61c2a277d0dc2` | `15393a78ace3a30b3f0fec17c787893f5e44bbb9` |
| mpv v0.41.0 | `41f6a645068483470267271e1d09966ca3b9f413` | `2fdb5b54ec99fa3861b5e2bc9181724e659b5882` |
| FFmpeg n8.1.2 | `38b88335f99e76ed89ff3c93f877fdefce736c13` | `f315416f7075aed202db27d4b4a4d24e99617379` |

All three candidate checkouts retain those exact HEADs and source trees with
clean Git status after build. Source-only archives from each candidate commit
are retained under the build's `immutable-source-snapshots` directory; their
identities and build-log hashes are in
[retention-receipt.json](retention-receipt.json). These commits and archives are
local, with no remote release or discoverable package revision.

The pinned upstream MPVKit recipe uses prebuilt auxiliary third-party release
ZIPs. The tool reconstructs their payloads from cached ZIPs and records their
hashes, rather than reusing extracted dependency headers/libraries. Original
and copied ZIP hashes match after build. The retained input inventory includes
cached older versions that the pinned recipe does not consume. These local
identities do not authenticate auxiliary ZIPs against remote release provenance,
and this run does **not** rebuild every auxiliary library from its own source.
SDK/system headers and installed build tools are recorded, not made immutable.

## Patch and build adaptations

The original attributed IINA repair remains SHA-256
`176cdef4eb860cfbffcaf821b186b1e6e7f5f1c1a1c246d728b5c28ef960a2d5`.
The clean source exposed a difference absent from the old build cache: the pinned
MPVKit recipe's tvOS patch adds `TargetConditionals` guards around device HAL
declarations. Applying the original IINA header hunk after that patch fails.
The [applied repair](coreaudio-repair-pinned-recipe.patch) preserves those guards
and ports only the added forward/function declarations. Both IINA C source
hunks apply unchanged. The adapted patch hash is
`af6edfe3af30f21e1281c6ddfc8bdf708bade1870b496ebf17c38a89caf03799`;
original attribution and exact ordered source patch identities remain in
[build-receipt.json](build-receipt.json).

The isolated recipe makes three additional changes: it omits network-only
auxiliary package-manifest generation, propagates isolated module-cache and
temporary-directory paths into subprocesses, and records the upstream FFmpeg
Metal pixel-buffer source adjustment in its source commit before compilation.
It runs the upstream builder for `platform=macos` with Xcode 27.0 (27A266a), the
current macOS SDK, and the recipe's macOS 12 deployment target. Generated
`Package.swift` metadata is incomplete because remote auxiliary entries were
omitted; it is not a replacement shipping package manifest.

The successful build used [actual-builder.py](actual-builder.py), matching its
receipt's builder hash. The repository builder subsequently gained independent
verification and seven safety regressions. The retained separate verification
receipt identifies that verifier without rewriting the successful build's
recipe or historical builder identity.

```bash
python3 scripts/build-mpv-coreaudio-clean-candidate.py \
  /Users/truls.aagedal/Developer/MPVKit /tmp/new-clean-coreaudio-candidate
python3 scripts/build-mpv-coreaudio-clean-candidate.py \
  --verify /tmp/aagedal-coreaudio-clean-build-v4-20260930
python3 scripts/test-mpv-coreaudio-clean-candidate.py
```

The seven regressions reject ZIP path traversal, symlink redirection, changed
source revisions/trees/status, copied ZIP identity mismatches, and binaries
missing an architecture despite universal plist declarations; they also check a
valid payload round trip and reject mismatched source before cloning. They are
included in `test-script-validators.sh`. The actual full build and independent
verification pass separately.

## Retained attempts and remaining integration

The first clean attempt stopped at the IINA/tvOS header-context mismatch.
The second stopped because nested SwiftPM `sandbox-exec` could not apply its
sandbox. The standard `--disable-sandbox` SwiftPM option resolved that while the
outer filesystem sandbox remained enforced. The third reached FFmpeg configure,
where the upstream subprocess environment's missing `TMPDIR` denied Clang
temporary-file creation and surfaced as a misleading assembler error. The
fourth fresh attempt completed after explicit isolated temporary-directory
propagation. No tool installation, original-checkout mutation, app package
repin or remote publication was used to resolve these failures.

The full candidate, original logs and source snapshots remain at
`/tmp/aagedal-coreaudio-clean-build-v4-20260930`. All eight ZIPs are in
`MPVKit/dist/release`; the universal app-link frameworks remain in
`MPVKit/dist/libmpv/macos` and `MPVKit/dist/FFmpeg/macos`. Upstream removes earlier
expanded XCFramework directories when it packages the next library, which is
why verification reads each final ZIP directly.

Remote publication with a final checksum/immutable package revision, shipping
repin and the remaining hardware/output release checks are still open. The
subsequent production profiles supply their own exact-artifact playback evidence;
earlier incremental candidate profiles cannot transfer to it by inference.
