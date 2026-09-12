# Live audio meter implementation contract

Design baseline: 2026-09-11. This document completes the design prerequisite
for live Audio QC; it does not implement meters, establish accuracy, or close
the roadmap's live-meter/performance acceptance gates. Product decisions below
are implementation requirements, distinct from the cited standards.

September 12 continuation: the
[DSP/display/decoder/lifecycle/presentation foundations](LIVE_AUDIO_METER_DSP.md)
are implemented with focused numerical and boundary tests. Actual playback
lifecycle wiring, transport pacing, app integration and live-path acceptance
remain; the live acceptance matrix below is open.

## Initial deliverable and measurement identity

Provide per-channel sample peak and true peak, plus aggregate Momentary and
Short-term loudness for one explicitly selected source audio stream. Default
to source A's selected track; the meter has its own visible A/B source selector.
Switching audible A/B monitoring must not silently change the measured source.
Initial supported layouts are mono, stereo, 5.1(side), and conventional 7.1;
sample rates are 44.1, 48 and 96 kHz. Other layouts/rates require acceptance
before support is advertised. Unknown channel roles permit numbered peak
readouts but make aggregate loudness unavailable.

The primary signal is **decoded source PCM**, before app volume, mute,
mute/solo routing, downmix, playback-speed processing and system output gain.
Use original channel order with an explicit speaker map; do not add an LFE
monitor gain. Record decoder version, stream index, sample rate, layout,
source identity, measurement generation and source interval. Decoder DRC and
normalization controls must be disabled and verified for supported codecs. If
that provenance cannot be established, mark the measurement unavailable or
qualified instead of silently treating processed PCM as the source.

Source measurements are not a reading of the loudspeakers or headphones. An
eventual **Monitor output** meter would need an actual post-routing PCM tap,
documented downstream exclusions and its own reset/acceptance path. It must
never be approximated by subtracting the volume slider value from source
readings, or combined with source maxima. It is outside the first implementation.

Do not sum different file streams or A/B sources. Existing offline Whole File
and In–Out analysis remains the route to integrated loudness and LRA; live
readouts never acquire a whole-programme label merely because playback ran
for a long time. Live integrated/LRA accumulation is not included in this
initial contract, and no **EBU Mode** claim is permitted on that basis.

## Standards baseline

These are the referenced algorithm/measurement requirements, not UI defaults:

- ITU-R BS.1770-5 defines K weighting, channel-weighted energy and true-peak
  estimation. Loudness excludes LFE; per-channel peak detection still includes
  it. Integrated gating uses overlapping 400 ms blocks, an absolute −70 LKFS
  threshold and a relative threshold 10 dB below the absolute-gated result.
  Channel weights must follow speaker positions, not channel count alone.
  [ITU-R BS.1770-5, Annexes 1–3](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf).
- Momentary uses an ungated rectangular 0.4-second window; Short-term uses an
  ungated rectangular 3-second window. No extra attack/release smoothing follows
  those windows. Live Short-term updates at least 10 Hz. Full live EBU Mode
  additionally requires integrated measurement, LRA, maxima and specified
  controls/scales; an EBU target preset alone is insufficient. The calibration
  check is in-phase stereo 1 kHz at −18 dBFS peak per channel, reading −18.0
  LUFS. Table 1 specifies signal-specific acceptance tolerances; its −23 dBFS
  stereo tone expects −23.0 ±0.1 LUFS for M/S/I. True-peak cases use
  +0.2/−0.4 dB tolerances. Passing minimum signals does not establish accuracy
  for all inputs.
  [EBU Tech 3341 v4, §§2.1–2.9 and Table 1](https://tech.ebu.ch/docs/tech/tech3341.pdf).

LUFS and LKFS have the same numerical loudness scale; LU expresses a relative
difference. Preset selection must not change the underlying PCM or computed
loudness. It changes labels and reference guides only.
[EBU R 128 v5, footnote 1](https://tech.ebu.ch/docs/r/r128.pdf).

## Presets and honest interpretation

| Preset label | Programme reference | True-peak guide | Interpretation |
| --- | --- | --- | --- |
| EBU R 128 — production reference | −23.0 LUFS | −1.0 dBTP maximum for linear production audio | Entire-programme loudness; different distribution requirements can be stricter. |
| ATSC A/85 — exchange reference | −24.0 LKFS | Below −2.0 dBTP | Exchange without metadata or a prior loudness agreement; measurement method depends on content type. |
| Custom reference | User-entered finite loudness target | Optional user-entered finite ceiling | Persist numeric values with the preset; never imply a named standard. |

EBU R 128 allows ±0.2 LU for measurement error in QC workflows and ±1.0 LU
where the target is impractical, such as live programmes. These are not
Momentary/Short-term limits. Its true-peak measurement tolerance is ±0.3 dB
for signals limited to 20 kHz; tolerance is not additional desired headroom.
[EBU R 128 v5, recommendations h–m](https://tech.ebu.ch/docs/r/r128.pdf).

ATSC's current July 2026 revision gives approximately ±2 dB loudness and
±0.5 dBTP measurement tolerances for exchange; operators should not target
the tolerance edges. Long-form assessment uses dialogue/anchor loudness;
short-form assessment uses integrated full-mix loudness. Source M/S and the
existing full-mix offline result cannot substitute for dialogue gating.
Decoded lossy-file peaks also cannot establish the original pre-encode peaks.
[ATSC A/85:2026-07, §§5.2 and 6](https://www.atsc.org/wp-content/uploads/2026/07/A85-2026-07.pdf),
[official quick reference, Annex M](https://www.atsc.org/wp-content/uploads/2026/07/A85-2026-07-Annex-M.pdf).

Product rules: show the programme target as a reference line, not a green
pass region for M/S. Show true-peak exceedance text independently from loudness
distance. Compare unrounded values to the ceiling (EBU: greater than; ATSC:
greater than or equal to); display one decimal place and retain precision in
diagnostics. Keep measurement tolerances in help, not in the threshold math.
Do not add a universal M/S or LRA limit. Label the ATSC preset **Dialogue
assessment unavailable** until a separately validated method exists. No
compliance badge, CALM assertion, dialnorm verification or automatic gain
normalization belongs to this deliverable. The user's delivery specification
and actual measured interval remain relevant even with a named preset.

## Ballistics and controls: product choices

Compute sample peak from the maximum absolute sample, using 1.0 as digital
full scale; true peak uses a separately validated reconstruction path. Never
derive true peak from sample peak. Both retain values above zero without
clamping. Silence is −∞; unavailable input is **Unavailable**, not silence.

For the initial true-peak implementation, use at least 4× reconstruction at
each supported sample rate, with continuous filter history across input
blocks. Record coefficients, group delay and version. Oversampling ratio alone
does not establish accuracy; validate block boundaries and positive/negative
intersample peaks. Aggregate maximum TP is the largest channel TP, never a sum.

Publish peak display buckets every 50 ms and M/S every 100 ms, based on source
sample timestamps rather than UI timer ticks. DSP must inspect all samples;
each peak bucket retains its maximum even if a UI update is coalesced. A peak
bar attacks immediately and falls at 20 dB per second. A separate peak marker
holds for 2 seconds and then follows that decay. These are app display choices,
not QPPM or EBU loudness ballistics. M/S values receive no such decay.

Retain independent sample-peak, TP, M and S numeric maxima for the current
continuous measurement segment. **Clear Maxima** clears those maxima and
exceedance latches without disturbing filter/window state. **Reset Meters**
starts a new segment and clears filters, windows, bars, maxima and latches.
Both actions must be keyboard reachable and separately named for VoiceOver.
Report units, source/track, sample interval, segment start and state alongside
copied readings; do not append unqualified live values to offline reports.

## Transport, ownership and reset contract

| Event | Required behavior |
| --- | --- |
| Open meters during forward 1× playback | Start at the current source position; do not decode the file from zero. Show **Warming up** until each complete loudness window is available. Peaks may appear once valid samples arrive. |
| Pause or buffering with no sample discontinuity | Freeze at the last consumed source sample; show **Paused** or **Buffering** and its position. Do not feed artificial wall-clock silence. Preserve windows/maxima for a continuous resume. |
| Resume at the next contiguous sample | Continue the same segment; exclude paused wall time from decay, hold and measurement duration. |
| Seek, scrub, frame step, loop wrap, or detected sample gap/duplicate | Invalidate the generation, reset all measurement state and begin a new segment at the new position. Never mix pre-seek history into the new reading. |
| Reverse or non-1× playback | Suspend with **Meters require forward 1× playback**. On returning to 1×, reset and warm up. A future speed-aware signal path requires separate provenance/acceptance. |
| File, selected measurement source/track, decoder, sample rate or layout changes | Cancel old work and clear readings immediately; a new generation owns all subsequent results. Late blocks cannot alter current state. |
| Monitor volume/mute/solo or audible A/B switch | Source readings remain unchanged. Keep the measured source label visible. |
| Preset change | Preserve computed values and segment; recompute threshold indication from current maxima with the new guide. |
| EOF | Drain remaining valid samples and filter tail with explicit source-boundary accounting; freeze with **Ended**. Do not invent a full loudness window for a short file. |
| Hide/close meter panel, close window, remove measured B | Cancel capture/decode, release buffers and clear the segment. Reopening starts fresh; no invisible analysis continues. |
| Decode failure, malformed PCM, overrun or timestamp loss | Show actionable **Unavailable** with diagnostic context; clear current validity and cancel the worker. Retry starts a new generation. Never conceal dropped analysis samples as a valid measurement. |

For timestamp-preserving geometry reloads, still start a new meter segment:
decoder continuity has been broken even if visual transport resumes at the
same frame. Playback-ready is not enough to establish audio timestamp continuity.

## Bounded processing and implementation acceptance

Use one window-owned measurement coordinator and at most one serial decoder/
DSP worker for the chosen source. If backend PCM cannot provide the required
pre-monitor signal, one persistent source decoder is permitted; repeated
ffmpeg launches per display tick are not. Decode only near the current
position, with no more than 250 ms of queued PCM ahead of consumption and
enough fixed history for the largest loudness window and reconstruction filter.
Keep the entire meter-owned PCM/DSP working set below 32 MiB for the initial
eight-channel/96 kHz maximum. This excludes measured decoder overhead, which
must be reported separately. Neither storage nor task count may grow with
file duration. No temporary whole-file PCM and no unbounded sample histories.

Audio callbacks must not block on UI, logging, disk, allocation or decoding.
Coalesce UI snapshots, never silently discard DSP input. Process backpressure
must have a bounded queue and explicit overrun failure. A hidden panel must
not retain worker ownership. Killing or replacing a generation must terminate
its subprocess across the cancellation-before-attachment race.

Required evidence before checking live-meter implementation/accuracy complete:

1. Drive the actual production PCM path with pinned EBU minimum signals and
   independent ITU-based references, including time-varying M/S and maxima,
   all supported rates/layouts, LFE isolation, channel weights, polarity and
   filter-block boundaries. Retain each reference's own tolerance and measured
   error; do not substitute one generous global tolerance. Reuse applicable
   [offline reference fixtures](AUDIO_PROGRAMME_REFERENCES.md), not their
   historical pass status.
2. Verify source readings remain invariant while changing monitor routing and
   volume on both playback backends. Verify compressed-source decoder gain
   behavior and compare with independent decoding. Unknown gain processing
   blocks an unqualified source measurement.
3. Exercise every lifecycle row with delayed blocks and decoder attachment,
   rapid A/B/track replacement, cancellation, EOF, corrupt input and stalls.
   Check no stale readings, orphan processes, duplicated samples or accumulated
   windows across discontinuities. Test below/at/above preset thresholds using
   unrounded values.
4. On the documented base-M1 release floor, measure ordinary and concurrent
   UHD/HDR comparison playback with meters, scopes and thumbnails. Record CPU,
   GPU, app/decoder peak and steady memory, queue high-water marks, sample gaps,
   publication latency and thermal state. Run representative 1/8/24-hour
   sources plus a sustained 30-minute observation; file duration alone is not
   playback-soak evidence. Require zero analysis overruns, no playback
   regression, 95th-percentile snapshot age below 250 ms after warm-up, bounded
   memory/task counts, and cancellation completion within one second. These
   budgets are product acceptance targets, not standards limits.
5. Complete keyboard-only source selection, preset selection, clear/reset,
   error recovery and closing; verify spoken VoiceOver reads snapshots on
   demand without announcing every tick. Colour must not be the only
   indication of exceedance, unavailable data or warm-up.

All acceptance above remains **not run** for this design. The standards links
were checked on 2026-09-11; use their named editions when recording results,
and review changes before upgrading an algorithm or preset definition.
