# Native raster: Apple Silicon expanded acceptance, 2026-10-14

The protocol 2 development candidate was rebuilt from the checksum-verified
published source stage with `--decoder-raster-candidate --apple-silicon-only`.
All eight newly built mpv/FFmpeg XCFrameworks contain only arm64. No Intel
scratch tree was created. Existing qualified auxiliary dependencies were reused;
no package was published and the source project’s shipping pins are unchanged.

## Accepted native cases

[The build receipt](arm64-build-receipt.json) records source trees, retained
source archive and patch identities, tools, SDK, recipe adaptation, artifacts,
fresh provider objects and shipping configuration parity. The build succeeds
with no feature configuration differences for arm64.

[Runtime verification](arm64-runtime-verification.json) passes **31/31 arm64
cases**: eight baseline provenance/freshness/lifecycle cases and 23 expanded
cases. [Per-case results](native-case-results.json) and
[fixture metadata and hashes](fixtures.json) preserve the independent references.
Expanded cases cover eight rotations/reflections on a rectangular grid, scale/
shear/fractional-translation rejection, UHD and DCI 4K, software and actual
VideoToolbox H.264, and 10-bit PQ/HLG FFV1 and HEVC with software and hardware
decoding. Positive cases compare every pixel component at PTS 0 and after an
accurate seek to PTS 1. Hardware cases require `hwdec-current=videotoolbox` and
`hardware-transfer=true`, using an AppKit/Metal surface with gpu-next/MoltenVK.

The H.264 hardware comparisons have maximum component error 0; tolerance was
fixed at 3 before this rebuild. PQ and HLG HEVC hardware comparisons also have
maximum error 0, with 843 and 857 distinct red-component levels at the two PTS
values. The HDR tolerance remains the predefined 256 RGBA16 code units. Software
H.264 is within its predefined 3-unit tolerance. Lossless geometry/RGB cases
require exact equality. These limits were not relaxed to make the final run pass.

## Application checks

[Consumer tests](consumer-test-summary.json) pass 21/21 and
[existing loupe tests](loupe-test-summary.json) pass 49/49, all arm64, with no
failures or skips. They cover protocol parsing, UHD bounds, malformed data,
HDR CGImage tags, PQ conversion above SDR white, source-proof gating, rendering,
geometry, and lifecycle. The stock dependency correctly remains preview-only.

The [isolated app candidate](app-candidate.json) uses eight rebuilt local binary
targets plus 21 qualified shipping auxiliary targets. The [hosted XCTest](hosted-test-summary.json) passes with no failures or skips.
Its [acceptance markers](hosted-acceptance.txt) prove **20/20 positive fixture
cases** ran through the real PlayerController, MPVMetalLayer and LoupeFrameCapture.
Each checks native metadata, source and CGImage sample pixels at PTS 0 and 1,
HDR color-space tags, cached CGImage identity while paused, and proof revocation
on resume. This is one XCTest containing 20 fixture cases, not 20 independent
XCTest methods. Software/hardware decoder selection is explicit per fixture.
[Hosted binaries](hosted-binaries.json) and the retained xctestrun bind that
acceptance to the actual arm64 app and test bundle. Negative transform cases
are covered by the native harness.

## Reproduction and scope

Temporary build workspace: `/private/tmp/aagedal-native-raster-20261014/build-arm64-v7`.
Fixtures: `/private/tmp/aagedal-native-raster-20261014/extended-fixtures-v3`.
Native runtime workspace: `/private/tmp/aagedal-native-raster-20261014/arm64-runtime-final`.
The retained fixtures/binaries/source archive remain outside the repository;
their hashes, source identities and commands are recorded here. The source stage
asset and verified SHA256 are documented in the
[initial rebuild evidence](../mpv-native-raster-integration-20261014/README.md).

The development environment flag is `AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1`.
Native hardware cases use VideoToolbox explicitly; the hosted harness sets
`AAGEDAL_MPV_DECODER_RASTER_HWDEC` per case. Default application behavior stays
off until a provider package is deliberately published and repinned.

The script-validator suite passes, including architecture-declaration rejection
and arm64 configuration parity without an unbuilt Intel slice. Compressed logs
retain command output. Native harness link warnings about the validation host’s
Homebrew libraries are retained in `native-stderr.json.gz` and the runtime log.
This accepts the bounded generated cases on this Apple Silicon host; it does
not establish physical-display HDR calibration, arbitrary-media correlation,
sustained memory/sanitizer acceptance, or a publishable dependency package.
