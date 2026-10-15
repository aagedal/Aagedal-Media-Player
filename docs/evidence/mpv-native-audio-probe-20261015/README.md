# Native audio probe acceptance — 2026-10-15

Release arm64 app build and 65 hosted tests pass on macOS 27.0.1, with zero
failures or skips. Both `MPV_NATIVE_AUDIO_PROBE_ACCEPTANCE: 9 signals` and
`MPV_NATIVE_SCOPE_APP_ACCEPTANCE` are present in the successful test run.

The [comparison attachment](native-source-dsp-comparison.json) retains actual
libmpv audio-filter results versus the existing Swift DSP. Cases include mono,
stereo, 5.1(side), conventional 7.1, 44.1/48/96 kHz, silence, LFE isolation, a
10-ms early transient and intersample peaks. The first query waits 3.35 seconds,
so the transient is retained by cumulative filter peaks, not by frequent polls.

Sample peak and independently reduced PCM RMS agree within 0.001 dB. Finite
M/S readings agree within 0.1 LU for supported equivalent weighting. The largest
observed true-peak difference against the existing Annex 2 DSP is 0.061 dB in
these fixtures (test tolerance 0.4 dB). This does not establish equivalence for
all signals or low amplitudes: FFmpeg's metadata rounds linear peaks to three
decimal places, and zero is displayed as “below precision.”

The rear-only conventional 7.1 case is **deliberately different**: raw FFmpeg
momentary loudness is 1.4924 LU higher than the corrected source DSP. Silent and
LFE-only cases retain negative-infinite source loudness; the raw FFmpeg filter
reports its finite floor. The prototype does not normalize these differences
or replace the source readings.

For these zero-origin generated fixtures, the filter sample count divided by
sample rate is approximately 0.44–0.49 s ahead of the player clock at query.
This exceeds the source meter's 250-ms alignment bound. Filter sample counts
are not an actual frame-PTS interface; these observations are not a general
latency calibration or a physical audio-output measurement.

Every case runs with global mute, zero volume and a downstream channel audition
filter. Native readings still match input PCM. Removing the probe preserves
the other filter and permits a subsequent exact seek/restart. A fresh filter
after seeking past the early transient has no old maximum or completed
short-term window. Session tests cover disabled behavior, unavailable filters,
one outstanding query, stale replies, player replacement and deinitialization.

The same combined dependency passes SDR/PQ/HLG native waveform/parade/vectorscope
integration, display-capture fallback and stop rejection. Thirteen raster parser
tests pass; this run does not repeat the separate 31-case native-raster hardware
acceptance or claim complete equivalence of the changed dependency closure.

Candidate: `build/native-audio-probe-candidate-20261015/Aagedal Media Player.app`.
Enable `AAGEDAL_MPV_AUDIO_PROBE=1` in its process environment and open Live Audio
Meter during forward 1× MPV playback. Ordinary launches omit the probe.

The [candidate receipt](candidate-receipt.json) identifies the pinned scope
libmpv and seven verified arm64 FFmpeg overlays; no dependency compilation was
performed. [Source/app hashes](source-and-app-identity.json) identify the tested
implementation and binary. [XCTest summary](tests-summary.json) records 65/65
passing tests. Full local logs and result bundle are under
`/private/tmp/aagedal-player-audio-probe-20261015/` (`build-final.log`,
`tests-final.log`, `tests-final.xcresult`).

This completes the comparison prototype, not a shipping source-meter
replacement. The source FFmpeg decoder stays active. No decoder-elimination CPU
or memory gain is claimed. Compressed-media gain, long-duration behavior,
physical latency and a timestamped native provider remain future work. See
[the implementation and reproduction notes](../../MPV_NATIVE_AUDIO_PROBE.md).
