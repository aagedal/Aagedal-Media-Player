# Sustained comparison difference-scope provenance

This continuation combines the existing sustained comparison gates with the
independent completed-publication checks from the short
[provenance qualification](../mpv-comparison-scope-provenance-20261016/README.md).
It changes qualification code, not production app behavior or MPVKit.

**Status: tooling verified; sustained candidate acceptance remains open.**
The arm64 Release build and signature verification pass. The 68-test hosted
regression action and separate settings regression pass with zero failures/skips,
including all 20 native-raster fixtures, native scopes/demand and the short
production provenance workload. All 12 strict-runner regressions pass.
The exact compiled sources are committed at `f2820e8`; the
[candidate receipt](candidate-receipt.json) pins source, executable, dependency,
fixture and validation-helper hashes. No MPVKit rebuild, shipping repin or
provider-gate change was made.

## Workload and gates

The arm64 Release workload uses the production comparison canvas, paired live
loupes and scopes with different-file UHD60 SDR/PQ and PQ/HLG pairs. Three cycles
exercise side-by-side, vertical wipe and overlay with A, B and difference scopes
at 720 pixels/15 Hz and ten measured seconds per selection per mode per pair.
Duration accumulates only cadence-window time; scalar verification, footprint
sampling and logging between windows do not consume it. Each selection completes
its final three-second window, so it may run longer.

Every measurement retains the existing 45 loupe presentations/sec, 100 ms drift,
29/30 usable clock samples, scope publication/input progress and idle loupe
screenshot-worker gates. The selected A/B sample must contain native plots at
each measurement-window endpoint; their dimensions and difference captures must match the requested
settings. This does not exclude transient fallback between sampled endpoints.
Each cycle tears down both pairs; cycle-end physical footprint must stay within 256 MiB above the first warmup cycle.

Every difference window additionally requires advancing **published** A/B input
timestamps and independently checks the latest completed difference publication:
every RGB difference pixel against scalar subtraction/gain/clamping of its exact
submitted captures, and complete waveform/vectorscope occupied-bin sets against
an independent scalar oracle. After each pair, retiring capture and changing gain
must not resubmit old pixels; restarting must publish a fresh pair that passes
the same pixel/bin checks. Only the latest publication is retained by the test
probe; there is no growing payload history.

The runner requires `--scope-provenance --active-scopes --comparison` with a
sustained duration, and all three matching comparison, active-scope and provenance
receipts plus successful XCTest exit. It clears inherited workload opt-ins from
both the test configuration and subprocess environment. Twelve runner regressions
cover both configuration formats, invalid arguments, inherited settings, failed
XCTest and missing/mismatched/suffixed receipts. The independent Swift review
found no blocking findings.

## Rejected initial run and process-local settings

The initial run was interrupted during cycle two after native plots changed from
requested 720-pixel output to 64 and 1440 pixels. A separate Aagedal hosted test
process on this Mac was changing the shared persisted scope settings and running
a 1440/30 workload. The [rejected status](rejected-status.json), compressed build,
test/action logs, executed configuration and pre-isolation test-source patch are
retained. This is a rejected partial run, not sustained acceptance; no threshold
was relaxed.

Both short and sustained provenance tests now use a volatile `NSArgumentDomain`
override for their scope settings. This keeps the requested resolution/rate
inside the test process, preserves unrelated launch arguments and restores the
previous argument domain afterward, without overwriting persisted app settings.
A named-suite regression checks production settings and SwiftUI `AppStorage`
lookups after persistent changes, plus restoration; it does not simulate all
notification behavior of an already-mounted view. Shared CPU/GPU contention
remains separate from preference isolation. The interrupted pre-duration repeat
began while the other 1440/30 comparison workload was active; its retained process snapshot records that context.

A second partial repeat was interrupted after independent review identified that
the wall-time selection timer included post-window scalar verification. Its
`pre-duration-*` files are retained without an acceptance claim. The final
candidate accumulates only cadence-window measurement time and logs the running
total. Evidence must contain all 54 cycle/pair/mode/selection groups, with
increasing totals and at least ten measured seconds in each.

The first corrected-duration repeat also ran with another Aagedal workload
active and **failed** the strict native A/B gate in cycle two, SDR/PQ vertical
wipe: the selected primary sample contained screenshot fallback, not native
plots. Its `loaded-native-failure-*` files retain the failed XCTest, measurements,
configuration and matching source patch. Metal allocation errors occur shortly
before rejection. Native analysis intentionally returns unavailable across seeks,
loop/restart transitions and other failures; the available logging cannot prove
which condition caused this fallback. Independent review found no capture
ownership bug. No production behavior or acceptance gate was changed to hide it.
A successful separate repeat would not resolve this contention result.

After the first competing Aagedal workload finished, the same built candidate
passed all 68 focused regressions. Another sustained Aagedal benchmark then
started. The [process check](host-processes-at-quiet-attempt.txt) detected it and
did not start the planned quiet repeat. No successful three-cycle provenance
receipt is claimed. The process check does not reserve the machine or establish
an idle OS for a complete future run.

The next step is a serial three-cycle 720/15 run using the command below, with
all gates unchanged. Its evidence must validate all 54 selection-duration groups,
exact sampled difference pixels/bins, native A/B endpoint samples, cadence,
drift, input progress and cycle-end memory. If native fallback reproduces without
the competing workload, add failure-reason diagnostics before choosing a
production or provider change. A serial success must retain the loaded rejection
and cannot qualify arbitrary concurrent workloads.

## Reproduce

Restore the verified raster baseline and native scope delta using
[the scope handoff](../../MPV_NATIVE_SCOPES.md). The retained [preparation
helper](prepare.py) verifies both inventories and all package files before
preparing current app sources at the exact local acceptance paths. Build those
sources for arm64 Release with testability enabled, as in the
[native raster handoff](../../MPV_NATIVE_RASTER_HANDOFF.md). Then run:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  PATH_TO_UHD60_MANIFEST NEW_OUTPUT \
  --comparison --active-scopes --scope-provenance \
  --soak-seconds 10 --soak-cycles 3
```

Require successful XCTest exit and
`MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per selection, resolution=720, targetFPS=15`,
as well as the ordinary sustained-comparison and active-scope receipts.
The existing short provenance runner separately verifies native-raster fixtures,
native scopes, demand and lifecycle regressions on the same built candidate.

## Limits

Pixel/bin correctness is sampled once per difference window and after each
pair's capture restart, not checked for every publication. The scalar oracle
runs after the cadence measurement, leaving unmeasured intervals between those
windows. Configured scope Hz is a scheduling target, and publications/presentations
do not count unique decoded video frames. Exact provenance associates outputs
with submitted captures; screenshot timestamps remain estimated.

Generated looped media, matching 16:9 rasters, the 960×540 comparison canvas and
this host bound the result. It does not establish complete scope trace colors or
intensities, composite-canvas pixels, A/B frame lock, physical HDR calibration,
producer-authentic long media, other hosts/settings, native dependency sanitizer
coverage or peak memory. In-playback footprint samples are neither a peak-memory
measurement nor a total-memory ceiling. Shipping pins and the native-raster
provider's default-off gate remain unchanged.
