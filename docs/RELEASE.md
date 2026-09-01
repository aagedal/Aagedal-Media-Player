# Release engineering

Aagedal Media Player releases are intentionally Apple-Silicon-only. The app
target, release archive, MPVKit dependency set, and bundled ffmpeg executable
are built for `arm64`; macOS 15.0 is the minimum supported system. Supporting
Intel would require universal builds of every native dependency and dedicated
playback, signing, and performance validation, so changing this policy is a
release-level decision rather than an `ARCHS` toggle.

## Runtime diagnostics and security

The shared Run scheme keeps Main Thread Checker and Thread Performance Checker
enabled. Metal API Validation is the sole disabled runtime diagnostic because
MoltenVK can render on background threads while Core Animation manages the
same `CAMetalLayer`; validation changes that timing and triggers the known
MoltenVK race documented in `CLAUDE.md`.

The release uses Hardened Runtime and Developer ID signing, with two deliberate
security choices:

- App Sandbox is disabled. Playback and export currently rely on durable access
  to arbitrary dropped/opened media, related sidecar content, sibling output
  locations, and a bundled ffmpeg subprocess. Enabling the sandbox requires a
  full security-scoped URL and child-process workflow audit.
- `com.apple.security.cs.disable-library-validation` permits the MPVKit native
  playback stack and its bundled codec/rendering libraries to load when their
  signatures do not share the app's Team ID.

Reassess both choices whenever MPVKit packaging, file-access ownership, or the
export pipeline changes. Do not add entitlements without updating the preflight
expectation and this rationale.

## Preflight and release

Before release, update the project version/build and add the matching
`CHANGELOG.md` section. Then run:

```bash
python3 scripts/release-preflight.py
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS"
xcodebuild analyze -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS"
```

The preflight is local and deterministic: it does not make network requests.
It verifies project and Sparkle metadata, version/build monotonicity, appcast
ordering, signatures and canonical download URLs, shared-scheme diagnostics,
security settings, and the reviewed ffmpeg architecture/checksum.

Run `scripts/release.sh` only after those checks pass. The release script runs
the preflight again before deleting `build/`, verifies the exported app's
version, architecture, hardened-runtime Developer ID signature, and nested
signatures before notarization, then validates the newly prepended appcast item.

After notarization, retain the usual manual distribution check:

```bash
xcrun stapler validate "build/export/Aagedal Media Player.app"
spctl --assess --type execute --verbose=2 "build/export/Aagedal Media Player.app"
```

## Updating ffmpeg

Treat `checksums/ffmpeg.sha256` as a reviewed provenance record. When
intentionally replacing ffmpeg, confirm that it is a thin arm64 Mach-O
executable, review its origin and capabilities, then update the checksum. The
preflight also requires the audio decoders, Float32 PCM output, and EBU R128
filter used by waveform and LUFS analysis; do not substitute an image-only
build even if screenshot/export smoke tests pass.

```bash
file "Aagedal Media Player/Binaries/ffmpeg"
lipo -archs "Aagedal Media Player/Binaries/ffmpeg"
shasum -a 256 "Aagedal Media Player/Binaries/ffmpeg"
```

The exported app signature check is authoritative for the distributable bundle;
the source checksum detects an unreviewed binary change before archiving.
