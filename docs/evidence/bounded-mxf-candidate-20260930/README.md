# Isolated bounded MXF reader candidate — 2026-09-30

A portable upstream SwiftMediaMetadata candidate now replaces full-file MXF
mapping with bounded positional reads. It applies to 3.0.1 revision
`8662054299a3e13c49c65f74c564360559d1bf7f`. The shipping package pin, app source,
and external development checkout were not changed by this work. This is an
upstream candidate, not a shipped correction or completed release acceptance.

[The patch](swift-media-metadata-bounded-mxf.patch) contains six source/test
files. `git apply --check` passes against an isolated checkout of the revision,
and `git diff --check` passes. The working candidates were created under
`/private/tmp/aagedal-bounded-mxf-{candidate,baseline}-20260930`.

## Behavior and compatibility

The existing Data entry and new `MXFReader.parse(from: URL)` share one KLV
classification/extraction loop. The URL API detects MXF before the generic
whole-container loader, then retains the existing shared URL postprocessing.
Every KLV is visited, including metadata after essence. The existing 512-byte
sniff, unknown-key XML/JUMBF recognition, 32 MiB complete metadata cap, NRT/ARRI
16 MiB prefix fallback, maximum-duration derivation, timecode encounter order,
Primer/MCA references, sidecar merge, format promotions and read-only
`originalData` ownership remain intact.

The cursor reads directly into bounded Data with `pread`, without mmap,
read-ahead or a retained essence cache. It uses subtraction-based bounds
checks, rejects unsupported extents, retries interrupted/partial POSIX reads,
and closes its descriptor on all exits. Invalid/truncated BER retains the
existing tolerant parse behavior; genuine I/O errors propagate. Concurrent
truncation or growth detected by the final descriptor extent check fails the
URL read. Same-size concurrent writes and path replacement are not proven
immutable or detected; callers still need stable source files.

Parser scratch depends on the capped prefix and one capped metadata value,
not essence size. Retained parsed results can still grow with metadata count;
this is not a fixed total-memory ceiling.

## Validation

- [Full upstream library suite](library-tests.log): **1,674 tests, 21 explicit
  opt-in skips, zero failures**. CLI targets were not exercised.
- [Focused MXF/VideoContainer/MCA/ARRI suite](focused-tests.log), with the
  authentic FX6 Data/file exporter parity enabled: **152 tests, one unrelated
  opt-in skip, zero failures**.
- [Final authentic read instrumentation](authentic-reads.log): one test passed;
  **965,737 positional requests, 72,730,354 requested bytes, maximum single
  request 16,777,216 bytes**, against the 8,643,449,904-byte source. Request
  totals include repeated BER-byte/header/sniff reads and the fallback prefix;
  they are requested bytes, not an allocation or OS residency measurement.
- New focused tests cover a sparse **512 MiB** skipped essence value with
  footer NRT and dark-key C2PA, late duration and Material/File timecode
  ordering, nonzero-index Data slices, indefinite/overflow/truncated BER,
  arithmetic bounds, concurrent truncation, and injected I/O failure.
  Existing synthetic NRT/RP2057/C2PA/capped-value/MCA fixtures now compare
  Data and file exports. Nonzero partial reads/EINTR are handled in code but
  are not deterministically injected by the tests.

The local cached argument-parser Git checkout has a broken object alternate.
Both isolated builds therefore used the same temporary package manifest
omitting the ArgumentParser dependency, CLI executable and CLI tests, while
retaining the library, Benchmark and library test targets. The portable patch
contains **no manifest/dependency/Benchmark changes**. Module caches were
redirected to `/private/tmp`. Identical Release probes built successfully with
`swift build --disable-sandbox -debug-info-format none -c release --product
Benchmark --scratch-path …`; disabling debug info avoids a sandbox-blocked
`dsymutil` helper. [Candidate](candidate-release-build.log) and
[baseline](baseline-release-build.log) build logs are retained.

## Separate-process library measurements

[Probe source](probe.swift), [runner](run-probes.py), and complete
[probe records](probes/summary.json) are retained. Each read used a fresh
standalone Release library process. Peak increases come from native
`getrusage`; current resident bytes before/after load/release are also retained.
Complete `VideoMetadataExporter.buildDictionary` JSON matched the unpatched
URL-reader baseline on all six inputs, including ARRIRAW/X-OCN format and
camera fields and MCA labels.

| Input | Baseline peak increase (MiB) | Candidate peak increase (MiB) | Baseline / candidate read seconds |
| --- | ---: | ---: | ---: |
| Sony MP4 `rre_8073.MP4` | 4.500 | 4.531 | 0.015 / 0.015 |
| Sony A1 `20260502_TRA_MOV_0240.MP4` | 63.016 | 62.375 | 0.025 / 0.023 |
| Sony FX6 `OJ_FX6A0021.MXF` (8.64 GB) | **373.000** | **21.703** | **0.197 / 0.399** |
| ARRIRAW `DW0001C021_251020_132307_a1I7H.mxf` | 30.469 | 20.500 | 0.044 / 0.044 |
| X-OCN `S35c 4K X-OCN LT 120p 17.9 (SCENE 4).mxf` | 36.094 | 21.734 | 0.041 / 0.040 |
| MCA `n-intervju_with-MCA-labels.mxf` | 78.688 | 18.813 | 0.044 / 0.054 |

These observations are library-only evidence. App/dependency compilation was
active around the checks, filesystem cache was uncontrolled, and each pair
ran baseline before candidate. Timings are not a throughput/thermal acceptance
benchmark. The FX6 observed read time approximately doubled, consistent with
nearly one million positional read calls, despite staying below half a second
on this host. Review syscall overhead before upstream release; no cache or
known-essence sniff optimization is bundled into this correction.

[Environment and SHA256 identities](probes/environment.json) confirm all six
sources, matching XML sidecars and probe binaries were unchanged after the
runs. The independently reread FX6 SHA256 matches the earlier retained
production evidence:
`5d1c636920c80e7ce83af6486a8de9184c5cacee8a316e799dbb52e8f02174a8`.

App `MetadataService` cache conversion/parity and production process memory,
external-volume behavior, multi-hour scaling, same-size concurrent changes,
Linux execution and base-M1 acceptance remain open. A released immutable
upstream revision and explicit dependency integration are still required
before a shipping repin.
