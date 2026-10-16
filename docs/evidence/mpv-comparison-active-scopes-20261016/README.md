# Sustained comparison with active scopes

The opt-in comparison runner now mounts the production `ScopeView` below the
960×540 comparison canvas and paired live lenses. Each SDR/PQ and PQ/HLG UHD60
pair exercises side-by-side, vertical wipe and overlay. Every mode measures
source A scopes, source B scopes and display-space difference separately.
The scope settings are explicitly 720 pixels and 15 Hz (the app defaults), and
are restored after the test. Shipping pins and the native-raster default-off
gate remain unchanged. No MPVKit source change or rebuild is required.

## Accepted arm64 run

The final candidate on Apple M5 Pro with 64 GiB RAM (macOS 27.0.1) passes three
complete cycles with ten measured seconds per scope selection per mode per pair (about 13 minutes including transitions and
lifecycle checks). XCTest and the strict runner both succeed with both requested
acceptance receipts. All **396 loupe windows** meet the unchanged gates:
**56.52 presentations/sec** minimum and **83.3 ms** maximum effective follower
drift. **11,878/11,880** clock samples are usable, with every window meeting its
29/30 requirement. Both loupe screenshot workers remain idle.

All **198 scope windows** publish both plots and pass selected-input freshness,
backend, transfer-tag and demand checks. Observed publication ranges are
14.65–15.27/sec for A, 14.18–15.27/sec for B, and 14.31–28.50/sec for difference.
These are UI publication observations, including callbacks from either input
in difference mode; they are not independent source-frame or physical-presentation
counts. Paused native-raster seek and paired follower close/reopen pass after
every pair.

Cycle-end physical footprints are 799,378,480; 1,039,453,232; and 840,404,184 bytes.
Maximum growth above warmup is **240,074,752 bytes (228.95 MiB)**, below 256 MiB.
The largest sampled in-playback footprint is 2,610,007,520 bytes; this is not a
peak measurement or an enforced total-memory ceiling.

[Statistics](soak-stats.json), [measurements](soak-measurements.txt),
[XCTest summary](soak-summary.json), compressed stdout/action logs and
[the candidate receipt](candidate-receipt.json) retain the run. The receipt pins
all 198 Swift source files, both app/test executables, validation scripts,
fixtures, restored libmpv and dependency descriptors. `source.patch.gz` records
the exact code delta from the receipt's source commit. The arm64 app is retained
locally at `build/active-scopes-candidate-20261016/Aagedal Media Player.app`.

## Capture continuation

The first attempted run found a zero-publication difference-scope window while
both inputs continued advancing. Its next window published only twice. The
30×100 ms sampling windows took about 7.6 and 6.6 seconds. That run was stopped
for diagnosis; it is rejected partial evidence, not a completed soak. Xcode
could not finalize its interrupted result bundle. Its stdout, single assertion
failure, 18 completed scope-window records, source delta and build receipt are
retained separately as `rejected-*`; they are not substituted for final evidence.

The screenshot/downsampling helpers were `nonisolated async` without any
suspension. With this project's approachable-concurrency configuration, calling
them from a main-actor task could keep synchronous screenshot waits and pixel
conversion on the main actor. Both SDR and HDR helpers now execute explicitly
inside detached utility tasks and return Sendable results. Publication still
uses the existing capture-generation and backend-identity guards. The shared
one-shot HDR diagnostic flag is protected by a lock. No pairing tolerance,
renderer gate or acceptance limit was changed.

The final build's focused loupe/scope run passes 42 tests without failures or
skips. Arm64 Release static analysis and strict signature verification of the
retained app also pass. This is regression coverage, not by itself sustained
acceptance. The single-source HLG native/screenshot throughput measurements remain separate
from concurrent comparison measurements.

## Acceptance contract

Each three-second window retains the existing loupe gates: both surfaces must
complete at least 45 Metal presentations/sec, effective source/follower drift
must stay within 100 ms, at least 29/30 clock samples must be usable, and both
loupe screenshot workers must remain idle. Difference scopes legitimately use
their own display-space screenshot workers.

Scopes must publish both plots in every window. Selected inputs must advance
sequence and have at least two distinct sampled media timestamps. A/B inputs
must contain native plots with exact matching PTS and expected SDR/PQ/HLG tags;
difference inputs must contain display-space SDR pixels without native plots.
The unselected capture must remain cleared at window endpoints. The selected
analysis demand and display-frame policy are checked after each window.

The test retains paired paused native-raster seek and follower close/reopen
checks. Between complete cycles, after host/controller teardown and a one-second
retirement allowance, physical footprint must stay within 256 MiB above the
first complete warmup cycle. In-playback samples are logged separately.

## Reproduce

Restore the checksummed raster bundle and native scope delta using
[the scope handoff](../../MPV_NATIVE_SCOPES.md), then build current sources for
testing in Release with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES`.
Use the retained UHD60 manifest from [the raster handoff](../../MPV_NATIVE_RASTER_HANDOFF.md):

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/aagedal-comparison-active-scopes-next \
  --comparison --active-scopes --soak-seconds 10 --soak-cycles 3
```

With `--active-scopes`, duration is measured **per scope selection per mode per
pair**. Each selection completes its final three-second window. Require a
successful XCTest exit and both `MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE` and
`MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE` with the requested duration/cycles.
The runner rejects missing or mismatched scope receipts, even if the ordinary
comparison receipt is present. Nine runner regressions cover these rejection
paths, environment isolation, and legacy/format-2 xctestrun configuration.

## Limits

Scope rates count observed completed UI publications, not physical scope
presentations or unique video frames. Positive per-window progress is a stall
check, not a guaranteed scope throughput floor. Sampled input timestamp progress
does not establish difference-output input provenance or composite pixel
correctness. Demand endpoint assertions do not exclude transient publications
between observations; focused lifecycle tests cover obsolete result revocation.
The logged latest/history eligibility counters use the fixture's 60 fps tolerance
for diagnosis; they are not proof of the exact metadata-dependent production
pair selected for a published difference image.

Generated six-second looped fixtures, independent decoder clocks, this host,
this canvas size and these scope settings bound the evidence. Native A/B scopes
analyze source signal; difference scopes analyze display-space captures. The run
does not establish frame lock, physical HDR calibration, producer-authentic
long-media behavior, other-machine performance, peak allocation, a total-memory
ceiling, or sanitizer coverage.
