# Scalar-only comparison retirement control

This continues the [post-test retirement investigation](../mpv-comparison-post-test-retirement-20261017/README.md).
The new opt-in `--scalar-memory-diagnostics` omits the complete relationship-getter
bundle from baseline, cycle-end and final-delayed snapshots. Weak identities,
origins, addresses, retirement history, VM ledgers and counts remain observed.
Post-test observations already omit these getters and keep their original method.
The control does not drain a pool or change production teardown, dependencies,
shipping pins, the default-off native provider or any workload acceptance gate.

The experiment removes getters including `NSApp.windows`, window/controller/view
relationships and hosting-view root state. Weak promotion/count reads remain
observations. A difference between runs cannot identify a particular getter,
autorelease insertion stack, owning path or production leak. A synchronous pool
created after the gate cannot drain pre-existing outer autoreleases; no pool token
is held across an async suspension.

## Verification and retained attempts

The final arm64 Release build and deep/strict signature verification pass.
All **23 runner regressions** pass. The first focused run passes 71 tests and fails
one comparison clock sample at `0.10000000000000009 > 0.1` seconds. Its unchanged
same-build repeat passes **72 hosted tests**, with zero failures/skips and all
20 native raster fixture cases. The [initial rejection](focused-rejected/summary.json)
and compressed action/test logs are retained; the clock threshold is unchanged.
Initial sandboxed build attempts failed on network/cache access; the successful
build uses the existing package checkout, disables updates and uses Xcode's
required caches. MPVKit is reused, never rebuilt.

The same-build relationship-snapshot workload then stops in cycle two at an A/B
native-plot unwrap: the selected latest sample has no native plots. It records
164 loupe windows before interruption. The subsequent observer test also rejects
because the sustained source failed before publishing its cross-test context.
Its [summary](relationship-control/summary.json), logs, executed configuration,
command and available baseline/cycle-one diagnostics are retained. It does not
qualify sustained acceptance or post-test retirement. This reproduces a previously
retained class of native-fallback rejection; no cause is established.

At the relationship run's cycle-one checkpoint, two closed windows, one host
and other observed identities with the same PQ/HLG origin survive. At the scalar run's cycle-one
checkpoint, only two windows survive. Each process has its own identity registry;
these are analogous categories, not the same objects observed across processes.
Closed-window survival still occurs without relationship getters, so those getters
are not necessary for that observed survival in this workload. This is a partial comparison under variable
shared-host conditions, not a completed paired causal experiment. Earlier memory,
native-fallback and detached-host results remain retained and unexplained.

## Completed scalar workload

The scalar-only workload and subsequent observer test both pass: **396 loupe
windows**, **198 scope windows**, **54 sampled difference publications** and
**six fresh resumes** across all 54 selections. Minimum cadence is **58.85
presentations/sec**, maximum drift **66.7 ms**, and **11,877/11,880** clock samples
are usable; every window meets the unchanged 29/30 requirement. Each selection
measures at least **11.67 seconds**. Cycle-end gate footprints are **933,235,976**,
**695,209,008** and **709,954,704 bytes**, with **zero maximum growth** above warmup
(limit 256 MiB). The scalar result is accepted; the overall two-control launcher
correctly returns failure because the relationship control rejects.

Only two, four and six windows remain alive at the scalar cycle checkpoints.
All six persist at final-delayed. All **180 identities** are dead at post-test
entry and remain dead five seconds later. Source-test completion uptime is
640564.5913875834 and post-test entry is 640564.5929318334, about 1.54 ms afterward.
These are observation bounds, not deallocation timestamps. Post-test footprint
values **208,587,440** and **116,066,992 bytes** never replace gate samples.
Closed windows therefore still survive in-test without the getter bundle. Host
survival is not reproduced in the completed scalar run; the interrupted
relationship run prevents a complete matched comparison. No autorelease cause,
connected ownership graph or production fix is established.

[Statistics](stats.json), [focused summary](focused-summary.json),
[scalar summary](soak-summary.json), [retirement summary](retirement-summary.json),
[measurements](measurements.txt), [candidate receipt](candidate-receipt.json),
[execution pins](execution-inputs.json) and [validation pins](validation-inputs.json)
retain exact source, arm64 binary, fixture and workload identities. Prepared and
current Swift sources match. [Host context](host-context.md) records competing
Xcode activity; this is not quiet-host qualification. A coordinated complete
same-build comparison, native-fallback failure-reason diagnostics and owning or
allocation/insertion stacks remain next. Earlier rejections remain unexplained.

## Reproduce

`prepare.py` verifies the pinned native bundle, scope delta and complete local
package, then prepares current sources at
`/private/tmp/aagedal-scalar-retirement-20261017/app`. Build for arm64 Release
using the [handoff](../../MPV_NATIVE_RASTER_HANDOFF.md). `run-validation.py` pins
inputs/scripts and binaries, verifies signatures, runs focused tests, then starts
the relationship control and scalar control serially in fresh processes even if
the first control rejects. `run-diagnostic.py --relationships` selects the
relationship control; omitting that argument selects scalar-only diagnostics.
Each run records passive once-a-minute host process snapshots.

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance --memory-diagnostics \
  --post-test-retirement --scalar-memory-diagnostics \
  --scope-resolution 720 --scope-fps 15 --soak-seconds 10 --soak-cycles 3
```

Omit `--scalar-memory-diagnostics` for the relationship control. It requires
`--memory-diagnostics`, which requires sustained comparison. Ordinary runs clear
inherited opt-ins from both process and copied XCTest environments. Every snapshot
records its observation mode; the runner rejects mismatched modes and any extra
fields in scalar rows. Original cycle samples keep their one-second allowance;
final-delayed and post-test-delayed retain their separate five-second delays.
The source completion callback, same PID and cumulative identity history are
required for post-test receipts. Footprint gates are sampled before snapshots.

`retain.py` retains a **complete** scalar workload (optionally `--rejected` for a
completed failed source test); `retain-control.py` handles a complete relationship
control. The interrupted relationship run above was retained separately without
fabricating missing checkpoints. Generated looped UHD60 sources, 960×540 canvas,
this host and 720/15 settings retain their workload limits. Physical footprint is
cycle-end growth, not peak/GPU memory or a total-memory ceiling. Producer-authentic
media, native dependency sanitizers, frame lock and physical HDR remain open.
