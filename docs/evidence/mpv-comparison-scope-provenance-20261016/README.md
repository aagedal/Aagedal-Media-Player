# Completed difference-scope publication provenance

This continuation associates a completed scope publication with the exact
submitted A/B captures, sample sequences/timestamps/uncertainties, effective gain,
waveform mode and output images. It never substitutes the captures that happen
to be current after asynchronous computation. The optional observation hook does
not retain snapshots in the production worker or view; qualification consumers
that retain them own their image/payload lifetime.

The production view now revokes a retained difference pair when either capture
is cleared or its capture generation changes. This also handles a rapid
replacement whose intermediate empty sample SwiftUI coalesces. A gain change
cannot resubmit pixels from the retired capture session. The worker advances its
pending queue before invoking the observation hook, so a synchronous observer
submission cannot strand the promoted request. Legacy render counts now use the
completed request's source instead of the view's current selection.

## Qualification

On Apple M5 Pro/64 GiB with macOS 27.0.1, the arm64 Release build succeeds
and **68 tests pass with zero failures/skips**. All **20 native-raster fixtures**,
native-scope and native-demand acceptance markers pass. The production comparison
provenance test passes both pairs and all three modes, including retirement and
fresh resume. All **36 loupe windows** and **18 scope windows** pass, with
**58.98 presentations/sec** minimum and **83.3 ms** maximum follower drift.

Six logged difference-window publications and two resumed publications each check
291,600 difference pixels and the complete occupied-bin sets. [The statistics](stats.json),
[measurements](measurements.txt), [XCTest summary](summary.json) and
[runner result](runner.log) retain the accepted result. Local app/result bundles
remain in `/private/tmp/aagedal-scope-provenance-20261016/derived` and
`tests/tests.xcresult`.

The short production workload mounts the comparison canvas, paired live loupes
and scopes with different-file UHD60 SDR/PQ and PQ/HLG pairs. It exercises
side-by-side, vertical wipe and overlay at 720 pixels/15 Hz, with one three-second
measurement window per scope selection per mode per pair. Existing loupe cadence,
clock, input freshness and readback-suppression gates remain. Difference
publications must advance both submitted-input timestamps in every difference
window, independently of the capture-progress checks.

For the latest completed difference publication in each of the six difference
windows, plus each pair's resumed publication, every display-space RGB difference
pixel is checked against independent scalar subtraction/gain/clamping of the
exact submitted images. A separate scalar oracle verifies all occupied waveform
and vectorscope bins. Neither oracle calls the production difference or scope
rendering helper. The live workload has matching 16:9 rasters; focused tests
retain aspect-fit and unequal-raster coverage.

After each pair, stopping primary capture and changing gain must produce no new
difference publication; restarting must publish a newer primary sample sequence
and pass the same pixel/bin checks. Focused regressions cover active-request
identity, replacement of pending work, callback reentrancy, canceled callbacks,
and an independent constant-color difference fixture. The focused fixture also
compares full plots through explicitly labelled renderer reuse; that comparison
is a transport check, not an independent renderer implementation.

## Reproduce

Restore the verified raster baseline and native scope delta using
[the scope handoff](../../MPV_NATIVE_SCOPES.md), then prepare and build current
sources as arm64 Release with testability enabled. The retained [preparation
helper](prepare.py) records the local acceptance paths and verifies the baseline,
scope delta and all package files before copying app sources. Run:

```sh
python3 docs/evidence/mpv-comparison-scope-provenance-20261016/run.py \
  PATH_TO_XCTESTRUN PATH_TO_NATIVE_FIXTURES MEDIA_FIXTURE_ROOT \
  PATH_TO_SCOPE_SIGNAL_FIXTURES PATH_TO_UHD60_MANIFEST NEW_OUTPUT
```

The media fixture root must contain the generated `loupe` fixtures. The scope
signal fixtures are in the restored delta's `validation/signal-fixtures`;
use the same UHD60 manifest as the earlier comparison qualification. The runner
sets the opt-in provenance workload, clears competing workload modes, executes
serially, and requires a successful XCTest action, zero failures/skips and the
native-raster, native-scope, native-demand and scope-provenance acceptance markers.
The original interactive macOS session must remain available for Metal and
VideoToolbox.

[The receipt](candidate-receipt.json) pins matching current/prepared Swift sources,
arm64 app/test executables, validation helpers, descriptors, libmpv, manifests,
UHD60 media and independent references. `source.patch.gz` contains the Swift
delta from its source commit. Compressed build/test/action logs, the executed
configuration and the XCTest summary retain the accepted execution.

## Limits and remaining work

This checks every pixel in sampled completed publications, not every published
frame. Independent bin occupancy does not validate complete trace color or
intensity. Screenshot timestamps remain estimated; exact provenance describes
association with submitted captures, not exact decoder-frame timestamps or frame
lock. The observation hook is intended for qualification, not permanent payload
history. Repeated renders of one pair do not count as input progress.

This short workload does not renew prior sustained memory/performance receipts
for this build. Generated looped UHD60 media, this host, the 960×540 comparison
canvas and matching 16:9 inputs bound the live result. Composite-canvas pixel
correctness, producer-authentic long media, other hosts, native dependency
sanitizers, peak memory and physical HDR calibration remain open. MPVKit was
restored without rebuilding; shipping pins and the native-raster default-off
gate remain unchanged.
