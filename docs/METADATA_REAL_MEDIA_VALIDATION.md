# Real-media validation of the RTMD memory candidate

This read-only check compares the unchanged SwiftMediaMetadata 3.0.0 dependency
with the proposed skip-mdat patch in isolated source copies. It supplements the
[synthetic container checks](METADATA_CONTAINER_VALIDATION.md) and
[memory investigation](METADATA_MEMORY_PERFORMANCE.md); the production pin and
resolved checkout remain unchanged.

```bash
python3 scripts/validate-metadata-real-media.py \
  /path/to/SourcePackages/checkouts/SwiftMediaMetadata \
  /tmp/new-real-media-validation \
  --rtmd /path/to/sony-rtmd.MP4 \
  --raw /path/to/sample.braw /path/to/sample.CRM /path/to/sample.R3D \
  --upstream-tests
```

The checkout must be clean at `c2d77c2dcefcb997623e52beca57bc61ce302cb9`.
The output directory must not exist. Builds and workloads have 30-minute timeouts.
No media is uploaded, rewritten, or copied. Input media and all matching Sony NRT
sidecar candidates are hashed before and after execution, including sidecar
absence. Reusable `baseline`/`fixed` packages from the other validation scripts
can be supplied with `--reuse-packages /tmp/previous-package-root`; every library
source byte is verified against the pinned baseline or expected candidate before
reuse. Only these isolated packages' manifests/probe targets are updated.

`MetadataRealMediaProbe.swift` compares the entire sorted JSON dictionary returned
by `VideoMetadataExporter.buildDictionary` for Sony and each raw clip. This covers
all fields emitted by that exporter, **not every internal metadata field**. For
Sony it also compares the public RTMD first-frame snapshot, every attribute frame
(including all fields), IMU sample rate, and every timestamp/signed triple in both
motion streams. The first snapshot must equal the first decoded attribute frame.
The output contains SHA-256 digests, format/stream/field counts and RTMD counts/rate;
GPS, serials, capture dates and other personal metadata values are not printed.
Frame digests use Swift reflection at the recorded toolchain, so comparisons across
a different compiler are not promised to have identical digest text.

An error in either reader, missing RTMD track, malformed output, digest mismatch,
changed input/sidecar, or failing upstream suite fails acceptance. Identical errors
are not treated as parity. Logs and `summary.json` retain outcomes. This check does
not measure RSS or claim a performance baseline; it can run alongside app tests.

With `--upstream-tests`, the candidate package gets an unchanged copy of
`Tests/SwiftMediaMetadataTests`, including its bundled JPEG resource, and runs
`swift test -c release --disable-sandbox`. The manifest has only local library,
zlib, probe and library-test targets: no ArgumentParser dependency, CLI target,
CLI tests, or fixture downloads. Upstream integration cases may skip missing
developer fixture files; tests may also use an installed ffmpeg to generate small
synthetic files. The summary reports test exit status and executed/skipped/failed
counts. The suite alone cannot establish real-camera compatibility.

## Local result — 2026-09-07

Both Release variants successfully read all four clips and produced identical
exporter dictionary hashes. All public Sony RTMD attribute and motion hashes
matched: 672 frames, 2,000 Hz estimated IMU rate, 26,880 gyroscope samples and
26,880 accelerometer samples. The separately decoded first-frame snapshot matched
the first entry in the full attribute stream. No reader errors occurred.

| Local fixture | Bytes | Exported fields | Input SHA-256 |
| --- | ---: | ---: | --- |
| 20260118_TRA_MOV_0229.MP4 | 226,775,611 | 69 | `fc9cd015d682646457b5b683cdf69ccc419e26a74e3039b84982846da47be83f` |
| A001_09151129_C060.braw | 169,685,293 | 37 | `a6d78efae696c0702c9702d175a077159aec3bdf94be6aa0b878557f81d95f1d` |
| A001C004_22032472_CANON.CRM | 1,798,905,972 | 36 | `b869a48d567d39a01d525cc532d88b5c720fbc5ac5c7c84f43b3734fa2bbdaf6` |
| KOMODO_Chroma_Key_Sample.R3D | 1,892,986,880 | 17 | `b7c074650d55c55b016d3635f05ac4fd7f69779dce80bb83bbd7aceff0c41456` |

The fixtures live under `/Users/truls.aagedal/Movies/TestVideo`; exact source paths
and safe result digests are recorded in the local artifact environment/summary.
The R3D exporter returned 17 fields and no video-stream entries in both variants;
this is preserved baseline behavior, not evidence of complete R3D extraction.

The candidate's library-only Release suite completed with **1,662 total tests,
20 skipped, zero failures** (1,642 non-skipped tests). Eighteen skips were missing
image/sidecar fixtures, one was a CRM test hard-coded to another developer's home,
and one was an MXF MCA test hard-coded to that home. The local CRM clip was covered
separately by the paired exporter check above. CLI tests were excluded. The
additional Swift Testing runner reported zero tests; the counts above are the
completed XCTest suite, not that empty runner.

Initial paired media results and upstream suite artifacts:
`/tmp/aagedal-metadata-real-20260907`. Suite log SHA-256:
`08e5194abdb7feca4c655abe706c0dc4eda1b265b1f62605b41182a2cd7ebe90`.
The final media-only run at `/tmp/aagedal-metadata-real-20260907-final` also passed
all five paired workloads and verified unchanged input and NRT sidecar hashes
without repeating the unchanged library suite. The Sony `M01.XML` sidecar SHA-256
was `f505eee20f16cca771ddd9b9e80bee462a0cfa6058c63c2c38296e73d8ffcf5f`; the candidate
paths and presence/absence for all four clips are retained in `environment.json`. Temporary artifacts can be removed by the
OS; this recipe, input hashes, coverage and result are the durable record.

## Remaining acceptance

Coverage is limited to these exact clips and one Sony camera/recording example.
Broader Sony bodies/modes, more raw formats and unusual container/error cases
remain relevant acceptance work. A reviewed upstream release is still needed;
checking published tags on 2026-09-07 found no release newer than the pinned 3.0.0.
After integration, repeat the isolated memory profile and full-app
metadata/loudness workload including conversion, concurrent work and release.
App-wide bounded memory remains unproven by this parity check.
