# Comparison scope settings qualification

The sustained comparison runner accepts explicit production scope resolution
(360, 720, 1080, 1440) and integer update rate (5–30 Hz). Defaults remain
720 pixels/15 Hz. Both options require `--active-scopes`; inherited settings
are cleared from ordinary runs. XCTest independently validates the settings,
sets them before mounting production scopes and restores preferences afterward.

Window records and the required acceptance receipt carry the chosen settings.
The runner rejects a receipt for different settings, including numeric suffixes
that would previously match a prefix. Native waveform/parade dimensions,
vectorscope dimensions and difference input widths must match the requested
resolution. All existing loupe, clock, scope freshness and memory gates remain.

## Accepted arm64 run

The current arm64 Release candidate passes **three complete cycles at 1440
pixels/30 Hz**, ten measured seconds per scope selection per mode per pair,
on Apple M5 Pro/64 GiB, macOS 27.0.1. XCTest and the strict runner succeed with
both requested receipts. All **338 loupe windows** and **169 scope windows**
pass, with **59.03 presentations/sec** minimum, **66.7 ms** maximum follower
drift and **10,140/10,140** usable clock samples. Both loupe screenshot workers
remain idle; paired paused native-raster seek and close/reopen checks pass.

Cycle-end physical footprints are 819,645,536; 1,009,978,704; and 788,434,016 bytes.
Maximum growth above warmup is **190,333,168 bytes (181.52 MiB)**, below 256 MiB.
The largest in-playback sample is 2,553,548,280 bytes; it is neither a peak
measurement nor an enforced total-memory ceiling.

Observed scope publications range from 15.15–30.44/sec for A, 15.64–21.76/sec
for B and 5.25–18.71/sec for difference. The requested 30 Hz is not an achieved
throughput guarantee. Windows finish after 30 asynchronous 100 ms sleeps and
may exceed three wall-clock seconds under load; the test completes its final
window after each requested duration. Window counts therefore differ from the
previous default-settings run and do not measure equivalent throughput.

[The statistics](soak-stats.json), [measurements](soak-measurements.txt),
[XCTest summary](soak-summary.json), compressed stdout/action logs and
[runner output](runner.log) retain the result. [The candidate receipt](candidate-receipt.json)
pins matching prepared/current Swift files, arm64 app/test executables, runner
scripts, media/reference files and restored dependency descriptors/libmpv.
`source.patch.gz` records the exact source delta from the receipt's base commit.
The dependency baseline and scope delta inventories were verified by
[the retained preparation helper](prepare.py); MPVKit was not rebuilt.

The fresh arm64 Release build succeeds; all **42 focused hosted tests** pass
with **zero failures/skips**. All **10 strict-runner regression tests** pass,
covering both xctestrun formats, settings bounds, inherited settings, mismatched
receipts and numeric-suffix rejection. The local app/result bundles remain in
`/private/tmp/aagedal-scope-settings-20261016/derived` and `soak/tests.xcresult`.

## Reproduce

Restore the checksummed raster and scope candidates following
[the scope handoff](../../MPV_NATIVE_SCOPES.md), then build current app/test
sources for arm64 Release with testability enabled. Run:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/aagedal-comparison-scope-settings-next \
  --comparison --active-scopes --scope-resolution 1440 --scope-fps 30 \
  --soak-seconds 10 --soak-cycles 3
```

Duration is per scope selection per comparison mode per pair. Require successful
XCTest exit and both comparison and active-scope acceptance receipts matching
the selected duration, cycles, resolution and update rate.

## Limits

Configured Hz is a scheduling target. Scope rates count completed UI
publications, not unique frames, physical presentations or a guaranteed rate.
The unchanged gate requires publications and selected-input timestamp progress
in every measurement window. Native A/B plots analyze source signal; difference
uses display-space captures. This does not establish exact difference-output
provenance or composite pixel correctness.

Generated looped UHD60 media, this host, the 960×540 comparison canvas and the
specific tested setting bound the result. Other setting combinations, authentic
long media, other machines, frame lock, peak memory, native dependency sanitizer
coverage and physical HDR calibration remain open. Shipping pins, restored
MPVKit binaries and the native-raster default-off gate are unchanged.
