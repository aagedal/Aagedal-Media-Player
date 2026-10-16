# App-side AddressSanitizer qualification

This continuation exercises the arm64 application and hosted XCTest code under
AddressSanitizer, using the unchanged, checksummed native-scope MPVKit candidate.
The dependency is restored and verified rather than rebuilt. Shipping package
pins and the native-raster provider's default-off gate remain unchanged.

The existing scope payload-copy test now reads every byte of waveform, parade
and vectorscope images after the node fixture has freed all its payload buffers.
Distinct patterns also detect swapped plots. Dimensions alone could not establish
that the image providers retained independent data.

## Accepted run

On macOS 27.0.1, the optimized arm64 Release build and all **63 selected tests**
pass with **zero failures and zero skips**. The full 20-case native-raster,
SDR/PQ/HLG native-scope and native-demand acceptance markers are present. No
AddressSanitizer error or summary is reported. The test action takes 22.35 seconds;
this is an observation, not a performance qualification.

[The receipt](candidate-receipt.json) pins matching prepared/current Swift
sources, app/test executable hashes, arm64 architecture, ASan load/report
symbols, dependency descriptors and fixture manifest. The compressed build log
and extracted compiler commands retain `-sanitize=address` for both app and test
modules. [The XCTest summary](summary.json), compressed stdout/action logs,
executed configuration and [runner output](runner.log) retain the result.
The source patch records the exact test delta from the receipt's source commit.

The runner also rejects an ordinary non-ASan xctestrun before launching tests.
The instrumented app and result bundle remain at
`/private/tmp/aagedal-app-asan-20261016/derived` and
`/private/tmp/aagedal-app-asan-20261016/tests/tests.xcresult`. They are development
artifacts; the ordinary candidate and its performance receipts remain separate.

## Reproduce

Prepare current app sources with the verified package using the
[native scope handoff](../../MPV_NATIVE_SCOPES.md). Build in a separate location:

```sh
xcodebuild build-for-testing \
  -project '/path/to/prepared-app/Aagedal Media Player.xcodeproj' \
  -scheme 'Aagedal Media Player' -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/aagedal-app-asan-derived \
  -onlyUsePackageVersionsFromResolvedFile -enableAddressSanitizer YES \
  ENABLE_TESTABILITY=YES ARCHS=arm64 ONLY_ACTIVE_ARCH=YES

python3 docs/evidence/mpv-app-asan-20261016/run.py \
  /path/to/generated.xctestrun /path/to/rebased-native-fixtures.json \
  /path/to/generated-media-fixtures /path/to/scope-signal-fixtures \
  /private/tmp/aagedal-app-asan-results
```

The media root must contain the generated `loupe` fixtures. Scope fixtures are
`delta/validation/signal-fixtures` in the restored scope candidate. The native
manifest uses the independently referenced 20-case raster workload. Keep the
interactive macOS session available for Metal and actual VideoToolbox decoding.

The retained runner preserves Xcode's ASan runtime injection, requires an
ASan-configured xctestrun, clears inherited workload modes and runs serially.
It requires successful XCTest exit, at least 50 passing tests, zero failures or
skips, all three native raster/scope/demand acceptance markers, and no ASan error
or summary marker. It retains the executed configuration as evidence; that copy
must be placed beside the original xctestrun to reuse its `__TESTROOT__` paths.
Build commands and executable instrumentation must also be checked: an ASan
runtime name in a plist alone does not prove compiler instrumentation.

## Scope and limits

The selected tests cover malformed/bounded node payloads, raster color conversion,
all three scope image copies, screenshot fallback/difference processing, capture
generation revocation, paused AV recapture, backend replacement, loupe surface
rebinding/resize, readback suppression, pause/seek and decoder teardown. The full
native raster manifest checks 20 software/hardware cases inside one XCTest.

The shipping-only fallback test is excluded because this run enables the
candidate provider. Scope throughput and sustained comparison tests are excluded
because their performance and physical-footprint limits were defined for ordinary
builds. Their existing acceptance evidence remains separate.

MPVKit, mpv, FFmpeg and graphics/system frameworks are uninstrumented. This run
does not establish sanitizer coverage of native provider internals, race freedom,
leak freedom, GPU allocation correctness, peak memory, sustained performance,
producer-authentic long media, other hosts or physical HDR calibration. The
portable native scope-math ASan/UBSan check remains separate. A native provider
sanitizer run requires a new dependency build and new acceptance evidence under
the existing handoff rules.
