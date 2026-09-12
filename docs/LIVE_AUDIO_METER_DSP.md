# Live audio meter calculation foundation

Implementation: September 12, 2026. This completes a bounded calculation and
display foundation for the [live-meter contract](LIVE_AUDIO_METER_DESIGN.md).
It does **not** add a live meter panel or connect measurements to a playback
decoder. The live Audio QC roadmap and release gates remain open.

## Measurement core

`LiveAudioMeterDSP` accepts contiguous, interleaved Float source PCM with an
explicit sample rate, speaker layout and initial source sample position. It
supports 44.1, 48 and 96 kHz, with explicit mono, stereo, 5.1(side) and conventional
7.1 speaker orders. Unknown roles permit numbered peaks while loudness stays
unavailable; channel count never silently invents a speaker map.

The two K-weighting stages use a sample-rate parameterization that reproduces
the published 48 kHz coefficients. Each speaker is filtered independently;
LFE contributes to peaks but not loudness. Side surround energy receives the 1.41 weight; conventional 7.1 rear
±135° speakers retain unit weight under Annex 3, matching the existing offline
correction rather than the bundled FFmpeg's default 7.1 map. The source specification is
[ITU-R BS.1770-5](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf);
the filter parameterization is also documented in
[libebur128's filter initialization](https://github.com/jiixyj/libebur128/blob/master/ebur128/ebur128.c).

Peaks publish in 50 ms source-sample buckets. Ungated rectangular Momentary
(400 ms) and Short-term (3 s) windows publish every 100 ms after the complete
window exists, without adding silence for startup or pauses. Each snapshot
retains a separate `loudnessEndFrame`, so the intervening peak update does not
pretend that an older loudness reading describes a newer interval. Silence is
negative infinity; insufficient history and unknown speaker roles are nil.

True peak uses all four published Annex 2 FIR phases with twelve samples of
continuous history per channel. The algorithm identifier is
`bs1770-5-k-weighting-annex2-fir4-v1`; nominal reconstruction delay is 5.875 input
frames. This is a reconstruction measurement, not a relabelled sample peak.
Values above full scale remain representable. At EOF, eleven zero frames drain
only the FIR; they never extend the reported source endpoint or loudness windows.
An exact-bucket EOF revises the last peak bucket instead of inventing a silent
new bucket. `isFinal` distinguishes this revision; the display's
`reviseFinalPeak` preserves source time and does not restart an unchanged hold.

## Bounds and failure behavior

The engine retains sixty 50 ms energy sums and fixed per-channel filter/peak
state. Input blocks may contain at most 250 ms of PCM; at eight channels/96 kHz
that is 768,000 bytes of Float input. A call returns at most five snapshots.
Neither sample history nor an output queue grows with file length. The engine
owns no tasks, decoders, temporary PCM files or UI timers. Callers must separately
bound decoder queues and coalesce presentation without dropping DSP samples.

A gap, duplicate source position, incomplete interleaved frame, non-finite PCM,
oversized block or source-position overflow rejects the entire input block and
invalidates the segment. No more valid snapshots can be produced from that
instance. A new instance is the explicit reset boundary for seek, source/format
replacement, speed change or recovery. Calling with no PCM does not advance
source time. EOF is terminal and cannot be applied twice.

Clear Maxima preserves filters/windows and the current peak bucket, but clears
independent numeric maxima. Peaks measured before clearing cannot relatch from
a previously accumulated bucket; subsequently reconstructed samples can still
contribute through the retained FIR history.

## Display foundation

`LiveAudioPeakDisplay` supplies immediate attack, 20 dB/s decay and an independent
two-second marker hold in source sample time. Reset removes all display history.
`LiveAudioMeterReference` has EBU production, ATSC exchange and validated finite
custom reference values. EBU uses a strict greater-than ceiling; ATSC uses
greater-than-or-equal, both before display rounding. Presets only guide display;
they never alter PCM or establish compliance. ATSC retains the explicit dialogue
assessment limitation. Independent display maxima and reference changes retain
and recompute the true-peak exceedance latch.

## Verification and remaining integration

`LiveAudioMeterDSPTests` covers tone calibration at all three rates, warm-up,
time-varying windows, comparison with independent FFmpeg M/S calculations,
LFE/surround isolation, silence versus unknown roles, polarity and intersample
peaks, arbitrary input-block boundaries, FIR tail, exact/partial-bucket EOF,
maxima/reset and permanently invalidated bad input. Display tests cover decay,
hold, exact preset boundaries, invalid inputs and final-bucket revision.
The full September 12 Release run passes 578 tests with zero failures or skips,
including the official ITU offline references and actual APFS recovery. Evidence:
`/tmp/aagedal-meter-programme-final-apfs-20260912/Tests.xcresult` and `summary.json`.
The new calculation/display foundation contributes 23 tests, including explicit
Annex 3 rear-versus-side speaker checks at every supported sample rate.
Final Xcode static analysis and all 61 release-preflight checks also pass.
These are calculation tests; synthetic PCM is not evidence of a validated live
source decoder or all programme/transient families.

A preliminary optimized standalone check on this development Mac processed ten
seconds of eight-channel 96 kHz PCM in about 0.13 seconds. It excludes decoder,
UI, scheduling and thermal costs and is not a release-floor performance result.

Remaining work:

- A window-owned, generation-isolated source-PCM decoder and coordinator with
  verified unprocessed signal provenance, stream identity and timestamps.
- Forward 1× transport pacing, bounded ahead-of-playback buffering, pause/resume,
  seek/loop/reload invalidation, EOF revision, cancellation, retry and overrun
  behavior through the real playback paths.
- The visible A/B measurement selector, source/track/interval diagnostics,
  persisted reference preferences, peak/loudness views and accessible controls.
- Production-path numerical references, compressed-source gain checks and
  monitor-routing invariance on both backends.
- Base-M1 concurrent-playback performance, sustained bounded-work observation,
  keyboard operation and spoken VoiceOver acceptance.

See the contract for the complete acceptance matrix; this foundation does not
reduce its scope or mark live meters as shipped.
