# Live audio meter calculation foundation

Implementation: September 12, 2026. This completes bounded calculation,
source-decoder, lifecycle-ownership and presentation foundations for the
[live-meter contract](LIVE_AUDIO_METER_DESIGN.md). It does **not** connect those
pieces to playback transport, pace decoding against playback, or expose the
presentation in an app window. The live Audio QC roadmap and release gates
remain open.

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

## Decoder and presentation foundations

`LiveAudioMeterDecoder` launches the signed bundled FFmpeg, identifies the
selected source and zero-based audio-stream ordinal, disables supported decoder
gain processing, preserves the declared sample rate/channel count, and streams
little-endian Float32 PCM directly into the calculation core. Arbitrary stdout
boundaries are reassembled into complete interleaved frames in a fixed 50 ms
buffer. Truncated, non-finite or discontinuous input fails the segment rather
than publishing partial success. Completion records the decoder version,
arguments, source request and sample format as provenance.

This decoder is deliberately not a playback coordinator. A direct call will
decode as quickly as FFmpeg supplies samples; transport pacing, bounded
ahead-of-playback work and actual player-event integration remain outside it.

`LiveAudioMeterCoordinator` now supplies the isolated window-ownership boundary:
one decode task, monotonically changing generations, stale result rejection,
one-slot post-DSP presentation coalescing, cancellation on replacement/close/
deinitialization, clean restart causes, retry, EOF, and explicit lifecycle
states. Because the decoder is not yet a controllable paced session, pause or
buffering conservatively cancels the worker and freezes the displayed snapshot;
resume requires a new source-position request and DSP generation. It does not
pretend to preserve continuous filter history while FFmpeg runs ahead.

`LiveAudioMeterViewState` and `LiveAudioMeterView` provide a reusable,
accessibility-labelled presentation for A/B source choice, sample and true-peak
bars/holds/maxima, Momentary and Short-term loudness, EBU/ATSC/custom guides,
status, diagnostics and measurement provenance. Reference preferences are
persisted with finite-value validation. Exact, unrounded EBU (`>`) and ATSC
(`≥`) decisions remain visible in text rather than colour alone. The view owns
no decoder, DSP or playback state and is not yet mounted by the application.

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
The calculation/display foundation contributes 23 tests, including explicit
Annex 3 rear-versus-side speaker checks at every supported sample rate. Nine
decoder tests cover arbitrary byte boundaries, fixed buffering, malformed and
truncated PCM, final revision, source identity/arguments, and a real bundled
FFmpeg WAVE decode with versioned provenance. Six presentation tests cover
preference validation and exact EBU/ATSC threshold wording. A focused Debug run
of these suites plus settings/numeric-default regressions passes 47 tests. Seven
coordinator tests cover stale callback rejection, one-slot UI coalescing,
pause/buffering freeze and clean resume, every restart cause, retry, EOF, and
cancellation before/after attachment and at deinitialization. These 54 focused
tests pass; Release production verification remains the separate
build/preflight gate.
Final Xcode static analysis and all 61 release-preflight checks also pass.
These are calculation tests; synthetic PCM is not evidence of a validated live
source decoder or all programme/transient families.

A preliminary optimized standalone check on this development Mac processed ten
seconds of eight-channel 96 kHz PCM in about 0.13 seconds. It excludes decoder,
UI, scheduling and thermal costs and is not a release-floor performance result.

Remaining work:

- Wire the generation-isolated coordinator and reusable presentation to their
  owning player window, selected A/B source/track and actual playback events.
- Forward 1× transport pacing, bounded ahead-of-playback buffering, genuinely
  continuous pause/resume with a controllable decoder session,
  seek/loop/reload invalidation, EOF revision, cancellation, retry and overrun
  behavior through the real playback paths, with verified timestamps and
  rejection of decoder/playback drift.
- Mount the reusable meter presentation in the application and connect its A/B
  selector, reference controls, clear/reset/retry actions and status diagnostics
  to the owning playback window.
- Production-path numerical references, compressed-source gain checks and
  monitor-routing invariance on both backends.
- Base-M1 concurrent-playback performance, sustained bounded-work observation,
  keyboard operation and spoken VoiceOver acceptance.

See the contract for the complete acceptance matrix; this foundation does not
reduce its scope or mark live meters as shipped.
