# Shared-host coordination

The FTP Sync coordinator reserved a separate seven-minute signed XCTest UI run
and waited for Media Player's native soak to release the desktop. It reported no
desktop interaction during this workload. At approximately 20:19 local time on
2026-10-17 it started an optional isolated unsigned Release compile (PID 41698),
then reported stopping it to reduce contention while awaiting desktop release.
The coordinator-reported approximate wall time has not been aligned with the test
process clock.
The precise overlap and impact on individual samples are not established. Passive
once-per-minute process snapshots are retained separately; they cannot establish
continuous host exclusivity. This run is shared-host evidence, not quiet-host
qualification. No acceptance gate was changed in response to the compiler load.
