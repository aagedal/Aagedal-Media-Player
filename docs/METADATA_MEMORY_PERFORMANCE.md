# Metadata memory investigation

The loudness baseline's parent-process spike originates in the resolved
SwiftMediaMetadata 3.0.0 dependency (`c2d77c2dcefcb997623e52beca57bc61ce302cb9`).
`MP4Parser.parse` always asks `RTMDReader.hasRTMDTrack` whether the clip contains
Sony timed metadata. That probe calls `topLevelBox`, which uses the generic
`ISOBMFFBoxReader.parseBoxes(from: fullData)`. Unlike the main MP4 parser, this
second walk reads every `mdat` payload through `BinaryReader.readBytes`.
Consequently ordinary MP4/M4A clips without RTMD also pay for materializing their
media payload. Mapping retention alone was an incomplete explanation.

An isolated probe linked against the existing Release dependency reproduced this:
for the eight-hour ALAC fixture, mapping raised RSS only from 7.4 to 7.6 MiB;
`RTMDReader.hasRTMDTrack` returned `false` but raised RSS to about 4,437 MiB.
Reading four bytes through `BinaryReader` before this call stayed below 8 MiB.
The complete MP4 parser reached about 4,440 MiB. These are phase observations,
not sampled allocation stacks; they isolate the costly call and its source path.
RSS includes resident mapped pages as well as allocations, so these numbers do
not by themselves identify the heap-versus-file-backed breakdown.

## Reproduce and evaluate the candidate dependency patch

```bash
python3 scripts/profile-metadata-memory.py \
  /path/to/SourcePackages/checkouts/SwiftMediaMetadata \
  /tmp/new-metadata-profile \
  /path/to/1h-5.1.m4a /path/to/8h-5.1.m4a
```

The source checkout must be clean and at the exact revision above. The output
directory must not exist. The harness copies only the dependency library sources
and zlib module into two temporary Swift packages, then builds in Release with
the local Swift toolchain. It does not resolve remote packages, change the app's
package pin, or edit the source checkout. Each build/workload has a 30-minute
timeout. Allow several minutes for two full library compilations and enough disk
space for their builds plus the existing fixtures. Fixture generation is described
in [the loudness profile](AUDIO_LOUDNESS_PERFORMANCE.md).

The `baseline` package is unchanged. The `fixed` package applies
[the candidate patch](dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch),
replacing the generic top-level read in `RTMDReader.topLevelBox` with the existing
`parseTopLevelBoxesSkippingMdat`. This leaves the original full buffer available
for later RTMD sample reads using absolute file offsets. It does not remove the
normal `VideoMetadata.read(from:)` postprocessing or change source-data retention.
The patch is for review/upstream integration; it is not applied to production.

Every input/variant/mode gets a fresh process:

- `read`: normal synchronous `VideoMetadata.read(from:)`, retained-result RSS,
  selected metadata snapshot, then result/autorelease-pool release.
- `rtmd`: explicit mapping, the isolated public RTMD presence probe, release.
- `skip-mdat`: explicit mapping and the existing skip-mdat box walker as a control.

Each phase reports current `mach_task_basic_info.resident_size` and Darwin
`getrusage.ru_maxrss` (both bytes). The latter captures process-lifetime peak RSS,
including transient peaks between phases. It includes startup/runtime costs;
there is no periodic sampler and no attempt to partition dirty, clean, compressed,
or mapped memory. Current RSS can remain elevated after release due to allocator
and VM behavior. The standalone process excludes app model conversion, AVAsset,
playback, and concurrent jobs. It demonstrates this dependency path's cost, not
full-app bounded memory.

Artifacts include environment information, exact source revision, input sizes and
SHA-256 hashes (including the probe, harness, and patch), build and patch logs,
phase JSONL, and `summary.json`. Successful
completion requires the expected phase sequence, positive memory measurements,
equal baseline/fixed metadata snapshots, equal RTMD presence results, and equal
skip-mdat box types/payload byte counts. Snapshot parity covers container
format/duration/size/bitrate/title/comment; video/subtitle/chapter counts; RTMD
presence; and audio codec/rate/channels/depth/duration/bitrate/layout. It does not
compare every dependency metadata field.

## Local result — 2026-09-07

The final isolated paired run passed all phase and parity checks on macOS 27.0
(26A5425a), Xcode 26.6 (17F113), using the same 1h/8h 48 kHz six-channel ALAC
fixtures as the loudness baseline. Input sizes were 289,992,446 and 2,319,934,602
bytes. The optional hardware `sysctl` probe was denied by the execution sandbox;
its failure is recorded in `environment.json`. No measurement needed that probe.

| Input | Workload | Baseline peak RSS | Patched peak RSS |
| --- | --- | ---: | ---: |
| 1 hour | Normal metadata read | 564.02 MiB | 11.19 MiB |
| 1 hour | RTMD presence probe | 562.34 MiB | 9.56 MiB |
| 1 hour | Skip-mdat control | 9.03 MiB | 8.98 MiB |
| 8 hours | Normal metadata read | 4,447.41 MiB | 19.64 MiB |
| 8 hours | RTMD presence probe | 4,437.80 MiB | 15.58 MiB |
| 8 hours | Skip-mdat control | 11.41 MiB | 11.38 MiB |

Normal read wall times were 0.0513/0.3620 seconds baseline and 0.0052/0.0159
seconds patched for 1h/8h respectively. These are single observations without
cache flushing or thermal control; they are diagnostic, not a throughput claim.
An earlier paired run also passed metadata snapshot parity and showed normal-read
peaks of 563.92/4,441.80 MiB baseline and 12.16/19.66 MiB patched. Its harness
predated the final probe/control parity and artifact-hash checks.

Both RTMD probes returned false. All selected metadata fields matched: ALAC,
48 kHz, six channels, 16-bit, 5.1 layout and 3,600/28,800-second duration. The
skip-mdat control returned `ftyp`, `free`, empty `mdat`, and `moov`; eight-hour
retained box payload totaled only 1,430,890 bytes. Remaining growth between 1h
and 8h is consistent with metadata/sample-table scaling and is not a proof of a
fixed bound. The full-media payload spike is eliminated in this isolated
candidate; the shipping app still uses the unpatched dependency.

Raw final artifacts: `/tmp/aagedal-metadata-memory-20260907-c` (earlier paired
run: `-b`). Temporary artifacts can be removed by the OS; the recipe, patch,
revision, and result table are the durable record.

## Acceptance still required

The synthetic ALAC files have no video or RTMD track. They establish the negative
probe regression and audio metadata parity only. Before a dependency release is
integrated, run its tests and verify real Sony RTMD clips, IMU rate and first-frame
snapshot parity, absolute sample offsets, leading/trailing `moov`, extended-size
and zero-size atoms, malformed/truncated boxes, and representative raw formats.
The [synthetic container validation](METADATA_CONTAINER_VALIDATION.md) now checks
leading/trailing `moov`, absolute `stco`/`co64` sample offsets, extended/zero-size
atoms, and selected malformed/truncated cases through public RTMD APIs. These
fixtures supplement the real-content acceptance above; upstream tests must still
check intended error semantics and broader format compatibility.

After integrating a reviewed dependency release, repeat the isolated profile and
full app metadata/loudness workload, including app-model conversion and release.
The app-wide bounded-memory gate and representative hardware/content acceptance
remain open until those checks pass.
