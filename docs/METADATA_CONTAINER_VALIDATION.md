# Synthetic RTMD container validation

This originally exercised the proposed SwiftMediaMetadata 3.0.0 RTMD skip-`mdat`
patch through public RTMD APIs. It complements the
[memory profile](METADATA_MEMORY_PERFORMANCE.md) with small deterministic fixtures
that contain actual synthetic RTMD sample tables and payloads. SwiftMediaMetadata
3.0.1 is now the production dependency; the baseline/patch mode remains a
historical comparison workflow.

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

To exercise a reviewed source commit rather than the recorded patch, append
`--candidate-checkout /path/to/clean/candidate --expected-candidate-sha FULL_SHA`
to the command. Both options are mandatory together; `FULL_SHA` must be the
exact lowercase 40-character `HEAD`, and the candidate checkout must be separate
and clean. With neither option, patch mode is unchanged. Source provenance records
both archive hashes and whether the patch was applied, and both checkouts are
reverified unchanged after the run.

For the current release, use a clean 3.0.0 checkout as the first argument and a
separate clean 3.0.1 checkout with
`--expected-candidate-sha 8662054299a3e13c49c65f74c564360559d1bf7f`.

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

## SwiftMediaMetadata 3.0.1 result — 2026-09-15

The exact-checkout mode passed the same 27 cases for both the 3.0.0 baseline and
the released 3.0.1 commit: 54 isolated processes, zero mismatches or errors, and
unchanged clean checkouts. This directly covers RTMD presence, frame values,
timestamps, 100 Hz IMU rate, complete gyro/accelerometer samples, `stco`/`co64`,
atom placement/sizing and the documented malformed cases against the production
dependency. Artifacts with source archives and complete provenance are retained
at `/private/tmp/aagedal-metadata-edges-smm301-20260915`.

## Remaining acceptance

Synthetic RTMD decoding alone cannot establish compatibility with real Sony
camera files. The subsequent [real-media validation](METADATA_REAL_MEDIA_VALIDATION.md)
checks one native Sony A1 clip, BRAW/CRM/R3D examples and the upstream library suite.
The reviewed dependency release and targeted production memory profile are complete.
Broader bodies/recording modes, formats and intended error semantics remain open.
