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
separately by the paired exporter check above. CLI tests were excluded from that run; the separate CLI result below closes that
coverage gap. The
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

## Separate offline CLI validation

The CLI suite can now run separately against the same candidate without fetching
packages or changing the production checkout:

```bash
python3 scripts/validate-metadata-cli.py \
  /path/to/SourcePackages/checkouts/SwiftMediaMetadata \
  /path/to/swift-argument-parser \
  /tmp/new-cli-validation
```

Both inputs must be clean git checkouts. The library must be at the pinned 3.0.0
revision above; ArgumentParser must match its committed `Package.resolved`
(1.7.1, `626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b`). The script archives
committed source into a new output directory, applies only the recorded RTMD
patch, and changes only the copied manifest's ArgumentParser dependency to its
local archived copy. All upstream CLI and test source remains unchanged.

The command runs `swift test -c release --disable-sandbox --filter
SwiftMediaMetadataCLITests` with `SWIFT_EXIF_RUN_CLI_TESTS=1` and an explicit
`SWIFT_EXIF_CLI_BINARY` pointing at the candidate Release binary. This avoids
accidentally using another Debug build or silently opting out of black-box tests.
Build and test execution has a 30-minute timeout. Acceptance requires the exact
pinned inventory of 28 black-box and 22 helper tests, with every individual suite
and both 50-test aggregate summaries complete. Any failed/skipped tests, missing,
duplicate or unexpected suite, wrong count, nonzero exit, timeout, or changed
input checkout fails acceptance.
The output records both source archive hashes, patch/script hashes, toolchain,
exit status, test counts and full build/test log hash. The CLI tests create their
own temporary synthetic fixtures; they do not use the camera originals above.
This suite covers command behavior, not additional Sony camera modes or memory
performance, and does not repeat the library-only suite.

On 2026-09-07, this candidate Release suite passed **50 tests, zero skips and
zero failures** in 2.685 seconds after a 97.46-second build using Apple Swift
6.3.3 on arm64 macOS. Coverage includes 28 black-box tests for help/version,
reading, writing, copying/remapping, stripping, diffing, argfiles and stay-open
behavior, plus 22 date-format, group-prefix and mapping helper tests. Both source
checkouts remained unchanged. The subsequent empty Swift Testing runner is not
included in those XCTest counts. Artifacts: `/tmp/aagedal-metadata-cli-20260907`;
CLI suite log SHA-256:
`07c28a2da4073e1ac358ba957aeddc2e3665a7349a4bd2b2457e70ca0f230b4b`.
The strengthened complete-inventory acceptance parser was verified against that
retained log (`revalidated-summary.json`) and nine focused Python regression
tests (`python3 scripts/test-metadata-cli-validation.py`); no second Swift build
was needed.

## Expanded local result — 2026-09-08

A second paired Release run added a longer native Sony A1 clip, ProRes RAW HQ
in MOV, ARRIRAW in MXF, and Sony X-OCN LT in MXF. All ten isolated executions
(five workloads per variant) succeeded and every baseline/candidate result
matched. The Sony check covered 5,568 RTMD frames, the first-frame snapshot,
2,000 Hz IMU rate, and all 222,720 samples in each motion stream. Input media
and every candidate NRT sidecar remained unchanged by the before/after hashes.

| Local fixture | Bytes | Exported fields | Input SHA-256 |
| --- | ---: | ---: | --- |
| 20260502_TRA_MOV_0240.MP4 | 1,569,013,272 | 69 | `d8f32f9e827dba821a8101c7dd713580e37b03e9723c4ffbf136919829d6fbe1` |
| a7s III ProRes RAW HQ.mov | 1,672,990,980 | 31 | `bb60c894a7ee17930c54161123dd98ba99f2df935a148cd3c70cef614787c5c2` |
| DW0001C005_251020_113322_a1I7H.mxf | 1,989,333,076 | 33 | `5b315def2190009aa61eee6ef127404cf18a661df8ffeece880ef14c682b5361` |
| S35 5.8 X-OCN LT 24p 17.9 (SCENE 4).mxf | 1,001,494,064 | 75 | `a1485b5820a4236503bebdc2e42c6e6417471506d288eb017759265b1a225a98` |

Artifacts are at `/tmp/aagedal-metadata-real-20260908-expanded`. The command
used the same pinned checkout and unchanged probe/script, with
`--reuse-packages /tmp/aagedal-metadata-edges-20260907-final`; the harness verified
the complete baseline/candidate library source inventories before rebuilding.
The exact fixture paths, sidecar hashes, toolchain and all safe result digests
are retained in `environment.json` and `summary.json`. The library and CLI
suites were not repeated because their source and candidate patch were unchanged.
This extends raw-format and longer-clip coverage; both native RTMD examples are
still Sony A1 clips, and exporter parity does not establish complete extraction
or metadata correctness in these formats. No memory measurements were taken.

## More camera/container coverage — 2026-09-09

A paired Release run added GoPro Hero9, GoPro Hero12 with log enabled, DJI
Action4 MP4, and Sony FX6 MXF clips. The existing `--raw` option now also accepts
the clearer `--media` spelling for camera/container inputs. All twelve isolated
executions passed: six workloads per variant, comprising the four new exporter
checks plus the existing short Sony A1 metadata/full-RTMD control. Every baseline
and candidate result matched and all original/sidecar hashes remained unchanged.

| Local fixture | Bytes | Exported fields | Input SHA-256 |
| --- | ---: | ---: | --- |
| DolomitesSet1-Hero9-GX019609.MP4 | 825,867,613 | 41 | `e8e87cd4fdc21085fb1df8c540ed4ed8a2687f615a8d1c77c69da41cb8f6b20d` |
| NightSEt1-Hero12-LOGEnabled-GX010055.MP4 | 188,649,225 | 41 | `69b74923c90fb14d330ac95426c9017c29e041786d20d6a19978884e99dc284a` |
| NightSet1-Action4-DJI_20230905195641_0033_D.MP4 | 1,263,320,832 | 41 | `9bde57a41e90bc1fb4cd0aab7e0865f4786f939044d884424d9f10c2b4f20f00` |
| OJ_FX6A0020.MXF | 245,605,936 | 45 | `ab07d7d507536717bb92fa15317b6c5961e711e22cb6384e5cf07274d550a439` |

The three MP4 clips each returned one video and one audio stream and no Sony
RTMD. The FX6 MXF returned one video and eight audio streams, also without Sony
RTMD in the exporter. This extends exporter parity and the MP4 negative-probe
camera coverage; it does not validate GoPro/DJI motion decoding or another Sony
body's native RTMD frame stream. The reused A1 control retained 672 frames and
26,880 samples in each motion stream. No memory measurement was taken.

Artifacts: `/tmp/aagedal-metadata-real-20260909-cameras`. The run used
`--reuse-packages /tmp/aagedal-metadata-edges-20260907-final`; source inventories
were verified before reuse. The new inputs live under `Movies/TestVideo/GoPro`
and `Movies/TestVideo/A1_v_FX6/FX6`; exact paths, hashes and safe exporter digests
are in the environment/summary artifacts.

The separate [upstream fixture run](METADATA_LIBRARY_FIXTURE_VALIDATION.md)
now exercises the original 20 library skips: fourteen pass, five still lack
ARW/sidecar originals, and one reveals an outdated JXL fixture/assertion
expectation. That failure remains an explicit acceptance blocker.

## Remaining acceptance

Paired exporter coverage is limited to these twelve exact clips and two native Sony A1 examples.
Broader Sony bodies/modes, more raw formats and unusual container/error cases
remain relevant acceptance work. A reviewed upstream release is still needed;
Checking published tags with `git ls-remote --tags` on 2026-09-09 found no release
newer than the pinned 3.0.0 (`c2d77c2`); `gh pr list --state all` returned no pull
requests. This does not establish whether review occurred outside GitHub PRs.
After integration, repeat the isolated memory profile and full-app
metadata/loudness workload including conversion, concurrent work and release.
App-wide bounded memory remains unproven by this parity check.
