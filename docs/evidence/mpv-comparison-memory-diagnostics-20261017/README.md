# Matched comparison teardown memory diagnostics

This continues the explicit diagnostic step from the
[rejected 720/15 run](../mpv-comparison-provenance-720-20261017/README.md).
The candidate adds opt-in observation; it does not change capture retirement,
decoder teardown, scope scheduling, dependency binaries or acceptance gates.
Shipping pins and the native provider's default-off gate remain unchanged.

## Accepted diagnostic run

The final arm64 Release build, deep/strict local signature verification,
**70 hosted tests** (zero failures/skips) and **16 runner regressions** pass.
The three-cycle 720/15 provenance soak also passes all unchanged gates:
**396 loupe windows**, **198 scope windows**, **54 sampled difference publications**
and **six fresh resumes**. All 54 selection groups measure at least 11.81 seconds.
Minimum cadence is **58.82 presentations/sec**, maximum follower drift is
**66.7 ms**, and 11,877/11,880 clock samples are usable; every window meets its
29/30 gate. Each sampled difference covers 291,600 pixels and occupied-bin sets.

Cycle-end footprints are **699,059,248**, **656,526,552** and **946,048,312 bytes**.
Maximum growth is **235.55 MiB** above warmup, below the unchanged 256 MiB limit.
This passing repeat does not explain or supersede the earlier 309.91 MiB memory
rejection or the earlier native-fallback rejection. It has only 20.45 MiB of
headroom against this workload's growth gate and is not a deterministic bound.

[Statistics](stats.json), [successful XCTest summary](soak-summary.json),
[measurements](measurements.txt), compressed action/build/stdout logs and executed
configurations retain the result. The [candidate receipt](candidate-receipt.json)
pins current/prepared Swift source sets, arm64 executables, unchanged dependency
binaries/descriptors, fixtures and validation scripts. Pre-run
[execution inputs](execution-inputs.json) remain unchanged after validation.
The initial compile error in the probe's actor annotation is retained in
`build.log.gz`; `build-final.log.gz` records the corrected passing build.

## Retirement findings and remaining diagnosis

The [first](memory-cycle-1.json), [second](memory-cycle-2.json) and
[third](memory-cycle-3.json) cycle files establish matched one-second teardown
observations. All observed payload owners retire after cycle one, except two
closed windows. At cycles two and three, one object in each host, controller, capture and
scope-worker category remains alive, with two loupe sessions/surfaces/layers
and one primary and secondary player wrapper. Aggregate counts do not establish
that those objects belong to the same pair or connected graph. All observed follower player wrappers retire in every
cycle. Closed window objects accumulate to two, four and six. These are object
lifetime observations, not evidence that native decoder handles remain active.
Counts alone cannot tell whether the same objects survive across cycles.

Graphics footprint is 199.20, 31.97 and 192.53 MiB; internal memory is 1441.25,
1507.55 and 1536.33 MiB; reusable memory is 363.09, 431.84 and 440.20 MiB;
purgeable nonvolatile memory is 44.11, 105.50 and 160.77 MiB. Compressed and media
footprint counters are zero at these checkpoints. The non-monotonic graphics
ledger and growth in other counters do not isolate a causal allocation class.
The lower second-cycle footprint despite surviving app objects also prevents a
simple equivalence between object survival and physical footprint.

No causal production fix is established. Next distinguish originating pair/cycle
and delayed retirement for the surviving objects, record scalar window state and
obtain reference paths/allocation stacks before changing teardown or caches.
In particular, do not change Swift/ARC window release behavior merely because
closed windows survive. Those diagnostics should remain separate from the
unchanged one-second memory gate. A coordinated quiet-host repeat also remains
open. [Minute-by-minute host snapshots](host-processes.txt.gz) show unrelated FTP
Sync UI tests and other Xcode activity during this run; no competing Media Player
benchmark is observed. Snapshots cannot reserve the host or prove inactivity
between samples. The local app/results remain under
`/private/tmp/aagedal-memory-diagnostics-20261017`.

## Diagnostic method

`--memory-diagnostics` is supported only with sustained comparison. The runner
sets a process-local output directory and removes inherited diagnostic settings
from both environment sources. On successful acceptance it also requires the
baseline and every cycle's JSON file, with one consistent process identity.
Missing diagnostics cannot qualify an older test binary. Failed XCTest still
rejects the run regardless of printed end markers or complete diagnostic files.

The test records a pre-workload baseline and matched `TASK_VM_INFO` samples at
each cycle end, after the existing one-second retirement allowance. The ordinary
footprint gate is sampled first and retained separately in the JSON; the following
VM-category snapshot can differ slightly. Counters include resident, internal,
external, compressed, reusable, device, purgeable, media and graphics ledgers.
These categories overlap and cannot be added to reconstruct physical footprint.
They are process accounting observations, not allocation backtraces, GPU totals
or proof of a leak's cause.

The registry holds only weak references, deduplicates live identities and keeps
scalar counts for retired identities. It observes windows, hosting views,
controllers, loupe state/captures, scope captures/probes/workers, and observed
loupe surfaces/layers/sessions/decoder wrappers. Surface observations occur at
existing readiness/mode/reopen points and in the existing clock sampling loop;
they do not instrument every transient allocation. Counts accumulate across
cycles. A zero alive count establishes retirement of the observed app objects,
not release of all native allocations or process-wide framework/driver caches.
The optional scope-worker hook is nil in ordinary app use.

No extra retirement wait, forced autorelease-pool drain, cache purge, gate change
or MPVKit rebuild is introduced. Recording diagnostics has a small observational
cost and does not establish a deterministic memory or drift guarantee.

## Reproduce

Prepare the verified native-raster baseline and scope delta using `prepare.py`,
then build current sources for testing in arm64 Release as described in the
[native handoff](../../MPV_NATIVE_RASTER_HANDOFF.md). The helper's absolute paths
identify this retained local run. Run:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance --memory-diagnostics \
  --scope-resolution 720 --scope-fps 15 --soak-seconds 10 --soak-cycles 3
```

Keep the earlier native-fallback and memory rejections. A subsequent passing run
cannot explain their causes. The generated UHD60 media, 960×540 canvas, selected
settings and host remain workload limits. Input timestamps remain estimates;
pixel/bin correctness samples completed publications rather than every output.
Frame lock, physical HDR calibration, native-dependency sanitizer coverage and
producer-authentic long media remain separate work.
