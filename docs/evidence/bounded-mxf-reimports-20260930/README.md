# Bounded MXF repeated production imports — 2026-09-30

The bounded-reader candidate passes **30 distinct imports, 30 immediate cached
reads and an earliest-URL revisit per input** on all three original Sony clips.
Every complete in-process app-model parity check passes. Open descriptors remain
exactly **9** at every release/revisit observation in all three fresh Release
XCTest hosts. Maximum RSS growth after the first released import is **2.578125,
1.921875 and 4.40625 MiB**, respectively. This closes the measured repeated-import
and shared-cache resource slice for this local candidate and these inputs;
shipping dependency pins remain unchanged.

## Procedure and source identity

The source-only app clone is at commit
`ff98066ef8e5525d6ac51a6a380b0d8c2e36cea8`. Its
[temporary project reference](temporary-project.patch) selects
`/private/tmp/aagedal-bounded-mxf-candidate-20260930`, the previously recorded
[bounded-reader candidate](../bounded-mxf-candidate-20260930/README.md).
The exact [temporary library manifest](temporary-library-Package.swift),
[compiled source list](compiled-library-SwiftFileList.txt), linked
[cursor symbols](candidate-mxf-symbols.txt), and
[build origin](candidate-build-origin.json) identify the actual candidate.
The old remote pin is not used as proof of the locally compiled package.

`/private/tmp/aagedal-metadata-reimport-dd-20260930` did not exist before
preparation. No Xcode build database or product directory was copied. Only the
separate validated SwiftPM package cache was APFS-cloned into an independent
cache, with artifact paths remapped there. The initial sandbox attempt could
not write standard compiler caches; the subsequent permitted fresh Release
[build succeeded](release-build.log.gz). The
[initial cache-access failure](initial-sandbox-build.log.gz) is retained.

The opt-in `testProductionMetadataRepeatedImportProfileWhenRequested` uses the
real `MetadataService.shared`. Each import gets a distinct temporary directory
symlink pointing to the original media's parent, then appends the original
filename. The unmodified service's URL keys force independent cache misses,
while original adjacent sidecars remain visible and the large media files are
not duplicated. Caller values are released after the immediate cached read;
one baseline model remains for complete equality checks. Shared-cache entries
remain subject to `NSCache` policy. Revisit equality and timing are observed
without asserting that the earliest entry was never evicted.

[The executed runner](run-production-reimports.py) records before/after hashes
for the app and test executables, library object, project, package resolution,
manifest, profiler/service/model source, compiled library sources, run template,
runner/validators, and original media/sidecars. These identities remain
[unchanged during profiling](environment.json). The candidate package contains
recorded local changes; its actual compiled sources are hashed explicitly.

## Results and enforced bounds

All three native result summaries show one passed test, zero failures and zero
skips. [Raw logs and manifests](runs/), [attachment text](attachments/),
[validated observations](summary.json), and
[resource/direct-URL snapshot comparison](resource-comparison.json) are retained.
The complete `.xcresult` bundles remain at
`/private/tmp/aagedal-metadata-reimport-artifacts-20260930/runs/input-{0,1,2}/Profile.xcresult`.

The validator explicitly received a **32 MiB** budget for maximum release/revisit
RSS growth above the first released import, and a **four descriptor** budget
above the initial host count. Both bounds pass; the exact arguments' effective
values appear in [validation.json](validation.json) and the passing
[validation log](validation.log). These are diagnostic budgets for this run,
not a universal app RSS ceiling. Invalid resource records, incomplete parity,
descriptor growth, decreasing lifetime peaks and missing fresh hosts fail
validation. Revalidation removes earlier passing summary/budget receipts before
validating observations.

| Original input | Imports / immediate cache reads | Maximum RSS growth after first release (MiB) | Initial / observed open descriptors | Lifetime peak increase across all imports (MiB) |
| --- | ---: | ---: | --- | ---: |
| `rre_8073.MP4` | 30 / 30 | 2.578125 | 9 / 9 | 7.15625 |
| `20260502_TRA_MOV_0240.MP4` | 30 / 30 | 1.921875 | 9 / 9 | 61.65625 |
| `OJ_FX6A0021.MXF` | 30 / 30 | 4.40625 | 9 / 9 | 25.140625 |

The first alias's complete app model is the parity baseline for every later
alias, every immediate same-URL read and the earliest-URL revisit. Its retained
stream/format/size/duration snapshot also matches the
[previous original-URL candidate profile](../bounded-mxf-app-production-20260930/summary.json)
for each clip. Cross-run complete app-model baseline parity is not separately
recorded; the earlier snapshot/exporter limitations remain applicable.

Median new-URL load times are approximately 0.0220, 0.0222 and 0.3822 seconds;
median immediate same-URL reads are approximately 0.072, 0.060 and 0.028
milliseconds. These timings and RSS observations overlapped other native
profiling and build work on this host, with an uncontrolled filesystem cache.
They establish neither sustained throughput nor thermal behavior. The directory
aliases exercise cache keys, not cold disk reads or external volumes.

RSS remains elevated above initial after the final revisit (approximately 6.859,
29.125 and 21.953 MiB). Immediate baseline recovery or cache eviction behavior is
not established. Authentic multi-hour scaling, external-volume behavior,
Linux/base-M1 execution, same-size concurrent changes and an upstream immutable
release/repin remain open.

The new validator has eleven passing focused self-tests, including rejection of
bad measurements, middle-cycle growth hidden by final recovery, invalid runner
configuration before a build, and stale passing receipts after failed
revalidation. Ordinary release verification skips this expensive opt-in test
unless its input and repeat-count environment are explicitly supplied.
