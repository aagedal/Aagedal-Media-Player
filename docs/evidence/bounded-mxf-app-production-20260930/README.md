# Bounded MXF candidate in the production metadata service — 2026-09-30

The existing production `MetadataService` profiler passes on an isolated app
built against the bounded MXF candidate. All three original Sony inputs have
full cached `MediaMetadata` equality and the same retained profile snapshots
as the shipping dependency baseline. FX6 lifetime-peak increase falls from
**368.516 MiB to 18.5625 MiB**. This is candidate integration evidence; no
shipping pin or app-source change was made.

## Candidate provenance and procedure

The temporary app Git clone was at
`060f611f7ba1d669a1af7b7846cdf1812f53b531`. Only its dependency reference was
changed to an `XCLocalSwiftPackageReference` pointing to
`/private/tmp/aagedal-bounded-mxf-candidate-20260930`. The library is the
[previous portable candidate](../bounded-mxf-candidate-20260930/README.md).
Its temporary manifest omits the unavailable local ArgumentParser/CLI
checkouts; [that exact manifest](temporary-library-Package.swift) and the
[temporary project diff](temporary-project.patch) are retained. Shipping
repository pins and source were not modified for this profile.

The [compiled Swift file list](compiled-library-SwiftFileList.txt),
[candidate build origin](candidate-build-origin.json), and complete
[compressed build log](attempted-build.log.gz) show compilation from the
patched local package, including `MXFFileCursor.swift`. The linked app contains
[new cursor symbols](candidate-mxf-symbols.txt); the untouched original app
executable does not. The inherited remote checkout/pinned revision alone was
not used as candidate provenance.

The Release `build-for-testing` succeeded with `ENABLE_TESTABILITY=YES` and
isolated package-cache paths. After the stale-output incident documented below,
no further builds ran. Profiling used only `xcodebuild test-without-building`
with unique generated xctestrun manifests and result directories, the original
unchanged production test method, and the unchanged validator. No
playback/decoder/transport action was requested.

[The executed runner](run-production-profile.py) retains exact app, test,
library object, package/project/profiler/metadata-service source, compiled
library source, xctestrun and media/sidecar SHA256 identities.
[Before/after checks](environment.json) confirm those identities were unchanged
during all three fresh-host runs. The actual candidate app/library binary
hashes and local package identity are explicit rather than inferred from the
shipping lockfile.

## Results

The [unchanged validator](validation.log) passed all three fresh XCTest hosts.
Raw profiles, attachment text, [summary](summary.json), and explicit
[shipping comparison](shipping-comparison.json) are retained. The earlier
shipping baseline is
[authentic-camera-metadata-memory-20260930](../authentic-camera-metadata-memory-20260930/README.md).

| Input | Shipping baseline / candidate peak increase (MiB) | Baseline / candidate load seconds | Cached complete app-model equality | Recorded profile snapshot parity |
| --- | ---: | ---: | --- | --- |
| `rre_8073.MP4` | 4.438 / 4.500 | 0.053 / 0.054 | Passed | Passed |
| `20260502_TRA_MOV_0240.MP4` | 59.531 / 59.547 | 0.055 / 0.054 | Passed | Passed |
| `OJ_FX6A0021.MXF` | **368.516 / 18.5625** | **0.184 / 0.403** | Passed | Passed |

Peak increases use native `getrusage` lifetime peaks in fresh processes,
including app conversion. The profiler compares the complete returned
`MediaMetadata` against the cached result using Equatable. Comparison to the
historic shipping run covers the profiler's retained stream/duration/format/
size snapshot, not a separately recorded complete Codable app-model baseline.
Complete dependency exporter parity was already established on six authentic
Sony/ARRIRAW/X-OCN/MCA inputs by the prior library candidate evidence.

FX6 current RSS stays approximately 18.6 MiB above initial after caller-owned
metadata is released; immediate return to baseline RSS is **not** established.
Repeated-import memory behavior and the app cache should be assessed before
release. Timings were observed alongside other
root native/build work and an uncontrolled filesystem cache; they are not a
throughput or thermal benchmark. External volumes, multi-hour scaling,
Linux/base-M1 execution and same-size concurrent changes remain open.

## Incidental DerivedData mutation and restoration

The initial setup APFS-copied historic DerivedData for build reuse. Its build
database retained absolute paths to the original DerivedData. Xcode consequently
removed **36 original flat framework/dSYM/header outputs** under
`/tmp/aagedal-live-authentic-current-dd-20260930` during stale-output cleanup.
This was an isolation mistake. The shipping repository/package pin and the
original package checkout/cache were not changed. Profiling had not started
when the mistake was detected; subsequent work used only the already-built
candidate and `test-without-building`.

[The restoration record](stale-output-restoration.json) lists every affected
path and restoration-source byte/symlink fingerprints. All 36 paths were
restored from corresponding APFS-copied flat outputs or equivalent pinned
vendor products and verified identical to those sources. Independent
per-flat-output pre-build hashes were not recorded, so exact pre-incident
identity for those flat products cannot be independently proven. There are
no remaining missing logged paths; this limitation is retained rather than
rewriting historic receipts.

The original app executable matches the independent pre-candidate hash already
recorded by the live-meter repeat preparation. That preparation separately
acknowledged its earlier difference from the older metadata-profile app hash.
The original test executable also differs from the older profile receipt and
has an mtime predating this candidate build; no immediately-pre-build independent
test hash was captured. The build log lists original app/test paths only as
outside-allowed-root stale warnings, not removed outputs. All five original
cached dependency source hashes match the earlier bounded-reader investigation.
Historic receipts were not edited.

Future builds must use **entirely fresh DerivedData** or explicitly fresh build
databases/output directories. Copying a package artifact cache is distinct
from copying an Xcode build database with absolute output paths.
