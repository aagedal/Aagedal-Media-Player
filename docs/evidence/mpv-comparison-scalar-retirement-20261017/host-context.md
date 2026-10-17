# Shared host context

The initial pre-build process inspection found no other Xcode test or Media Player benchmark.
Later one-minute process snapshots record unrelated work during both sustained
attempts; exact overlap between snapshots is unknown. The retained
`host-processes.txt.gz` contains PID, parent PID, elapsed time, CPU and command name,
not full command arguments. It does not establish impact or causation.

- Relationship control (PID 90209): snapshots around 23:38–23:42 local time include
  AagedalFTPSyncUITests-Runner PID 88839, FTP Sync app processes and another
  xcodebuild. Some swift-frontend snapshots approach 98% CPU. A separate command
  inspection identified FTP Sync UI smoke tests; it did not identify every compiler.
- Scalar control (PID 98798): snapshots around 23:45–23:49 include additional
  xcodebuild PIDs 98962/99949 and swift-frontend activity, including a near-98% CPU
  sample. The project of these compilers is not established by the command-name log.

No other Media Player benchmark was identified in the inspected snapshots.
That is not proof of absence between samples or quiet-host acceptance. Neither
native fallback, drift nor different retirement patterns are attributed to load.
Both controls use the same pinned app/test binaries and manifests, but fresh
processes with independent weak identity registries. They run in fixed order,
relationship first, scalar second. The first interrupts in cycle two, so the
completed scalar run cannot supply a complete paired causal comparison.
