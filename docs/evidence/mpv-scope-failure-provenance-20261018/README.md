# Native-scope fallback failure provenance

This continues the [scalar retirement control](../mpv-comparison-scalar-retirement-20261017/README.md),
whose relationship workload stopped at an A/B sample without native plots.
The app now carries a scalar failure reason from the native request through its
matching screenshot completion into the atomically published scope sample.
Capture selection, scheduling, generation/player stale-result guards, capability
cache policy and every qualification gate remain unchanged. MPVKit is reused;
shipping pins and the default-off raster provider are unchanged.

## Diagnostic contract

`MPVPlayer.nativeScopePlotsResult` distinguishes explicit screenshot override,
invalid width, missing player, failed/malformed/absent capability probe, track
lookup failures, native command failure, track replacement, and plot decoding
rejections. Decode rejection identifies map/protocol/dimensions/track/format/PTS,
color metadata, each plot's byte array, or image construction. The existing
optional API calls the same validator and retains its acceptance behavior.

The original negative capability-cache policy is preserved. The cached scalar
reason records whether the original probe failed, was malformed or confirmed
command absence; adding diagnostics does not retry or change that decision.
Results carry no borrowed node storage, images on failure, players or view owners.
Native success still copies node-owned plot bytes before returning from the queue.

Fallback provenance contains the native attempt's generation, requested width,
reason, API status and track IDs when available. Both SDR and HDR screenshot
completions carry it through the original guards. Direct display-space difference
capture and successful native plots carry no native failure. An empty screenshot
completion remains an empty publication with its native reason; `nativePlots == nil`
alone never establishes successful screenshot fallback. The existing four-sample
history copies only scalar failure provenance alongside its original SDR content;
no extra payload history is retained.

The comparison XCTest observes publications without retaining them. It logs the
first eight fallback details per source/pair, including sequence, timestamp quality
and payload kind (`sdr`, `hdr`, `empty`), plus total counters at pair teardown.
The strict A/B unwrap also includes the actual failing sample's reason and payload
presence even if the detail budget was exhausted. Logging does not run in ordinary
app use. A command failure only identifies the native API boundary: the retained
provider has multiple early exits, so that status cannot identify hardware-download,
allocation, restart/seek, color or another internal cause by itself.

## Retained initial verification

The initial arm64 build succeeds. Its focused run passes 73 tests and fails two:
a comparison clock sample reports 116.7 ms against the unchanged 100 ms gate;
the new provenance test incorrectly equates requested width 64 with returned
width 16. The retained SDR fixture is 16 pixels wide and capture deliberately does
not upscale it. The corrected test checks requested and returned dimensions
separately. A subsequent test compile catches an optional-size lookup, corrected
before the final build. No production behavior is changed by these test fixes.
[Initial summary](focused-initial-rejected/summary.json), logs and initial binary
pins retain the unsuccessful attempt; it is not acceptance of the final test binary.
A process snapshot during the initial focused failure found no other Xcode build
or test process; this single sample is not continuous quiet-host evidence.

The final tests additionally cover empty fallback, SDR/HDR fallback, scalar history,
demand-change clearing, direct difference capture, return to native plots, and
stop-time stale-publication suppression. Pure tests cover rejection categories,
owned plot bytes and capability lookup/malformed/absence, including an available
command surrounded by malformed unrelated entries in either order.

## Completed relationship workload — rejected memory gate

The final arm64 Release build, deep/strict signature verification, **75 focused
hosted tests** (zero failures/skips) and **23 runner regressions** pass. The
relationship-snapshot workload completes three cycles but is **rejected** by
cycle-end memory growth. It covers **396 loupe windows**, **198 scope windows**,
**54 sampled difference publications** and **six fresh resumes** across all 54
selections. Minimum cadence is **58.72 presentations/sec**, maximum drift
**83.3 ms**, and **11,878/11,880** clock samples are usable; every window meets
29/30. Every selection measures at least **11.87 seconds**.

Gate footprints are **744,459,312**, **781,028,448** and **1,181,715,720 bytes**.
Maximum growth is **437,256,408 bytes (417.00 MiB)** above warmup, exceeding the
unchanged 256 MiB limit. The runner correctly rejects the failed source XCTest
regardless of printed completion markers. The subsequent observer test passes.
Only two/four/six closed windows survive the cycle checkpoints; no other observed
payload identities survive. All 180 identities are dead at post-test entry and
five seconds later. Weak probes do not cover every allocation/native handle.

Final-delayed footprint is **451,660,680 bytes**, a **696.23 MiB** decrease from
the failed gate; post-test entry/delayed are **451,513,224** and **308,677,512**.
These later samples never replace the original gate. The cycle-three/warmup
internal ledger increases 242.83 MiB, purgeable-nonvolatile increases 85.47 MiB
and graphics footprint decreases 5.48 MiB. Ledgers overlap and are not additive
allocation categories. These observations do not identify allocation stacks,
causal owners or explain the earlier memory rejection.

[Fallback summary](native-fallback-summary.json) records eight published
fallbacks, matching the full per-pair counters: **one SDR and seven HDR**, all
estimated timestamps and `commandFailed/status=-12` with expected track 1.
No empty publication appears in this workload. The retained header defines
`-12` as `MPV_ERROR_COMMAND`, a generic command error. Those new observations
exclude app-side plot decoding/capability rejection for these particular samples;
they do not establish the cause of any earlier uninstrumented rejection or the
provider's specific early exit. Passing sampled native checkpoints does not mean
native capture succeeds on every publication between them.

[Statistics](stats.json), [focused summary](focused-summary.json),
[rejected workload summary](soak-summary.json), [retirement summary](retirement-summary.json),
[candidate receipt](candidate-receipt.json), [execution pins](execution-inputs.json)
and [validation pins](validation-inputs.json) retain the final candidate identity.
Prepared/current Swift sources match; app and test executables are arm64 only.
`source.patch.gz` records the final diagnostic delta from the base commit.
`summarize-fallback.py` is a post-run analysis tool whose hash and input archive
hash are recorded in its output; it does not change XCTest or runner acceptance.
Other Xcode activity occurs in passive host snapshots, so this is shared-host
evidence, not quiet-host qualification. The scalar control is a separate fresh
process on the same binary and retains its own result.

## Completed same-build scalar control

The independent scalar control passes both XCTest methods and strict runner
acceptance. [Control statistics](scalar-control/stats.json),
[summary](scalar-control/summary.json), [execution pins](scalar-control/execution-inputs.json)
and [fallback summary](scalar-control/native-fallback-summary.json) retain its
separate outcome. Pre-run hashes prove the same app/test binaries and manifests
as the relationship run. Mode validation requires scalar-only rows throughout;
post-test completion/PID/history checks remain identical.

It completes **396 loupe windows**, **198 scope windows**, **54 sampled difference
publications**, **six fresh resumes** and all 54 selections at **at least 11.77
seconds** each. Minimum cadence is **58.76 presentations/sec**, maximum drift
**83.3 ms**, and **11,875/11,880** clock samples are usable, with every window
meeting 29/30. Footprints are **739,429,328**, **725,552,152** and **888,425,448
bytes**, maximum growth **148,996,120 bytes (142.09 MiB)**, below 256 MiB.

Only two/four/six windows survive the cycle checkpoints, all six remain at
final-delayed, and all **180 identities** are dead at post-test entry and five
seconds later. Final-delayed/post-entry/post-delayed footprints are **672,648,168**,
**320,801,432** and **150,309,528 bytes**. Its 16 published fallbacks all fit the
detail budget: **one SDR and fifteen HDR**, all estimated timestamps and
`commandFailed/status=-12`; no empty publication appears.

This completes a fixed-order, fresh-process same-build comparison, **not a causal
or quiet-host experiment**. The relationship process (PID 50796) overlaps other
builds/compiler activity. No other build/test process is observed at the scalar
process's (PID 62264) once-minute sample times; intervening work is not excluded.
[Host context](host-context.md) retains these unequal conditions. Both modes have
only closed-window survivors and eventual full weak retirement; removing getters
does not eliminate window survival. One memory rejection and one passing control
do not establish an observer-induced memory cause or explain earlier rejections.
Native provider failure stages/state, matched allocation/insertion stacks and
coordinated repeatability remain required before choosing a fix. No gate is
relaxed and the rejected relationship result is never superseded by the scalar pass.

`run-scalar-control.py` starts the independent scalar run after checking pinned
inputs; this checks identity, not acceptance of the preceding workload.
`retain-scalar-control.py` enforces the same exact coverage/receipt/settings and
cadence/drift/memory checks as relationship retention, plus scalar snapshot
validation and successful runner/XCTest outcomes. Its statistics pin the post-run
analysis script and source log. `summarize-fallback.py` requires all six counters,
unique sample identities and matching bounded detail counts; totals never infer
unlogged reasons. Run it with the control directory for the scalar summary.

## Reproduce

`prepare.py` verifies the baseline, scope delta and complete local MPVKit package
before preparing current sources at
`/private/tmp/aagedal-scope-failure-provenance-20261018/app`. Build for arm64 Release
using the [native handoff](../../MPV_NATIVE_RASTER_HANDOFF.md), then run
`run-validation.py`. It pins execution inputs and scripts,
verifies the app signature, runs focused tests, then runs the unchanged
relationship-snapshot provenance workload and post-test observer serially:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance --memory-diagnostics \
  --post-test-retirement --scope-resolution 720 --scope-fps 15 \
  --soak-seconds 10 --soak-cycles 3
```

The new diagnostics need no workload flag. They do not wait for a replacement
native plot, hold old plots or relax fallback rejection. Memory timing remains a
one-second cycle allowance with separate delayed/post-test observations; no pool
is drained. `run-diagnostic.py` retains passive process snapshots once per minute.
`retain.py` handles a complete source/observer workload, optionally `--rejected`
for a completed failed source test. An early throw requires retaining the partial
result separately without inventing absent checkpoints. Rejected prior runs remain
retained and unexplained. Generated looped UHD60 sources, 960×540 canvas and this
host/settings retain their workload limits. Native dependency sanitizers,
producer-authentic long media, peak/GPU memory, frame lock and physical HDR remain open.
