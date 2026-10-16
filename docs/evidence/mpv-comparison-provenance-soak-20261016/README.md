# Sustained comparison with sampled difference-publication provenance

This continuation combines the existing sustained comparison and active-scope
workload with independent pixel/bin checks of completed difference publications.
It reuses the verified arm64 raster baseline and native scope delta without
rebuilding MPVKit. Shipping dependency pins and the default-off native-raster
provider gate remain unchanged.

## Accepted final run

On Apple M5 Pro/64 GiB with macOS 27.0.1, the final arm64 Release build and
all **68 focused hosted tests** pass with zero failures/skips, including all
20 native-raster fixtures, native scopes and native-demand acceptance markers.
All **12 strict-runner regressions** pass. The retained app passes local
[deep/strict signature verification](signature-verification.txt).

The sustained run passes three cycles at 1440 pixels/30 Hz, both different-file
UHD60 pairs, all three modes and all three scope selections. All **344 loupe
windows** and **172 scope windows** pass: minimum **58.76 presentations/sec**,
maximum **83.3 ms drift**, and **10,318/10,320 usable clock samples** (each window
meets 29/30). All 54 selections include at least **10.09 measured seconds**.
All **54 sampled difference publications** and **six resumed publications**
pass 1,166,400-pixel whole-image checks and complete occupied-bin checks apiece.

Cycle-end physical footprints are **1,048,055,072**, **1,064,783,208** and
**1,169,591,848 bytes**: maximum growth is **115.91 MiB** above the first complete
warmup cycle (limit 256 MiB). These are sampled cycle-end values, not peaks or
a total-memory ceiling. This run has a higher warmup footprint than the initial
rejection; no isolated total-memory reduction or causal leak fix is established.

[Statistics](stats.json), [measurements](measurements.txt), [focused summary](focused-summary.json),
[soak summary](soak-summary.json), compressed build/action/stdout logs and executed
configurations retain the result. [The candidate receipt](candidate-receipt.json)
pins matching current/prepared Swift sources, arm64 executables, dependency
inventories/descriptors, libmpv, media, references and validation helpers. Local
app/result bundles remain under `/private/tmp/aagedal-provenance-soak-20261016/derived`,
`focused-isolated/tests.xcresult` and `soak-isolated/tests.xcresult`.

## Retained rejection and oracle adjustment

The [initial run](rejected-initial/stats.json) was rejected by the unchanged
cycle-end memory gate: footprints were 703,073,592, 943,050,040 and 1,253,395,840
bytes, reaching 524.83 MiB above warmup (limit 256 MiB). All 338 loupe windows,
169 scope windows, 54 sampled difference publications and six resumed
publications otherwise completed. Minimum cadence was 58.79 presentations/sec
and maximum drift was 66.7 ms. The failed XCTest exit correctly made the runner
reject the result even though the XCTest printed its end-of-workload markers.
Rejected logs, summary, source delta, settings and source/binary receipt are
retained separately; the rejected result does not qualify this workload.

Inspection found no concrete retain cycle. The independent oracle used large
hash sets and filtered index arrays in addition to normalized pixel buffers.
The follow-up replaces the sets with fixed-size byte masks and compares every
output alpha-occupancy value directly, preserving both missing/extra-bin checks.
An explicit autorelease pool bounds Objective-C/CF bridging temporaries inside
each detached synchronous oracle call. This is a qualification-harness allocation
adjustment; it does not establish the rejected run's memory-growth cause or fix
a demonstrated production leak. No production code or acceptance limit changed.

The first focused run of the adjusted build also retained an [independent timing
rejection](rejected-focused-drift/summary.json): 67 tests passed and the short
comparison provenance test failed one SDR/PQ side-by-side difference-lens window
at 150 ms follower drift (limit 100 ms). Pixel/bin checks completed. The same
build subsequently [passed all 68 tests](focused-repeat/summary.json) with unchanged
settings and gates. The follower uses soft rate correction for intermediate offsets below its hard-seek threshold; inspection
found no concrete new causal bug from the oracle adjustment. A passing repeat
does not erase this excursion or establish a deterministic 100 ms synchronization
guarantee under arbitrary load. Source/binary identity and rejected logs are kept.

A subsequent sustained attempt was [stopped as an invalid settings run](rejected-settings-partial/status.json):
requested settings were 1440/30, but native plot dimensions were 720×405. No
acceptance is claimed for that partial run. The harness had set mutable persisted
preferences; the follow-up instead installs selected values in the process-local
`NSArgumentDomain`, preserving other XCTest argument values and restoring the
prior domain afterward. This gives requested settings precedence over app startup
and other-process persistent preference changes. It changes test isolation only;
the actual plot/input dimension checks remain required. The writer that replaced
the initial persisted settings was not identified.

## Workload and gates

The production comparison canvas, paired live loupes and scope view exercise
both different-file UHD60 SDR/PQ and PQ/HLG pairs, side-by-side/vertical-wipe/overlay,
and A/B/difference selections. The selected settings are 1440 pixels/30 Hz,
three complete cycles and at least ten measured seconds per selection.
The requested Hz remains a scheduling target.

All existing gates remain: each loupe must complete at least 45 Metal
presentations/sec in every window, effective follower drift must stay within
100 ms with at least 29/30 usable clock samples, and both loupe screenshot
workers must stay idle. Selected scope inputs and completed plots must progress;
A/B must use native plots and difference must use display-space captures.
Cycle-end physical footprint must stay within 256 MiB above the first complete
warmup cycle after teardown and the one-second retirement allowance.

Each difference window additionally requires a newer publication generation and
multiple submitted A/B timestamps. An independent scalar oracle checks every RGB
difference pixel against that publication's exact submitted images and effective
gain, plus complete occupied waveform/vectorscope bin sets. Capture retirement,
a gain change that must not resubmit retired pixels, and a fresh restart are
checked after each pair. The probe retains the latest publication, with no
payload history; one sampled publication is held while its oracle executes.

The scalar oracle uses fixed-size bin masks and an explicit autorelease pool,
and runs away from the main actor. Its execution falls outside
cadence measurement windows and does not consume the requested measured duration.
The test accumulates the elapsed sampling windows, finishing its final window
once the requested duration is covered. This includes ordinary asynchronous
sampling waits; it is not a hard real-time sampling guarantee. Background oracle
work can overlap live playback between measured windows.

## Reproduce

Restore the checksummed raster and scope candidates following
[the scope handoff](../../MPV_NATIVE_SCOPES.md), prepare current sources and build
arm64 Release for testing with testability enabled. The retained [preparation
helper](prepare.py) records the exact local verified baseline/delta paths.

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --verify-difference-pixels \
  --scope-resolution 1440 --scope-fps 30 --soak-seconds 10 --soak-cycles 3
```

Require successful XCTest exit and all three matching receipts:
`MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE`,
`MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE`, and
`MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE`.
The runner rejects incompatible flags, isolates inherited workload selections
in both target and process environments, and retains the executed configuration.
Its regression tests cover both xctestrun formats and missing/mismatched receipts.

The separate focused run uses the previous [provenance runner](../mpv-comparison-scope-provenance-20261016/run.py).
[The retention script](retain.py) checks successful zero-skip results, coverage,
unchanged fixtures, matching prepared/current Swift sources and arm64 binaries
before writing the local acceptance receipts. The receipt pins the committed
source state; `source.patch.gz` is empty when those app/test/runner changes are
already included in that commit.

## Limits

This qualifies sampled completed publications, not every published frame.
Independent occupied-bin checks do not validate full plot colors or intensities.
Screenshot timestamps remain estimated: exact provenance describes association
with submitted captures, not exact decoder timestamps or A/B frame lock.
Metal counters measure loupe presentations, not unique video frames or composite
canvas cadence. Footprints are cycle-end samples, not peak allocations, GPU
memory, a total-memory ceiling or leak/sanitizer evidence.

Generated looped media, matching 16:9 rasters, a 960×540 comparison canvas,
these settings and this host bound the run. Producer-authentic long media,
composite-canvas pixel correctness, other settings/hosts, native dependency
sanitizers and physical HDR calibration remain open. This run does not extend
ASan coverage or republish a shipping dependency.
