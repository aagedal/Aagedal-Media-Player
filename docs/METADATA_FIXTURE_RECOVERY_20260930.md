# Metadata fixture recovery and exact 3.0.1 acceptance — 2026-09-30

Nine reviewed JPEG/JXL/XMP originals are available again in
`/Users/truls.aagedal/Pictures/TestImages`. Every file matches the identity pinned
in [the fixture acceptance table](METADATA_LIBRARY_FIXTURE_VALIDATION.md).
The nearby `TestImages copy` directory is unsuitable: four same-named images,
including `ShortPlantHDR_seq_000001.jxl`, have different hashes, and
`DEI_8158_edit.jpg` is absent. No alternate image was substituted.

## Recovered Sony raw

The authentic `TRA03164.ARW` was recovered from:

```text
/Users/truls.aagedal/Library/Mobile Documents/com~apple~CloudDocs/Photos/2026/2026-01-01 – Tur Til Andrea – Måne/TRA03164.ARW
```

It is 60,850,176 bytes; SHA-256:
`385d5397ab5338e86bb2ef68b5543a05aa82b7ff9d93b7607cb19279e33fae3b`.
Independent ExifTool inspection reports make `SONY`, model/Sony model ID
`ILCE-1`, original date `2026:01:01 15:30:09`, dimensions 8704 × 6144, and lens
`FE 35mm F1.4 GM`. This matches the upstream raw test's camera contract.

All three unchanged raw assertions passed against the exact integrated 3.0.1
release: `testReadARW`, `testARWWriteIPTCAndXMP`, and
`testWriteSidecarForARW`. The original and staged raw remained byte-identical.
The recovery, independent metadata identity and original assertions support
pinning this input in the fixture validator and acceptance table.

The adjacent uppercase `TRA03164.XMP` is **not the historical test sidecar**.
Its SHA-256 is `4355af3b782b449a8438ebf440d4858d9e810e70dc94c86c702e117ecf061b7c`
and size is 3,666 bytes. Its XML lacks the asserted headline, credit, subjects,
creator, title, description and people. ExifTool independently finds none of
these fields. The upstream test expects headline/title `Hello world'`, credit
`TV 2`, subjects `I am the king`, `star wars`, `Strawberry`, creator
`Truls Aagedal`, description `2026-03-18 , :`, and people `Jonas`, `Silje`.
This incompatible sidecar was not copied, renamed, pinned or used in acceptance.

## Exact release and upstream assertion

A read-only `git ls-remote` check of
[SwiftMediaMetadata](https://github.com/aagedal/SwiftMediaMetadata) returned
`8662054299a3e13c49c65f74c564360559d1bf7f` for both upstream `HEAD` and
`refs/heads/main`. This is the integrated 3.0.1 release. Its unchanged
`testReadJXLBareCodestream` still expects a `writeNotSupported` throw from the
reviewed container. The fixture recovery does not reconcile that assertion.

The JXL diagnostic now supports `--candidate-checkout` and
`--expected-candidate-sha` through the shared source-provenance helper. It
archives a separate clean pinned 3.0.0 baseline and exact candidate, never
applies the RTMD patch in exact-candidate mode, records each upstream assertion
and source hash, and verifies both source archives after execution. Its evidence
validator requires the reviewed real codestream's hash and integer size, in
addition to the seven successful checks and matching variants. Missing or
identically incorrect codestream evidence fails validation.

The fixture validator also recognizes the actual Swift 6.4 test-target product
suite name `SwiftMediaMetadataTests.xctest`, in addition to the historical
SwiftPM name `MetadataFixtureValidationPackageTests.xctest`. The initial release
rerun exposed this toolchain difference. Both names map to one required suite;
duplicate aliases, unknown suites, failures and incomplete summaries still fail.

The exact-release diagnostic command is:

```bash
python3 scripts/diagnose-metadata-jxl-fixture.py \
  /path/to/clean/3.0.0/baseline \
  /Users/truls.aagedal/Pictures/TestImages/ShortPlantHDR_seq_000001.jxl \
  /tmp/new-jxl-release-diagnostic \
  --candidate-checkout /path/to/clean/3.0.1/checkout \
  --expected-candidate-sha 8662054299a3e13c49c65f74c564360559d1bf7f
```

## Release evidence

The final exact 3.0.1 run exercised all twenty unchanged fixture cases:
**17 passed, two skipped, one failed**. The only skips were
`testReadExistingSidecar` and `testReadSidecarMatchesManualRead`, which require
the unavailable historical XMP. The sole failure was the existing JXL throw
assertion. Consequently `passed` and `allFixturesCovered` remain false.
All staged inputs, originals supplied to the harness and both clean source
archives remained unchanged. The ten reviewed image/raw/sidecar files were
staged in `/tmp/aagedal-reviewed-images-20260930`; CRM and MCA remained at their
original documented locations. The original iCloud ARW and original nine-image
source directory were also rehashed against the reviewed pins after the run.

Both final JXL Release probes passed all seven checks with identical results.
The pinned real codestream remains 584,049 bytes and SHA-256
`124ae9b5ecd477f23a3e87072dc01f4c20f78752cf4fa7dfbbbf05267561ac06`.
The candidate provenance records exact release SHA
`8662054299a3e13c49c65f74c564360559d1bf7f`, with no applied patch. Both baseline
and release tests still expect unsupported writes; the contract requires
upstream review. Original/staged JXL and both source archives remain unchanged.

Durable records, including complete test output and identities:

- [Independent recovered-input identities](evidence/metadata-fixture-recovery-20260930/recovered-inputs.json)
- [Fixture environment](evidence/metadata-fixture-recovery-20260930/fixture-environment.json)
- [Fixture summary](evidence/metadata-fixture-recovery-20260930/fixture-summary.json)
- [Fixture test log](evidence/metadata-fixture-recovery-20260930/fixture-tests.log)
- [JXL environment](evidence/metadata-fixture-recovery-20260930/jxl-environment.json)
- [JXL diagnostic summary](evidence/metadata-fixture-recovery-20260930/jxl-summary.json)
- [Three unchanged recovered-raw tests](evidence/metadata-fixture-recovery-20260930/recovered-arw-tests.log)

The fixture log SHA-256 is `b50df66357cf4ce7cbe87f62a56bd36c3a0df1603015651873ba8fb0ff2afe41`.
Temporary build artifacts are at
`/tmp/aagedal-metadata-fixtures-301-reviewed-20260930` and
`/tmp/aagedal-jxl-301-final-20260930`; the durable records above survive their
removal. Toolchain: Apple Swift 6.4, target `arm64-apple-macosx27.0.0`.
Twelve fixture-validator, nine JXL-diagnostic and ten source-provenance Python
regressions pass. They verify evidence rules; the actual recovered-input runs
supply the media compatibility evidence.

The initial sandboxed fixture build failed during dSYM generation with
`Operation not permitted` before running tests. A separate permitted rerun
completed. This environmental build failure is not a metadata fixture result.

The recovered ARW closes three former missing-input skips. The historical XMP
sidecar and reviewed upstream JXL fixture/assertion reconciliation remain
required for a zero-skip, zero-failure fixture acceptance gate. This work does
not replace camera-mode validation or complete production memory profiling.
