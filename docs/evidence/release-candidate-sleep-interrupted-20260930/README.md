# Sleep-interrupted candidate attempt — 2026-09-30

The canonical verifier at clean commit `c4a755769ee26a8412ac65777cfcf81bb563396f`
passed its script-validator gate and optimized Release aggregate: 705 passes,
eight allowlisted skips, zero failures or runtime warnings (713 total).
All three new active-track/composition loupe decoder tests passed.

Its separate serial transport run failed both tests while the host repeatedly
slept and executed maintenance dark wakes. The first test ran from 12:37:01 to
12:52:02 local time (901 seconds); an eight-second observation collected only
three samples and reported a 531.8-second excursion. The power log records a
534-second sleep from 12:37:16 to 12:46:10. The second test overlapped a
900-second sleep from 12:52:02 to 13:07:02. Eight sleep intervals totalled
1,723 seconds during the approximately 1,987-second runner interval.

The retained power validator rejects this interval. These failures are
sleep-confounded timing/audio observations, not clean evidence of a transport
regression. No synchronization thresholds were changed. The verifier exited
before static analysis, preflight or final identity checks, and has no
`status=passed` record. This attempt must not be consumed as candidate evidence.
A fresh awake canonical verification is required.

Full aggregate logs/build products and both result bundles remain at
`/private/tmp/aagedal-candidate-c4a7557-20260930`. Copied summaries, detailed
outcomes, serial failure log and filtered power events are retained here.
The power interval is the isolated runner, from 12:37:01 to 13:10:07 local time.
