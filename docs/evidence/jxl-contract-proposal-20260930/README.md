# Proposed upstream JXL fixture correction — 2026-09-30

The retained [test-only patch](../../dependency-patches/swift-media-metadata-3.0.1-jxl-real-fixture-tests.patch)
reconciles the known `RealFileTests.testReadJXLBareCodestream` contradiction with
the exact 3.0.1 `JXLWriter` contract. The named original fixture is a container;
the writer documents successful container writes, byte-identical unmodified
bare writes, and lossless wrapping when metadata is added.

The proposal reads the authentic container, verifies one complete `jxlc` and
no fragmented `jxlp`, and extracts its genuine codestream. Three optimized
Release tests pass with no skips or failures:

- Container writes preserve the original codestream.
- A bare read/write retains every original byte.
- Editing orientation wraps the codestream once, preserves its bytes and
  round-trips orientation; a repeated write retains one `ftyp` and one `jxlc`.

No library implementation or source fixture is changed. The isolated package
is copied from the exact 3.0.1 fixture-validation package, and every library
source hash matches that reference before and after execution. The fixture
remains 587,205 bytes with SHA-256
`92ae631a48e89f3ef73a355d79df1f4be2c5f7c2fa54572dce3c053dc1963e57`.
[Environment and source hashes](environment.json) bind the patch and proposed
test source. [Release output](tests.log) retains the actual three-test result.

This is a locally tested proposal for upstream review. The unchanged twenty-case
fixture gate remains **17 passed, two skipped, one failed**; this patch does not
replace that record, reconcile the missing historical XMP, or change the app's
dependency pin. It has not been published or applied to the upstream checkout.

The first sandboxed attempt compiled but failed during dSYM generation before
tests. The permitted rerun built and executed all three tests. Original upstream
warnings belong to the package build, not a new app candidate verification.
Temporary build artifacts remain at `/tmp/aagedal-jxl-contract-proposal-20260930`.

To apply the proposal to a separate clean 3.0.1 checkout:

```bash
git apply --check /path/to/swift-media-metadata-3.0.1-jxl-real-fixture-tests.patch
git apply /path/to/swift-media-metadata-3.0.1-jxl-real-fixture-tests.patch
swift test -c release --filter 'RealFileTests/(testRealJXLContainerWritePreservesCodestream|testReadJXLBareCodestream|testRealJXLBareCodestreamMetadataWrite)'
```

The authentic `ShortPlantHDR_seq_000001.jxl` must be present in that isolated
checkout's `TestImages` directory; do not substitute a same-named alternate.
