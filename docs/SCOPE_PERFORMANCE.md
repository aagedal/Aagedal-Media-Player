# Scope Performance

The [native MPV scopes candidate](MPV_NATIVE_SCOPES.md) computes all three plots
inside libmpv and returns diagnostic images. The app now publishes those image
references directly, without another detached compute task. It invalidates older
active and pending screenshot computations before publishing native plots, and
updates the HDR scale before the render notification. This app-side change needs
no MPVKit rebuild or shipping package pin change. No isolated throughput gain
is claimed for direct publication.

Comparison scopes now request analysis only for the selected source, or both
for display-space difference. Changing demand invalidates old capture requests
and timer ticks. Both sessions retain their running intent for backend reloads;
unselected sources skip analysis while keeping their timer and AV outputs, so
selection does not change the ProRes RAW decode pipeline. Re-enabling a paused
AVPlayer source requests one fresh copy of its already-consumed frame, then
resumes ordinary new-frame checks.

The native provider still performs CPU analysis, pixel conversion and
VideoToolbox downloads for selected sources; plot payload copies remain in the
app. GPU analysis remains further optimization work. AVPlayer, unsupported MPV
inputs and display-space difference scopes keep their existing capture/compute
paths when requested. No isolated throughput gain is claimed for selection
gating.

The [2026-10-16 candidate evidence](evidence/mpv-loupe-rate-scope-demand-20261016/README.md)
records 59 passing loupe/scope regressions and a UHD60 HLG end-to-end check at
29.98 native updates/sec versus 19.64 screenshot updates/sec on this host.

The CPU scope renderer has a reproducible optimized profiling matrix:

```bash
scripts/profile-scopes.sh
```

The profiler compiles the production `ScopeComputer` implementation with
Swift optimization enabled, renders deterministic BGRA frames, and measures
the combined waveform/parade and vectorscope path. Because update rate changes
submission cadence rather than per-frame cost, one measurement per resolution
can be expanded across every supported integer update rate from 5 through
30 fps.

## Baseline — 2026-09-01

Hardware: MacBook Pro (Mac17,8), Apple M5 Pro, 64 GB memory.

| Resolution | Mode | Median render | Sustainable rate | 5 fps load | 15 fps load | 30 fps load |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: |
| 360 | Luma | 1.5 ms | 686.0 fps | 1% | 2% | 4% |
| 360 | Parade | 1.0 ms | 967.4 fps | 1% | 2% | 3% |
| 720 | Luma | 4.9 ms | 202.9 fps | 2% | 7% | 15% |
| 720 | Parade | 3.9 ms | 257.1 fps | 2% | 6% | 12% |
| 1080 | Luma | 16.1 ms | 62.0 fps | 8% | 24% | 48% |
| 1080 | Parade | 8.1 ms | 123.6 fps | 4% | 12% | 24% |
| 1440 | Luma | 22.6 ms | 44.2 fps | 11% | 34% | 68% |
| 1440 | Parade | 19.8 ms | 50.4 fps | 10% | 30% | 59% |

All settings complete within their frame budget on this machine. The most
demanding measured combination, 1440-wide luma at 30 fps, uses an estimated
68% of one CPU core for computation. Capture, pixel-format conversion, UI
composition, and playback decoding are outside this focused benchmark and
should still be checked with the existing `ScopePerformance` signposts on the
oldest release-supported hardware.

For captured frames, the runtime worker permits one active computation and one
replaceable pending frame. If end-to-end work exceeds a frame budget, the newest
submission replaces
the pending one instead of creating an unbounded queue. Memory-pressure events
cancel pending scope work, and teardown cancels both active and pending work.

Treat this baseline as comparative rather than universal: thermal state,
hardware, OS, and compiler versions affect absolute timings. Re-run the matrix
on the same hardware before and after renderer changes.
