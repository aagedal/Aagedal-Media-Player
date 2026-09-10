# Compare review APFS disk-full check — 2026-09-10

The production sidecar store passed real out-of-space save/delete preservation
and recovery on a disposable APFS image, extending the earlier HFS+ coverage.
This is store integration coverage; native disk-full alerts, retained popover
edits and user-driven retry on APFS remain separate acceptance work.

## Bounded fixture

`scripts/test-compare-review-disk-full.sh` accepts
`AAGEDAL_DISK_FULL_FILESYSTEM=APFS` for a 128 MiB image. The default remains a
32 MiB HFS+ image. Both the shell harness and XCTest verify the selected
filesystem and capacity; XCTest also verifies the canonical owned temporary
mount path, device and per-run UUID token before filling anything. Maximum
filler writes are fixed at 136 MiB for APFS and 40 MiB for HFS+. Unsupported
filesystem selections fail before creating artifacts or a mount. Neither
fixture fills a user volume or the host volume.

The harness passes filesystem selection through both direct test runs and its
copied `.xctestrun` manifest. The original manifest remains unchanged. Direct
build-and-test runs enable testability, including Release configurations.
Completion requires both XCTest success and a matching proof token; skipped
or absent tests cannot count as acceptance. Cleanup detaches the image and
removes its temporary directory.

## Verified results

Release tests were built with Xcode 26.6 (17F113) on macOS 27.0 (26A428), arm64,
using `ENABLE_TESTABILITY=YES`. The same built test bundle exercised both
filesystem choices, with parallel testing disabled.

| Fixture | Test result | Reported capacity | Available blocks at ENOSPC | Available blocks after filler removal |
| --- | --- | --- | --- | --- |
| APFS, 128 MiB image | 1 passed, 0 failures, 0 skips; 0.205 s | 134,176,768 bytes | 784 | 32,409 |
| HFS+, 32 MiB image | 1 passed, 0 failures, 0 skips; 0.200 s | 33,513,472 bytes | 0 | 7,987 |

Block size was 4,096 bytes. APFS retained reported free blocks while returning
actual ENOSPC; acceptance depends on the write errors and preservation/recovery
assertions, not a zero-free-block assumption.

For both filesystems the bounded filler reached POSIX ENOSPC. Production atomic
replacement and atomic note deletion then failed with out-of-space errors,
leaving the original sidecar bytes and source media intact and leaving no
partial sidecar files. Truncating and synchronizing the owned filler restored
space. A valid revision 2 save succeeded after failed revision 99, and deleting
the note subsequently succeeded and persisted. Both runs verified the proof
token, exited 0, detached their image and removed their fixture directory.

Evidence is retained locally in:

- `/private/tmp/aagedal-apfs-focused-20260910/`
- `/private/tmp/aagedal-hfs-focused-20260910/`

Each contains `Tests.xcresult`, `run.log`, `tests.json`, `volume.plist`,
`environment.txt`, `TestRun.xctestrun`, `verified-token.txt` and `status.txt`.
The environment records include source SHA-256 values and the working-tree
state. The Release build log is `/private/tmp/aagedal-apfs-build.log`.

## Reproduction

```sh
AAGEDAL_DISK_FULL_FILESYSTEM=APFS \
  scripts/test-compare-review-disk-full.sh -configuration Release

# Reuse a build without modifying its manifest:
AAGEDAL_DISK_FULL_FILESYSTEM=APFS \
  scripts/test-compare-review-disk-full.sh --xctestrun /path/to/tests.xctestrun
```

Omit the filesystem environment variable to recheck HFS+. The focused checks do
not replace the integrated full suite or native interaction acceptance.
