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

Review all release plans before selecting a candidate:

- [`IMPROVEMENT_PLAN.md`](../IMPROVEMENT_PLAN.md) and
  [`FOLLOW_UP_IMPROVEMENT_PLAN.md`](../FOLLOW_UP_IMPROVEMENT_PLAN.md) track the
  completed reliability work. Re-run their regression and static-analysis
  checks against the candidate; historical passes are not release evidence.
- [`PRODUCT_ROADMAP.md`](../PRODUCT_ROADMAP.md) tracks remaining product and
  release gates, including representative-media smoke checks and the beta.
- [`COMPARE_MODE_IMPLEMENTATION_PLAN.md`](../COMPARE_MODE_IMPLEMENTATION_PLAN.md)
  tracks Compare Mode acceptance. Feature checkboxes do not replace the
  base-M1 performance gate, hands-on visual checks, editor round trips, or demo.
  Use the [performance run sheet](COMPARE_MODE_PERFORMANCE.md),
  [marker interchange run sheet](COMPARE_MODE_INTERCHANGE.md), and
  [demo run sheet](COMPARE_MODE_DEMO.md) to retain that evidence.

Before release, update the project version/build and add the matching
`CHANGELOG.md` section. Commit those changes, then run the canonical optimized
candidate verification from a clean checkout, choosing a new output directory:

```bash
scripts/verify-release-candidate.sh /tmp/aagedal-candidate-VERSION-BUILD
```

The verifier records the exact commit, `Package.resolved` hash, host and Xcode
version; first runs the self-contained script-validator tests and shell/Python
syntax checks; runs the test suite and static analysis in Release with
dependencies restricted to the resolved file; enables testability for the
optimized test bundle; retains the `.xcresult` and complete logs; and runs
source preflight. It exports machine-readable XCTest evidence, rejects runtime
warnings, expected failures, a drop below the recorded test-count floor, and
any skip outside the named optional-input allowlist. Script checks are retained
in `script-validator-tests.log`. The verifier also fails if HEAD, the resolved
package hash, or checkout cleanliness changes during the run; write its output
outside the source checkout. Because the two mixed-backend transport tests have
shown order-sensitive behavior late in their long-lived hosted test class, the
verifier excludes them from the aggregate result and runs them together in a
fresh serial runner. It validates both result bundles, covering all 685 tests
without treating test-host resource accumulation as a playback acceptance
signal.
The destructive disk-image check, external-reference checks, fixture generation,
and production profilers—including representative live-audio-meter acceptance—
remain explicit opt-ins rather than ordinary candidate verifier work.
Opt-in reference, performance, and destructive-filesystem tests report named
skips unless their documented harness supplies the required inputs. A passing
ordinary suite therefore does not claim those acceptance gates ran.

The preflight is local and deterministic: it does not make network requests.
It verifies project and Sparkle metadata, version/build monotonicity, appcast
ordering, signatures and canonical download URLs, shared-scheme diagnostics,
security settings, and the reviewed ffmpeg architecture/checksum.

Strict signature verification is the prerequisite for interpreting signer,
Hardened Runtime and timestamp details. When that check fails, the preflight
reports the authoritative verification error and suppresses derivative claims
about fields that `codesign` may mark unavailable. Reproduce the check in a
normal Terminal and inspect the available signing identities before replacing
or re-signing the reviewed binary:

```bash
security find-identity -v -p codesigning
codesign --verify --strict --verbose=4 "Aagedal Media Player/Binaries/ffmpeg"
```

A restricted automation sandbox can prevent `codesign` from reaching the normal
macOS trust services and report `invalid signature` for an unchanged valid
artifact. If sandboxed and normal-Terminal results disagree, first confirm the
tracked checksum, then require the normal-Terminal strict verification and full
preflight to pass. Do not bypass or weaken the signature checks.

Run `scripts/release.sh` only after those checks pass, pointing it at that exact
evidence directory:

```bash
CANDIDATE_EVIDENCE_DIR=/tmp/aagedal-candidate-VERSION-BUILD scripts/release.sh
```

The release script refuses a dirty checkout, requires the version/build to
match the committed Xcode project metadata, revalidates the candidate's XCTest
summary and skip details, and requires its source commit and `Package.resolved`
hash to match the checkout. It resolves and prints the full source commit before
invoking the toolchain and uses that exact commit as a newly created GitHub release's target.
It runs the preflight again before deleting `build/`, verifies the exported
app's version, architecture, hardened-runtime Developer ID signature, and nested
signatures before notarization. The archive is restricted to the revisions in
the tracked `Package.resolved`; it cannot silently resolve a newer branch head.
After creating the distribution ZIP, it extracts
that exact artifact into `build/distribution-check`, repeats the app preflight,
validates the stapled ticket, and requires Gatekeeper acceptance before signing
the update or changing the appcast. It then validates the newly prepended appcast
item. Publication requires an authenticated GitHub CLI and then verifies that
the release tag resolves to the exact source commit, the release is neither a
draft nor a prerelease, and the expected ZIP asset's uploaded state, byte size,
and GitHub-computed SHA-256 match the local distribution before changing the
tracked appcast. If automated Homebrew publication is configured, its checkout
and cask path are validated before archive work and checked again before a
single exact version/SHA rewrite; unrelated or ambiguous cask content fails
closed.

To reproduce the packaged-artifact checks manually after notarization:

```bash
xcrun stapler validate "build/distribution-check/Aagedal Media Player.app"
spctl --assess --type execute --verbose=2 "build/distribution-check/Aagedal Media Player.app"
```

## Updating ffmpeg

Treat `checksums/ffmpeg.sha256` as a reviewed provenance record. When
intentionally replacing ffmpeg, confirm that it is a thin arm64 Mach-O
executable, review its origin and capabilities, then sign the repository copy
with the release Developer ID Application identity, Hardened Runtime, and a
secure timestamp before updating the checksum. The preflight verifies that
signature and also requires the audio decoders, Float32 PCM output, and EBU
R128 filter used by waveform and LUFS analysis; do not substitute an image-only
build even if screenshot/export smoke tests pass.

```bash
codesign --force --sign "Developer ID Application: …" --identifier no.aagedal.full.ffmpeg \
  --options runtime --timestamp "Aagedal Media Player/Binaries/ffmpeg"
codesign --verify --strict --verbose=2 "Aagedal Media Player/Binaries/ffmpeg"
file "Aagedal Media Player/Binaries/ffmpeg"
lipo -archs "Aagedal Media Player/Binaries/ffmpeg"
shasum -a 256 "Aagedal Media Player/Binaries/ffmpeg"
```

The exported app signature check is authoritative for the distributable bundle;
the source checksum detects an unreviewed binary change before archiving.
