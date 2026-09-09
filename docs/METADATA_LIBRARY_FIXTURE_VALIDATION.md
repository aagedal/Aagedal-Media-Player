# Upstream metadata fixture acceptance

The [real-media candidate validation](METADATA_REAL_MEDIA_VALIDATION.md) originally
ran 1,662 upstream library tests with 20 missing-fixture skips. The separate
fixture harness now selects those exact 20 cases, preserving their assertions:

```bash
python3 scripts/validate-metadata-library-fixtures.py \
  /path/to/SourcePackages/checkouts/SwiftMediaMetadata \
  /tmp/new-library-fixture-validation \
  --images /path/to/TestImages \
  --crm '/path/to/Canon Cinema RAW Light/A001C004_22032472_CANON.CRM' \
  --mca /path/to/MCA_Test/n-intervju_with-MCA-labels.mxf \
  --allow-missing-images
python3 scripts/test-metadata-library-fixture-validation.py
```

The source checkout must be clean at the production 3.0.0 revision
`c2d77c2dcefcb997623e52beca57bc61ce302cb9`. The harness archives its committed
source into a new output directory and applies only the recorded RTMD skip-mdat
candidate to the library. A local library/test manifest excludes the CLI and
remote dependencies. It copies the named image, sidecar, CRM and MXF fixtures
into that isolated package. The two upstream tests with hard-coded developer
home paths get exactly one path-expression replacement each, resolving their
staged fixture relative to `#filePath`; no assertion or skip condition changes.
All other upstream test source remains unchanged. No original fixture is edited.

Release build/test execution has a 30-minute timeout. Inputs and staged copies
are hashed before and after execution; the clean checkout and missing-fixture
absence are rechecked. The environment records the committed archive hash,
script/patch hashes, both relocated test hashes, toolchain, fixture sizes/hashes,
and exact case selection. Build and test output remains local. Current fixtures
need about 2.5 GB of temporary space, plus the package/build artifacts.

By default missing image fixtures fail before building. With the explicit
`--allow-missing-images` option, only the exact tests requiring absent named
fixtures may skip. Every other case must pass; the exact 20-case inventory and
all five XCTest summaries must be complete and consistent. Partial coverage is
reported with `allFixturesCovered: false`. Failed tests always fail acceptance,
including failures reproduced in the baseline. `--baseline-control` runs an
unpatched source archive through the same fixture staging and assertions in a
separate new output directory. Seven Python regression tests check complete and
partial results, unexpected skips/failures, missing/duplicate cases or summaries,
incorrect counts, process failure/timeouts, and empty alternate-runner output.

## Local result — 2026-09-09

The candidate exercised **20 tests: 14 passed, five skipped, one failed**.
Fourteen previously skipped tests now pass: Canon C70 CRM camera/thumbnail
assertions, the four-track MXF MCA labels/group/language/renderer assertions,
and twelve JPEG/JXL/XMP read, write and round-trip checks. This was a focused
run of the formerly skipped cases; it did not repeat the other 1,642 library
tests or the separate 50-test CLI suite.

Five tests still lack the exact `TRA03164.ARW` and `TRA03164.xmp` originals.
These cover Sony A1 still-image reading/writing and sidecar reading/writing.
The available nearby Sony files were not substituted for fixtures with
specific upstream metadata expectations.

The newly exercised `testReadJXLBareCodestream` fails because it expects
`ImageMetadata.writeToData()` to throw. The local file with the expected name
is a **JXL container**, beginning with `0000000c4a584c200d0a870a`, rather than the
`ff0a` bare-codestream signature. In addition, the pinned library's
`JXLWriter.wrapBareCodestream` already supports lossless bare-codestream writes;
its existing `JXLWriterTests` explicitly assert no-op preservation and metadata
wrapping. The old real-file assertion therefore needs upstream review alongside
the fixture's identity. The harness preserves and reports this failure; it does
not mark the entire fixture gate complete.

An unpatched baseline control then reproduced the **same 14 passed, five
skipped and one failed case outcomes**. This establishes that the observed JXL
failure predates the RTMD candidate; identical failures still do not pass the
fixture acceptance gate. Baseline artifacts:
`/tmp/aagedal-metadata-library-fixtures-20260909-baseline`; log SHA-256:
`96d853477993afc35f821cc31a4ca0bbdd9284bb0e148fc84ba13e76e3ce73d9`.

Both variants' original and staged inputs remained byte-identical and the
production checkout remained clean. Exact local paths and all candidate records:
`/tmp/aagedal-metadata-library-fixtures-20260909`. Candidate log SHA-256:
`28d8187f15f698ad1b09c5046e6123958768f2c736da508b8d317e36e1921d2b`.

| Fixture | Bytes | SHA-256 |
| --- | ---: | --- |
| Nepobaby sesong 2 01.jpg | 7,807,107 | `79177d554a27f15183c8bd0861a0c4fc3c92be7c8cbaba1829bfeca88818b757` |
| TRA03167_edit.jpg | 16,036,356 | `e425f11497a948acd14158941b8f7c12b28d96d308dce7877f346126f6150be9` |
| S01E13 The Parting of Ways-0003.jpg | 383,109 | `67a6631a76e6ab226da4f9367d63c6373c6a160b5dcc670016e9dbbd0db6b3fb` |
| S01E13 The Parting of Ways-0006.jpg | 279,629 | `ea07a8985925092731d91ffa100c61e87eff820e7ce9b64430ba7f2b49dc51d7` |
| Vixen 2026 05.jpg | 3,020,246 | `eb0d79c52deb04b0e67ca7f8c091d9ec0aa4b585e95134638622154c23544f7b` |
| ShortPlantHDR_seq_000001.jxl | 587,205 | `92ae631a48e89f3ef73a355d79df1f4be2c5f7c2fa54572dce3c053dc1963e57` |
| TRA03168_edit_002.jxl | 7,936,580 | `75c772fac47508798e3ef96618dc405676a53f2a0e74186eb965b61379923a89` |
| Nepobaby sesong 2 06.xmp | 3,505 | `64802bc1bc6735e6d6b34138120c71f68cce190da0dfbe4f4031045db145d6c7` |
| DEI_8158_edit.jpg | 1,594,293 | `4f97e1d1239d804fadaadd84f466f0b415a6eb02db5842dc250a07bf956dd039` |
| A001C004_22032472_CANON.CRM | 1,798,905,972 | `b869a48d567d39a01d525cc532d88b5c720fbc5ac5c7c84f43b3734fa2bbdaf6` |
| n-intervju_with-MCA-labels.mxf | 591,046,832 | `e6b67949b33cad33126b675dbf8bf74eb0e1a6b119ccd392eb00a393fccf3abf` |

Temporary artifacts may be removed by the OS. The harness, pinned hashes,
coverage and recorded failure above are the durable evidence. This run does
not measure memory, validate more Sony RTMD camera modes, or authorize changing
the production dependency pin.

## Real-codestream JXL diagnostic — 2026-09-10

The independent diagnostic below resolves whether replacing the mislabeled
container with a genuine bare codestream could satisfy the old assertion:

```bash
python3 scripts/diagnose-metadata-jxl-fixture.py \
  /path/to/clean/SwiftMediaMetadata \
  /path/to/TestImages/ShortPlantHDR_seq_000001.jxl \
  /tmp/new-jxl-diagnostic
python3 scripts/test-metadata-jxl-diagnostic.py
```

The harness archives the clean pinned source separately for baseline and RTMD
candidate, stages an unchanged original, and builds a local probe without remote
dependencies. The probe requires a container with exactly one complete `jxlc`
box and no partial `jxlp` boxes, then extracts that real codestream in memory.
It never substitutes a derived file into the upstream fixture suite or edits
the suite's assertions. Seven checks require successful container and bare
writes, byte-preserved codestreams, exactly one codestream after orientation
wrapping, and orientation read-back. Four Python regressions reject missing,
inconsistent, false or non-Boolean evidence and changed/wrong input identity.

Both Release probes passed all seven checks with identical results, and the
original fixture, staged copy and clean production checkout remained unchanged.
Local evidence: `/tmp/aagedal-jxl-diagnostic-20260910`, including the source
archive and tool hashes, build logs, both `probe.json` files and `summary.json`.
This run exercised the separate probe; it did not rerun or change the twenty
upstream fixture cases. The existing seven fixture-validator regressions also
still pass.

The source fixture contains `ftyp`, `Exif`, `jxlc`, and `xml ` boxes. Its actual
bare codestream is 584,049 bytes with SHA-256
`124ae9b5ecd477f23a3e87072dc01f4c20f78752cf4fa7dfbbbf05267561ac06`.
This derived payload is diagnostic evidence; it is not an upstream-approved
replacement fixture. Reconciliation must address the obsolete throw expectation
as well as the original file's container identity. The library's pinned writer
and its existing synthetic tests intentionally support these writes.

The fixture gate still needs the exact `TRA03164.ARW` and `TRA03164.xmp`
originals, reviewed upstream JXL fixture/assertion reconciliation, and a rerun
of all twenty fixture cases with zero failures and no missing-fixture skips.
The diagnostic does not complete those requirements, broader camera acceptance,
upstream review of the RTMD fix, or full-app profiling after integration.
