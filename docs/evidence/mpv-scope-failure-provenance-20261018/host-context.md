# Shared-host context and fixed control order

Passive snapshots in `host-processes.txt.gz` record PID, parent PID, elapsed time,
CPU and command name once per minute. They do not identify every project's full
command line, exclude intervening workloads or establish causal resource contention.

The relationship workload uses xcodebuild 50793/app 50796 from about 00:19:36
local time. Another xcodebuild 50487 appears in 00:19–00:21 snapshots with its
build service and swift-frontend near 98–100% CPU in early samples. Another
xcodebuild 54006 appears around 00:22–00:26 with compiler samples near 84–97% CPU.
The projects are not established by these command-name snapshots. No second
Media Player benchmark or FTP Sync test process is identified in these samples.
The final memory rejection is not attributed to the other builds.

The scalar control uses xcodebuild 62259/app 62264. Its sampled build/test filter
shows only that workload during the reviewed 00:34–00:43 period; the retained log
continues through completion. This is not continuous quiet-host qualification.
Host conditions and run order are not randomized or matched: relationship runs
first, scalar second, each in a fresh process. Pre-run input hashes prove binary
and fixture identity, not equality of host/GPU/cache state.

The initial focused rejection has a separate process snapshot, retained under
`focused-initial-rejected/host-processes.txt.gz`, with no other Xcode build/test
process at that instant. Its 116.7 ms drift sample and incorrect fixture-width
assertion remain retained. No claim of causal load, pool ownership or production
leak follows from these snapshots or from differing memory outcomes.
