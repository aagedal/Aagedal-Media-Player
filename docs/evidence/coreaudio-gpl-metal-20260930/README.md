# Fresh feature-qualified GPL/Metal CoreAudio candidate — 2026-09-30

A fresh isolated macOS build now preserves the required MPVKit-GPL license,
codec/filter, Samba, video/backend and FFmpeg Metal configuration on both
arm64 and x86_64. All eight actual universal framework binaries, original ZIP
hashes/sizes, source trees, compiled object/configuration identities and builder
snapshot pass independent verification. The original dependency checkout is
unchanged. This is an unpublished local candidate; the shipping app pin remains
`230c3174f1515898f24599147ad61c2a277d0dc2`.

| Fresh objects | arm64 | x86_64 |
| --- | ---: | ---: |
| mpv | 221 | 220 |
| FFmpeg | 1,122 | 988 |

[The build receipt](build-receipt.json), [independent verification](independent-verification.json)
and [actual builder snapshot](actual-builder.py) identify the exact configuration
and sources. The recipe commit is `42cf977668f4b20f7423993d3eea9232077481d5`;
all eight artifact checksums are retained. The local build and artifact payloads
remain at `/private/tmp/aagedal-coreaudio-gpl-metal-build-v2-20260930`.
Auxiliary third-party ZIPs remain the upstream prebuilt inputs; this does not
rebuild or remotely authenticate every dependency.

## Working Metal compiler and explicit build selection

`xcodebuild -downloadComponent MetalToolchain -exportPath` exported the matching
27A266a component, and import reported that it was already installed. Xcode's
component inventory reports installed, but ordinary `xcrun ... metal -v` still
reports missing toolchain. Running the installed compiler directly works.
No component was deleted, system preferences changed or Xcode installation replaced.

The builder now accepts an explicit `--metal-toolchain` root, verifies executable
compiler/linker paths, compiles a real Metal kernel and links its metallib before
allocating a candidate. [The prerequisite receipt](metal-prerequisite.json)
binds launcher and underlying compiler/linker payload hashes plus symlink targets.
The pinned FFmpeg recipe receives those exact `--metalcc`/`--metallib` paths.
Unsupported command paths fail early. Both final slices still must pass the
existing feature gates; the explicit compiler does not waive them.

```bash
python3 scripts/build-mpv-coreaudio-clean-candidate.py \
  /Users/truls.aagedal/Developer/MPVKit /tmp/new-coreaudio-gpl-candidate \
  --metal-toolchain /private/var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v27.1.266.1.jWL5ac/Metal.xctoolchain
python3 scripts/build-mpv-coreaudio-clean-candidate.py --verify /tmp/new-coreaudio-gpl-candidate
```

The mounted toolchain path is host/session-specific. Use the installed component
inventory to identify it on another run; these local paths are not a public
reconstruction recipe. Eighteen builder regressions pass, including absent
linker/output rejection, command-path safety, changed implementation/target
rejection, and retained builder identity after live source edits.

## Rejected first attempt and corrected provenance

The first fresh build passed its local artifact/configuration checks, but
independent verification rejected its builder snapshot identity. The running
builder copied its source early, then later hashed the live repository file,
which the root edited while the build ran. Its original receipt and retained
snapshot therefore name different hashes. [The rejected receipt](rejected-first-build-receipt.json),
[identity comparison](rejected-first-builder-identity.json) and verification
failure are preserved unchanged. That candidate is diagnostic and was not used
for the new native acceptance profiles.

The builder now captures and verifies the copied snapshot identity immediately
and uses it throughout receipt creation. A new empty directory rebuild with
that stable source succeeds, followed by independent verification. The first
receipt was not rewritten to hide the mismatch.

## Native profiles and remaining release work

[Three authentic production profiles](../live-meter-gpl-metal-native-20260930/README.md)
pass on a separately linked current Release app using every new framework:
GoPro AAC stereo and FX6 PCM24 mono ordinals zero/seven. All six observation/EOF
starts initialize CoreAudio with two output channels, and unchanged validation
passes selected tracks, source-preserving monitor routing, pause/resume,
cancellation and timestamp-authoritative EOF. No native output-init/channel-map
errors occur. This exercises arm64 native initialization; it is not audible
output, device-switch, surround hardware or x86_64 runtime acceptance.

Immutable public source/input/recipe and installable GPL package/artifact
publication, fresh SwiftPM resolution, shipping repin, sustained supported-macOS
and base-M1/hardware acceptance remain open. Byte-identical rebuilds and complete
remote auxiliary provenance have not been demonstrated. See the remaining
[public recipe and package requirements](../live-meter-native-output-20260930/shipping-parity-audit/README.md).
