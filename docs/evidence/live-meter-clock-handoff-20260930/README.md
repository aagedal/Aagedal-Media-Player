# Live-meter pending-handoff clock race — 2026-09-30

A deterministic coordinator regression reproduces false synchronization loss
when a new DSP snapshot has already been reduced into the one-slot handoff but
its presentation task has not run. The test first publishes source endpoint
4,800 at 48 kHz and synchronizes playback at 0.1 seconds. On the same main-actor
turn, it submits reduced endpoint 14,400 and delivers playback clock 0.4 seconds.
The published endpoint is 300 ms behind, while the already-reduced endpoint is
only 100 ms behind, within the unchanged 250-ms freshness bound.

The pre-fix Release test fails as predicted: the coordinator rejects the older
published endpoint, clears its reading and changes generation. Its retained
clock-failure context identifies decoded frame 4,800, player time 0.4 seconds and
drift −300 ms. `fresh-snapshot-before.log` retains the native test receipt;
its JSON joins the exact source log hash and external result bundle.

This proves a post-DSP scheduling race. It does not identify the cause of the
historical authentic FX6 synchronization failure, whose pending-handoff state
was not retained. Production freshness bounds, pacing, source identity and the
bounded one-slot handoff are preserved by the targeted correction.

A second deterministic pre-fix Release regression submits a duplicate endpoint
4,800, then delivers the late clock before the queued producer-failure task can
run. The handoff has already rejected the duplicate, but clock assessment
replaces that specific diagnostic with generic synchronization loss and records
a clock-failure context. Its three assertions fail as predicted; the native
receipt is retained in `malformed-clock-before.log` and its JSON.

The correction reconciles the playing clock with the latest already-reduced
snapshot through the normal generation-checked drain, preserving pending
producer rejection before generic clock assessment. Paused, buffering,
unsupported-speed and EOF paths retain their prior ownership. This adds two
coordinator regressions. Root's corrected Release run passes all 36 focused
checks: 23 coordinator and 13 Review text tests, including both reproduced races.
`corrected-focused.log` and its JSON retain that receipt. The clock-failure
retention regression and existing suspended/EOF/lifecycle checks also pass.

## Corrected focused validation

All 36 optimized Release Review/meter checks pass, with no skips, failures,
expected failures or runtime warnings. Detailed validation explicitly requires
both new clock-ordering regressions, the new failure-context regression and
both Review correction regressions. Full results remain at
`/private/tmp/aagedal-2-continuation-focused-20260930/ClockRaceCorrected.xcresult`;
retained summaries, details and validation are alongside this report. These are
controlled source regressions, not native keyboard or spoken acceptance.
