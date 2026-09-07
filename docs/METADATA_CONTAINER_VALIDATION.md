# Synthetic RTMD container validation

This exercises the proposed SwiftMediaMetadata 3.0.0 RTMD skip-mdat patch through
public RTMD APIs. It complements the [memory profile](METADATA_MEMORY_PERFORMANCE.md)
with small deterministic fixtures that contain actual synthetic RTMD sample tables
and payloads. It does not change the app's dependency pin or its resolved checkout.

```bash
python3 scripts/validate-metadata-container-edges.py \
  /path/to/SourcePackages/checkouts/SwiftMediaMetadata \
  /tmp/new-metadata-container-validation
```

The checkout must be clean at `c2d77c2dcefcb997623e52beca57bc61ce302cb9`.
The output directory must not exist. The script makes separate baseline and patched
library source copies, builds both in Release without resolving remote packages,
and invokes a fresh process per fixture. Build timeout is 30 minutes; per-fixture
timeout is 30 seconds. A crash, timeout, parity mismatch, or unexpected decoded
value fails the run. Environment, harness/probe/patch and fixture SHA-256 hashes,
generated MOV files, build/patch logs, individual JSON results, and the final
`summary.json` are retained in the output directory.

The fixtures are deliberately minimal parser inputs, not playable camera clips:

- Eight positive cases combine leading/trailing `moov`, `stco`/`co64` offsets,
  and ordinary/extended-size `moov` and `mdat` atoms.
- Two positive cases use a final zero-size `mdat` or `moov`.
- The sample bytes sit at an unaligned absolute offset after 37 padding bytes.
  Two frames carry distinct ISO values (800, 1600), 20 ms spacing, and known signed
  gyroscope/accelerometer triples. Assertions check both ISO values, timestamps,
  first-frame identity, 100 Hz IMU rate, and every motion triple/timestamp. All
  public frame attribute fields are also represented in the parity snapshot.
- One negative case contains no RTMD track.
- Fourteen cases put short headers, incomplete extended headers, undersized
  atoms, oversized 64-bit lengths (including `Int.max`), or truncated payloads
  before/after a valid container.
- Two cases truncate the first sample or put its `co64` offset beyond `Int.max`.

Malformed-case expectations describe the current dependency's public RTMD API
behavior, not a normative file-format policy. Most malformed suffixes preserve
already discovered `moov`; an incomplete extended-size header throws inside the
walker and is swallowed by public RTMD discovery, causing no track to be reported.
The harness checks that the candidate preserves these outcomes. It does not
exercise every private walker error path or every possible malformed input.

## Local result — 2026-09-07

All 27 fixtures passed in both baseline and candidate Release builds on the local
macOS 27.0 / Xcode 26.6 environment: 54 isolated processes, equal public RTMD
results, and correct expected values for all ten positive sample-decoding cases.
No fixture crashed or timed out. The truncated-first-sample and invalid-`co64`
cases preserved track presence but returned no frame or motion samples and no
IMU rate. The incomplete extended-header suffix returned no track in both builds.
Other tested malformed suffixes retained the valid preceding RTMD samples.

Final artifacts: `/tmp/aagedal-metadata-edges-20260907-final`. Temporary artifacts
may be removed by the OS; the generator, probe, recipe and result above are the
durable evidence. This run measures parser behavior, not memory usage.

## Remaining acceptance

Synthetic RTMD decoding cannot establish compatibility with real Sony camera
files. Real RTMD clips still need first-frame/IMU-rate and complete metadata parity,
including representative bodies/recording modes. Representative raw formats,
upstream dependency tests, a reviewed dependency release, and the full-app
metadata/loudness memory profile remain required before production integration.
