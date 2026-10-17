# Comparison object origins and delayed retirement

This continues the explicit next step in the
[matched teardown diagnostics](../mpv-comparison-memory-diagnostics-20261017/README.md).
Only XCTest diagnostics and their runner change. Production teardown, capture
scheduling, MPVKit binaries, shipping package pins and the native provider's
default-off gate remain unchanged. The earlier native-fallback and memory
rejections remain retained and unexplained.

## Accepted candidate and observations

The final arm64 Release build, deep/strict local signature verification,
**71 focused hosted tests** (zero failures/skips) and **19 runner regressions**
pass. The full three-cycle 720/15 provenance soak passes all unchanged gates:
**396 loupe windows**, **198 scope windows**, **54 sampled difference
publications**, **six fresh resumes**, at least **58.91 presentations/sec** and
at most **83.3 ms** follower drift. All **11,880/11,880** clock samples are usable.
All 54 measured scope selections run for at least 11.82 seconds.

Cycle-end footprints are **978,848,864**, **807,357,464** and **1,067,896,024 bytes**.
Maximum growth is **84.92 MiB** above warmup, below the unchanged 256 MiB limit.
This passing shared-host repeat does not explain or supersede either earlier
rejection. Other Xcode activity appears in retained host snapshots; those
snapshots do not reserve the host or establish quiet-host acceptance.

[Statistics](stats.json), [XCTest summary](soak-summary.json),
[measurements](measurements.txt), [candidate receipt](candidate-receipt.json),
[pre-run executable/manifest pins](execution-inputs.json) and
[validation input pins](validation-inputs.json) retain the exact result.
Current and prepared Swift file sets match. App and XCTest executables are
arm64 only; verified dependency/fixture identities remain unchanged.

[Object summaries](retirement-summary.json) establish that the surviving
cycle-one host **41** comes from the final PQ/HLG pair. It remains alive at the
cycle-two checkpoint (263.02 seconds after its teardown), cycle three
(525.09 seconds) and the delayed checkpoint (530.14 seconds). Both cycle-two
hosts retire by its checkpoint. Cycle-three hosts **131** and **161** also survive
the final delayed observation, respectively 135.91 and 6.09 seconds after their
teardown. No observed object retires between the final gate and delayed snapshot.
These are bounds on observed survival, not eventual-retirement measurements.

The surviving hosts have no window, superview or registered next responder.
Their scalar root links identify their own controllers/captures/state/probes.
Surviving controllers and loupe sessions report no current player, and all
observed follower wrappers retire. Six closed windows remain listed in
`NSApp.windows`; each is invisible, with no content view, delegate, window
controller, content-view controller, children or sheets. This does not establish
an active decoder handle, nor that closed windows own the detached host graphs.

A **7.14 MiB post-gate memory graph** was captured successfully. Its
[receipt](reference-graph-receipt.json) pins the local graph and all compressed
reference reports, reproduced offline by `collect-reference-reports.py`. The
graph itself remains at the receipt's local path; text
reports for all three hosts and six windows are retained here. Host 41 has a
direct scanner-labelled `__strong` autorelease-pool entry with a path to the
XCTest wait stack. All three surviving hosts have direct scanner-labelled strong
dictionary-value
references from AppKit `previousKeyViews` and `_MergedGlobals.85`; other paths
include SwiftUI view/attribute graphs and notifications. Window reports also
include direct
autorelease-pool entries. These narrow the next investigation to framework/test
pool lifetime and AppKit/SwiftUI reference state, without proving a unique
owning root or a production leak.

The scanner also reports paths through `RetirementProbe.Entry` weak storage.
Those are **not strong ownership evidence**: the source holds weak references,
and focused lifetime tests confirm that the probe/snapshot does not retain its
observed object. The scanner's root count therefore cannot be interpreted as a
count of retaining owners. The paths through SwiftUI `WeakBox` storage are also
weak. In particular,
weak paths through host 41 and the probe do not establish autorelease-pool
ownership of hosts 131 or 161. Allocation stacks were not collected. Next obtain
autorelease/insertion stacks or an isolated post-test/pool-boundary
observation for these identities before selecting a production fix. Do not drain
pools, clear framework dictionaries or change ARC window-release behavior inside
the existing acceptance workload to make its gate pass. Also distinguish window
autoreleases caused by diagnostic `NSApp.windows` getters from those caused by
the workload: this graph cannot assign pending-release entries to their source.

An earlier candidate passed the initial 71 focused tests, then its sustained run
was deliberately interrupted before the first cycle checkpoint to correct a
snapshot consistency race. A weak object could retire between two reads,
producing contradictory row fields. The final snapshot promotes each weak
reference once for its row, retaining only scalar results. Compressed partial
logs/configuration and the intermediate build log are retained with
`partial-` / `before-snapshot-fix` names; they are not acceptance evidence.
The corrected binary was rebuilt and reran both focused and full sustained
validation. No dependency or production teardown change was needed.

## Method

Each weak entry now carries a stable, monotonically assigned ID, originating
cycle/pair, first-observed uptime, scalar address and originating teardown uptime.
The first checkpoint observing retirement remains recorded. IDs distinguish
address reuse and preserve identity across later cycle checkpoints; addresses
alone do not. The registry retains no observed objects.

Snapshots record actual scalar host/controller/session/view relationships and
window visibility, key/main status, application-window membership, content-view
and controller state, responder class and parent/child/sheet state. A null
relationship ID can mean an unregistered object, rather than no relationship;
explicit presence flags and class fields distinguish selected window cases.
These getter observations do not prove which references own their targets or
identify an external retaining root.

All original cycle-end gate samples still follow exactly the existing one-second
retirement allowance. A separate `final-delayed.json` snapshot occurs at least
five seconds after the final gate sample, without any further workload. Its gate
footprint is null and its VM footprint never substitutes for a gate measurement.
The runner requires schema 2, every cycle and delayed checkpoint, consistent
process identity, cumulative stable object IDs/origins, monotonic checkpoint
uptimes and retirement history. Later callbacks may register new IDs after their
origin's teardown; that observation is preserved rather than rejected.

The independent review found that a retained `NSHostingView` naturally owns the
comparison root's controllers/state/captures and scope subtree. MPV property and
comparison drift tasks also promote weak references across async suspension;
cancellation does not itself establish immediate task completion. These are
candidate paths, not causal findings. This test does not mount the ordinary
`ContentView` window coordinator paths, and its comparison objects do not enter
the XCTest's stored window/controller arrays.

`run-diagnostic.py` records host process snapshots once a minute. After the final
cycle JSON has been atomically written (all performance/memory gates complete),
it attempts `leaks --forkCorpse --outputGraph` for the recorded PID. The graph is
an additional post-gate diagnostic, separate from the acceptance snapshots. It
can affect later retirement timing; delayed observations must be read with that
qualification. Malloc stack logging is not enabled, so allocation stacks are not
established by this run. A reference scanner's paths are not proof of ownership.

## Reproduce

Prepare the existing checksummed native candidate and scope delta with
`prepare.py`, then build current sources for arm64 Release using the
[native handoff](../../MPV_NATIVE_RASTER_HANDOFF.md). The helpers retain absolute
paths for this local run under `/private/tmp/aagedal-retirement-origins-20261017`.
`run-focused.py` accepts xctestrun, native manifest, generated media directory,
scope fixture directory, UHD60 manifest and a new output directory.

The sustained workload remains:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance --memory-diagnostics \
  --scope-resolution 720 --scope-fps 15 --soak-seconds 10 --soak-cycles 3
```

Use the evidence's `run-diagnostic.py` instead for the additional post-gate graph
attempt and passive host snapshots. `summarize-retirement.py` derives the scalar
origin/identity summary from retained JSON without inferring ownership or leaks.
Generated looped UHD60 media, this host, the 960×540 canvas and selected scope
settings remain workload limits. Physical HDR calibration, native-dependency
sanitizers, peak-memory bounds and quiet-host qualification remain separate work.
