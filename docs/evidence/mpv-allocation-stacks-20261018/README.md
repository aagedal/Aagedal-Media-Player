# Post-gate allocation histories for comparison retirement

This continues the [native fallback and completed controls](../mpv-scope-failure-provenance-20261018/README.md).
It adds an opt-in allocation diagnostic to the XCTest/runner tooling. Production
teardown, capture behavior, MPVKit, shipping package pins and the provider's
default-off gate are unchanged.

## Retained result

The arm64 Release build, deep/strict signature verification, **76 focused hosted
checks** (zero failures/skips), **24 runner regressions** and **14 collector
regressions** pass. The independent instrumented process passes both sustained
comparison and subsequent observer tests, strict runner acceptance and all six
allocation queries. [Statistics](stats.json), [XCTest summary](soak-summary.json),
[collector receipt](allocation-stacks/receipt.json) and
[source/binary receipt](candidate-receipt.json) retain the separate evidence.

The unchanged three-cycle 720/15 provenance workload covers **396 loupe windows**,
**198 scope windows**, **54 sampled difference publications**, **six fresh
resumes** and all 54 scope selections for at least **11.96 measured seconds**.
Minimum cadence is **58.71 presentations/sec**, maximum drift **66.7 ms**, and
**11,878/11,880** clock samples are usable; every window meets 29/30.
Cycle-end footprints are **696,454,240**, **804,555,848** and **864,111,736 bytes**:
maximum growth **167,657,496 bytes (159.89 MiB)** is below the original 256 MiB
limit. These are instrumented, cycle-end observations, not peak memory or a
controlled explanation of earlier rejected workloads.

Only two/four/six window identities survive the cycle checkpoints; all other
tracked payload identities are dead. The same six windows remain at final-delayed.
Each report contains one matching **640-byte allocation** through
`+[NSWindow(PreviewAllocator) allocWithZone:]` and
`LiveLoupeSessionTests.qualifyComparison`, resolving to the fixture's `NSWindow`
construction at `LiveLoupeSessionTests.swift:665`. No `FREE` record is printed
in those reports. This identifies the allocation path for the queried addresses;
it does not identify current retainers, autorelease insertion, total retained
window graphs, or the cause of memory growth. The XCTest/AppKit/SwiftUI frames
farther down these allocation stacks are execution context, not owning paths.

All **180 tracked identities** are dead at post-test entry and five seconds later.
The post-gate collector wait affects this test-boundary observation and cannot
establish a particular pool drain. Final-delayed/post-entry/post-delayed footprints
are **659,983,456**, **650,955,872** and **592,612,448 bytes**; none replaces a gate
sample. Earlier detached-host survival is not reproduced or explained.

Passive before/after [process snapshots](host-processes.txt.gz) show other Xcode
activity; they are not continuous monitoring or quiet-host qualification. Runtime
runner/collector and app/test sources match their execution pins. Runner regression
assertions were extended afterward to cover collector nonzero exits/timeouts;
`initial-runner-regressions-source.py.gz` matches the original regression-source
pin, and separately hashed final regression logs cover the final assertions.
No production fix or native failure-stage attribution is established.

## Diagnostic contract

`--allocation-stacks` requires `--memory-diagnostics` and sustained comparison.
Only the copied XCTest host environment enables `MallocStackLogging=1` and
`MallocStackLoggingNoCompact=1`. Ordinary runs clear those keys, their directory
override and the new handshake flag from both configuration and inherited process
environments. Neither xcodebuild nor the collector inherits stack logging from
the runner. The original xctestrun remains unchanged.

After all original one-second cycle gates and the separate five-second final
snapshot, XCTest atomically writes `allocation-request.json` and awaits external
completion for at most 600 seconds. It never promotes weak objects while waiting.
The collector reads the exact `final-delayed.json`, validates PID and identities,
and checks the current executable name before each bounded malloc-history query.
It collects at most 32 live identities within a 500-second aggregate budget,
retaining process-check results and each raw stdout/stderr/status/timeout. A
successful query requires an `ALLOC` record matching or containing the requested
address, not just exit status zero. The receipt hashes its request, snapshot and
raw reports. Retention compresses these byte-for-byte and records their original
filenames/hashes in `allocation-stacks/report-archives.json`. Empty survivor sets explicitly report no allocation evidence.

The runner starts one collector, reaps it on completion or early workload failure,
and requires both ordinary workload acceptance and collector success/handshake
receipt. A collection failure cannot qualify the workload. No pool drain, cache
purge, debugger stop or longer allowance changes an original cycle gate.

Logging runs throughout the workload and changes its allocation/timing conditions.
The external collection wait changes later test-boundary retirement timing; those
samples cannot be directly compared to uninstrumented observations as a causal
experiment. The request snapshot records prior weak survival, not a live-reference
hold. Objects can retire and addresses can be reused before inspection; the raw
allocation/free history must be examined before attributing a record to an identity.
Allocation stacks identify allocation paths, not retaining references or autorelease
insertion stacks. No memory-growth cause follows from these reports alone.

## Reproduce

`prepare.py` verifies the restored baseline, scope delta and complete existing
MPVKit package, then prepares current sources without rebuilding the dependency.
Build arm64 Release for testing using the [handoff](../../MPV_NATIVE_RASTER_HANDOFF.md)
and the local paths in the retained build log, then run `run-validation.py`.
The focused check includes the new failure/PID/timeout handshake contract. The
instrumented command is:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance --memory-diagnostics \
  --scalar-memory-diagnostics --allocation-stacks --post-test-retirement \
  --scope-resolution 720 --scope-fps 15 --soak-seconds 10 --soak-cycles 3
```

`malloc_history` requires permission to inspect the test process. This environment's
sandbox rejects a short-lived allocation probe with `mach port for process 0 not
valid`; the same probe outside the sandbox successfully returns its allocation
and `main` stack. Xcode also requires access to its standard package caches and
signing/test services; the retained sandbox build rejection is not a source
compile rejection. Run the validation from an appropriately permitted session.
`retain.py` archives actual logs, outcomes and source/binary hashes, including
rejected results. Printed acceptance markers cannot override a failed XCTest.

Generated UHD60 media, the 960×540 comparison canvas, independent decoder clocks,
sampled provenance, uninstrumented MPVKit, peak/GPU memory and physical HDR retain
their prior qualification limits. Native command stage/state diagnosis, ownership
and autorelease insertion evidence, earlier rejected results and coordinated
quiet-host repeatability remain open.
