# Comparison retirement after XCTest completion

This continues the [origin-aware teardown investigation](../mpv-comparison-retirement-origins-20261017/README.md).
The previous delayed checkpoint remained inside the sustained async test method.
This continuation adds an opt-in observation in a separate, serial XCTest method,
requiring the source test's actual `testCaseDidFinish` callback first. Only XCTest
diagnostics and the runner change. Production teardown, MPVKit, shipping pins,
the default-off native provider and every existing acceptance gate remain unchanged.
Earlier native-fallback and memory rejections remain retained and unexplained.

## Accepted run and observations

The final arm64 Release build, deep/strict local signature verification,
**71 focused hosted tests** (zero failures/skips), **21 runner regressions** and
both serial sustained/post-test XCTest cases pass. The unchanged three-cycle
720/15 provenance workload covers **396 loupe windows**, **198 scope windows**,
**54 sampled difference publications** and **six fresh resumes**. Minimum cadence
is **58.90 presentations/sec**, maximum follower drift is **66.7 ms**, and
**11,876/11,880** clock samples are usable; every window meets the unchanged
29/30 usable-sample requirement. All 54 selections measure at least 11.81 seconds.
Cycle-end footprints are **858,852,448**, **925,699,288** and **986,697,040 bytes**;
maximum growth is **121.92 MiB** above warmup, below the unchanged 256 MiB limit.

[Statistics](stats.json), [focused summary](focused-summary.json),
[soak summary](soak-summary.json), [measurements](measurements.txt),
[candidate receipt](candidate-receipt.json), [execution input pins](execution-inputs.json)
and [validation input pins](validation-inputs.json) retain exact source, binary,
fixture and workload identities. Current/prepared Swift sources match, both app
and test executables are arm64 only, and verified dependency identities are unchanged.

All six observed hosts and every observed controller, scope worker, payload owner,
player wrapper and loupe surface retire before their originating cycle checkpoint.
This run therefore does **not reproduce the earlier detached-host survival** and
cannot explain its owning references or the earlier native-fallback/memory rejections.
The windows accumulate as the sole observed survivors: two, four and six at the
cycle checkpoints, with all six still alive at `final-delayed`.

All **180 observed identities** are dead at [post-test entry](memory-post-test-entry.json)
and remain dead [five seconds later](memory-post-test-delayed.json).
Window IDs **1, 31, 61, 91, 121 and 151** are first observed retired at
`post-test-entry`; no observed objects or relationships cross the test boundary
through diagnostic storage. The source completion callback uptime is
633090.9367080834; the post-test-entry uptime is 633090.9381502917, approximately
1.44 ms afterward and 170.09 ms after the preceding snapshot timestamp.
The snapshots bound observed retirement; they are not deallocation timestamps.
Physical footprint falls from 772,771,128 bytes at final-delayed to 234,490,592
at post-test entry and 116,984,544 at post-test delayed. These **post-gate** values
never replace the original memory-gate measurements or attribute the reduction
to particular objects, decoder handles, pools or caches.

The result establishes eventual retirement across this XCTest boundary for these
identities. It does not identify an autorelease/insertion stack or uniquely owning
reference. Allocation/insertion stacks or a controlled pool-lifetime experiment
remain needed for a causal pool claim; reproducing the prior detached-host
survivors is a separate unresolved requirement before selecting a production fix.
[Shared-host coordination](host-context.md) retains other Xcode activity and the
FTP Sync coordinator's reported brief optional compile. Its precise overlap and
impact are unproven. This remains shared-host evidence, not quiet-host acceptance.

## Method and limits

`--post-test-retirement` requires `--memory-diagnostics` with sustained comparison.
The original cycle samples still follow their one-second retirement allowance;
the original final-delayed snapshot still follows the final gate by at least five
seconds. Only after these snapshots and the source test's completion callback does
a second XCTest observe the same weak registry immediately and after another
five seconds. The registry retains weak object references, identity/origin scalars
and timestamps. The completion observer retains a locked timestamp, never the
XCTestCase. Cross-test storage carries no host, window, controller or workload
closure. The second test removes the observer and clears cross-test storage.

Both post-test snapshots omit relationship getters, including `NSApp.windows`,
which can themselves enqueue autoreleases. The runner requires the same PID,
cumulative IDs, immutable addresses/origins, consistent retirement history, the
actual completion uptime between the final workload snapshot and post-test entry,
and at least five seconds between post-test observations. Missing or reordered
tests, process relaunch, missing snapshots or a failed XCTest cannot qualify.
The diagnostic is explicit in both copied XCTest configuration and subprocess
environment; ordinary workloads clear inherited opt-ins.

A separate XCTest establishes observation after source test completion. It does
not establish which autorelease pools drained, isolate ARC ownership paths, prove
a production leak, or explain the earlier rejected runs. No pool is manually
drained, no framework dictionary is cleared and no production release behavior
changes. There is no concurrent external memory-graph collection in this run.
Physical footprint remains a cycle-end growth measurement, not a peak-memory or
total-memory bound. Generated looped UHD60 sources, 960×540 comparison canvas,
this host and 720-pixel/15-Hz scope settings retain their workload limits.

## Reproduce

`prepare.py` verifies the existing native bundle and scope delta and prepares
current app sources at `/private/tmp/aagedal-post-test-retirement-20261017/app`.
Build that copy for arm64 Release using the [native handoff](../../MPV_NATIVE_RASTER_HANDOFF.md),
then run `run-validation.py` from the source checkout. It pins both manifests,
app/test binaries and validation scripts, verifies the app signature, and runs
71 focused hosted tests followed by this serial workload:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance --memory-diagnostics \
  --post-test-retirement --scope-resolution 720 --scope-fps 15 \
  --soak-seconds 10 --soak-cycles 3
```

`run-diagnostic.py` records passive host-process snapshots once per minute.
`retain.py RUN_ROOT` checks source/binary/fixture identities and workload coverage,
then retains receipts, compressed logs and all seven memory checkpoints.
`summarize-retirement.py` derives identity/origin summaries without inferring
ownership or leaks. These local helpers retain the exact run paths.
