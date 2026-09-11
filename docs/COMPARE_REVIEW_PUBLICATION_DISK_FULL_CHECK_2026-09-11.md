# Review publication disk-full recovery — September 11, 2026

The existing bounded disk-image integration test now exercises production
exclusive relink and historical-timebase migration publication, in addition
to ordinary atomic edit/delete recovery.

Before exhaustion it saves a historical review with a large note, previews
relinking and constructs an exact-rate migration proposal. The large document
requires data allocation even on APFS with reserved metadata capacity. After
the bounded filler reaches ENOSPC, both publication paths must report an
out-of-space error. Neither destination may exist, no temporary files may
remain, and the original review, historical source and both media files must
remain byte-identical. After releasing the filler, the exact reviewed proposals
and destinations are retried. Both copies reopen successfully, preserve the
expected notes/document and leave the source unchanged.

The volume allowlists, canonical mount/device checks, token proof and size
limits are unchanged. Run with the existing harness:

```sh
AAGEDAL_DISK_FULL_FILESYSTEM=APFS scripts/test-compare-review-disk-full.sh --xctestrun /path/to/tests.xctestrun
AAGEDAL_DISK_FULL_FILESYSTEM=HFS+ scripts/test-compare-review-disk-full.sh --xctestrun /path/to/tests.xctestrun
```

The APFS integrated Release run passes **534 tests with zero failures and zero
skips**, including both official ITU sets, in 116.067 seconds (116.277 including
suite overhead). Evidence: `/tmp/aagedal-publication-recovery-apfs-20260911`,
including `Tests.xcresult`, `run.log`, `tests.json`, environment/volume records,
matching completion token and cleanup status. The harness detached and removed
its 128 MiB image. This run precedes the separate inspector safe-area correction;
the publication test and production store code are identical to the final change.

The final integrated HFS+ run passes **535 tests with zero failures and zero
skips**, including the added MPV/AVFoundation reload-transport regression and
both official ITU sets, in 117.892 seconds (118.113 including suite overhead).
The filler reached zero free/available blocks; all edit/delete/relink/migration
checks passed. The harness validated the completion token, detached the owned
32 MiB image and removed it. Evidence: `/tmp/aagedal-inspector-final-hfs-20260911`,
including `Tests.xcresult`, `run.log`, `tests.json`, `summary.json`, volume and
environment records, completion token and successful cleanup status.

This is real filesystem/store coverage. Native relink/migration/copy disk-full
interaction, broader permission-denied flows, keyboard traversal and spoken
VoiceOver remain separate acceptance work. No production store fix was needed.
