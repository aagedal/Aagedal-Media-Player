# Live-loupe rate following and scope analysis demand

The app now follows the source MPV backend's effective playback rate, including
Compare Mode's temporary synchronization nudges. Those nudges do not change the
user-facing transport speed. Previously the loupe used that nominal speed and
could correct by only 5% while its source was temporarily corrected by up to
50%. Temporary source nudges now update the follower's base rate without seeking
or withdrawing readiness; nominal speed/transport changes still realign it.
Clock polling is 50 ms, with one asynchronous sample in flight and stale rate
samples rejected. Independent decoders remain independently clocked.

Scope analysis already runs inside the restored native MPVKit candidate. This
change publishes its finished plot references directly and invalidates obsolete
fallback computations. A/B scope selection also suppresses analysis of the
unselected source; display-space difference still requests both. Capture intent,
AV output identity and backend replacement behavior are preserved. Re-enabling
a paused AVPlayer source copies its already-consumed frame once, then returns
to ordinary new-frame checks.

## Final app regressions

The final arm64 Release build passes **59 tests, zero failures and zero skips**
in the seven loupe/scope suites plus `ScopeAnalysisDemandTests`. Coverage includes
source rate nudges in both directions, native image publication and fallback
revocation, A/B/difference demand policy, native SDR-to-PQ backend replacement
while analysis is disabled, AV output retention with no pipeline rebuild, and
paused AV frame resumption with matching pixels/timestamp and no repeated
analysis. Both demand acceptance markers are present in the retained logs.

The single-source UHD60 HLG scope test measured **29.98 native updates/sec** and
**19.64 screenshot updates/sec** at a 30 Hz target. This is an end-to-end check
on this host, not an isolated before/after measurement of direct publication or
A/B selection gating, and not a universal hardware performance claim.

[The final receipt](candidate-receipt.json) pins production/test source hashes,
binary hash, restored dependency descriptors and test results. The source copy
used for building matches those hashes. The executable is arm64 only and
`codesign --verify --deep --strict` passes with macOS trust services available.
[The test summary](tests-summary.json), compressed build/test/action logs and
final comparison recheck are retained here. The app is available locally at
`build/continuation-candidate-20261016/Aagedal Media Player.app`.

## Full sustained comparison run

The previously rejected 30-second-per-mode workload now passes all three
cycles, both different-file SDR/PQ and PQ/HLG pairs, and all three comparison
modes. All **360** loupe windows meet 45 fps: the minimum is **58.80 fps**.
Maximum effective follower drift is **66.7 ms**, below the unchanged 100 ms
limit. All **10,800/10,800** clock samples are usable; screenshot workers stay
idle. Paused native-raster seek and follower close/reopen assertions pass.

Cycle-end physical footprints are 759,908,704; 781,125,984; and 896,256,400 bytes.
Maximum growth above the first cycle is 136,347,696 bytes (130.03 MiB), below
256 MiB. Highest sampled in-playback footprint is 1,648,855,608 bytes. These
samples do not measure peak allocation or establish a total-memory ceiling.
The XCTest and strict runner both succeed; the completion marker alone is not
used as acceptance.

[Measurements](soak30-measurements.txt), [statistics](soak30-stats.json),
[XCTest summary](soak30-summary.json), compressed action/stdout logs and
[build receipt](soak30-receipt.json) preserve this run. It used the build before
the subsequent AV-only paused recapture correction; scopes are inactive in this
MPV comparison workload. Its exact source delta from commit `708d25b` is retained
as `soak30-source.patch.gz`. The final binary is independently rechecked below;
these two build hashes are not interchangeable. The full-run app is retained at
`/private/tmp/aagedal-continuation-20261016-soak-candidate.app`.

## Final-binary comparison recheck

After the AV-only paused scope correction, the final binary independently
passes three cycles of both pairs and all three modes at 10 measured seconds
per mode (each final three-second window completes). All **144** loupe windows
meet 45 fps, with **59.01 fps** minimum and **50 ms** maximum drift. All
**4,320/4,320** clock samples are usable. Screenshot workers remain idle and all
paused native seek/reopen assertions pass. Cycle-end footprints are 837,863,560;
723,093,616; and 558,680,224 bytes, with no growth above the first cycle.

[The final statistics](soak10-stats.json), [XCTest summary](soak10-summary.json),
[measurements](soak10-measurements.txt), compressed action/stdout logs and final
candidate receipt preserve this separate check. It does not replace the longer
30-second-per-mode run or claim its build hash. Reproduce with the same runner
and `--comparison --soak-seconds 10 --soak-cycles 3`.

## Reproduce

Restore the arm64 raster bundle and native scope delta according to
[the scope handoff](../../MPV_NATIVE_SCOPES.md). No MPVKit compilation is needed.
Build current sources with `build-for-testing`, Release, `ARCHS=arm64`,
`ONLY_ACTIVE_ARCH=YES`, and `ENABLE_TESTABILITY=YES`.

For focused tests, configure the xctestrun environment with:

- `MEDIA_FIXTURE_DIR`: output of `scripts/generate-test-fixtures.sh`.
- `AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1`.
- `MPV_SCOPE_TEST_FIXTURES`: restored delta `validation/signal-fixtures`.
- `MPV_SCOPE_PLAYBACK_FIXTURE`: restored delta `validation/playback-fixtures/hlg-tagged.mp4`.

Run `InspectionLoupeRenderingTests`, `LiveLoupeSessionTests`,
`LoupeCaptureGateTests`, `LatestFrameGateTests`, `MPVNativeScopeIntegrationTests`,
`MPVScopePlotsTests`, `ScopeAnalysisDemandTests`, and `ScopeFrameDifferenceTests`
with parallel testing disabled. Exclude the three opt-in comparison/concurrent
qualification methods from this focused run; execute them with their runner.

For sustained comparison:

```sh
python3 scripts/validate-mpv-native-app.py PATH_TO_XCTESTRUN \
  /private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json \
  /private/tmp/new-rate-following-soak \
  --comparison --soak-seconds 30 --soak-cycles 3
```

## Limits

Shipping package pins and the decoder-raster default-off gate are unchanged.
The native scope provider still performs CPU analysis and VideoToolbox surface
downloads. GPU analysis would require a separate MPVKit change/build and fresh
qualification. Generated six-second looped UHD60 inputs, independent decoder
clocks, physical HDR calibration, composite canvas pixel/cadence correctness,
active-scope comparison load, producer-authentic long media, other machines and
sanitizers retain their existing qualification limits. MoltenVK teardown
allocation and CATransaction diagnostics remain in the logs.
