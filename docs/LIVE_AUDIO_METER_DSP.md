# Live audio meter calculation foundation

Implementation: September 12, 2026. This completes bounded calculation,
source-decoder, lifecycle ownership, presentation and window-session integration for the
[live-meter contract](LIVE_AUDIO_METER_DESIGN.md). The source decoder is now
wall-clock paced at 1× and its process can remain continuous across pause and
buffering. Player controllers now publish typed clock, transport, scrub, seek,
frame-step, loop, source and audio-track events, and the coordinator applies a
tested drift/failure policy to them. A window-owned session now subscribes that
seam and exposes an activating panel in the app. The live Audio QC roadmap and
release gates remain open because representative-media and production acceptance
are not complete. The decoder transport now verifies each raw PCM packet
against FFmpeg's same-process frame timestamps, size and checksum. It normalizes
at most one millisecond of container timestamp quantization while rejecting
material gaps; that closes the protocol-design gap without standing in for
real-source acceptance.

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

The window coordinator now sends Clear Maxima to the serial DSP worker through
an ordered revision on its bounded worker gate. Every worker snapshot carries
the revision applied before calculation, and the one-slot presentation handoff
rejects maxima from older revisions while continuing to consume their current
readings for source-time ballistics. This also covers an in-flight or exact-
bucket EOF revision: a pre-clear peak cannot reappear after the UI has cleared
it, while FIR-tail peaks actually calculated after the clear remain eligible.

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

`LiveAudioMeterDecoder` launches the bundled FFmpeg, identifies the
selected source and zero-based audio-stream ordinal, disables supported decoder
gain processing, preserves the declared sample rate/channel count, and streams
little-endian Float32 PCM into the calculation core. FFmpeg's tee muxer writes
each encoded packet as raw PCM on stdout and as a `framecrc` record on stderr.
The meter admits a packet only after verifying its PTS/DTS continuity, declared
`1/sampleRate` time base, frame and byte counts, and Adler-32 checksum against
the exact PCM bytes. Arbitrary pipe boundaries are reassembled without treating
callback order as timestamp order. During active streaming, unmatched data on
either pipe is capped at 250 ms and applies backpressure; termination releases
waiters so the OS-bounded final pipe tail can be reconciled or rejected. Missing headers, gaps, malformed records,
checksum differences, truncated PCM and incomplete framing fail the segment.
Completion records the decoder version, arguments, sample format, timestamp
protocol, time base and verified frame count as provenance.

Seeking uses a bounded hybrid: input seeking stops long files from decoding from
the beginning, while at most one second of immediately burst decoder preroll is
trimmed on the output side. This preserves exact generated AAC, ALAC and MP4
AC-3 intervals at a requested source-sample boundary and avoids the AAC priming
loss observed with input-only seeking. Generated fixtures establish exact seek
behavior; representative production sources remain a separate acceptance gate.

This decoder is deliberately not a playback coordinator. It requests native
1× input pacing and caps catch-up at 1× so a temporarily stalled reader cannot
race forward afterward. The fixed 50 ms processor buffer remains below the
DSP's 250 ms input ceiling. A per-generation condition gate admits no PCM beyond
the playback clock plus 250 ms; a large stdout callback blocks at the exact
byte boundary and applies pipe backpressure before excess PCM is queued or
processed. Pause and buffering suspend admission, resume wakes it, and
generation cancellation wakes blocked consumers before process teardown.
Wall-clock pacing and bounded admission still do not prove alignment with the
active player clock. The timestamp-verified packet stream prevents decoder gaps from
being hidden by contiguous raw bytes, but its seek alignment and clock behavior
must still be validated on representative real compressed sources.

`LiveAudioMeterCoordinator` now supplies the isolated window-ownership boundary:
one decode task, monotonically changing generations, stale result rejection,
one-slot post-DSP presentation coalescing, cancellation on replacement/close/
deinitialization, clean restart causes, retry, EOF, and explicit lifecycle
states. The coordinator now retains a race-safe process control for each worker.
Pause and buffering stop the attached FFmpeg process without ending its pipe,
freeze queued presentation, and resume the same decoder/DSP generation when the
source identity is unchanged. Suspend-before-attachment is remembered, and
cancellation still terminates a stopped process. Seek, loop, reload, speed and
source discontinuities continue to create clean generations.

`LiveAudioMeterPlaybackEvent` is the typed player seam for periodic clock and
transport state, interactive scrubbing, EOF, seek/frame-step/loop boundaries,
and source or selected-track replacement. `LiveAudioMeterClockPolicy` compares
the reduced DSP endpoint with the measured source clock, fails outside ±250 ms,
and uses 200/100 ms suspend/resume hysteresis inside that bound. Unsupported
speed invalidates the segment and returning to forward 1× restarts at the
current player clock. These policies are wired into the coordinator and covered
by focused tests. `LiveAudioMeterSession` resolves the selected A/B source,
subscribes to the correct controller, waits for track and late-metadata readiness,
and owns decoder lifetime through panel or player-window closure.

`LiveAudioMeterPlaybackSource` provides the typed handoff from a selected A/B
track to the decoder. It preserves the zero-based audio-only stream order used
by `0:a:N`, keeps container stream identity separately for diagnostics, rounds
start time once to an exact source-sample position, and clamps it to the source
duration. Mono, stereo, `5.1(side)` and conventional `7.1` receive explicit DSP
speaker maps. Other one-to-eight-channel layouts retain numbered peak meters
but do not guess loudness weights; missing or unsupported format data produces
an actionable failure.

The frame-timestamp side channel also declares the layout produced by FFmpeg.
Mono, stereo, `5.1(side)`, and conventional `7.1` must match the expected name
exactly before their speaker weights can be used. Unknown layouts must still
report a parseable matching channel count and remain peak-only. An absent,
unrecognized, or contradictory decoder layout fails the measurement rather
than allowing metadata labels to stand in for decoded-stream evidence.

`LiveAudioMeterViewState` and `LiveAudioMeterView` provide a reusable,
accessibility-labelled presentation for A/B source choice, sample and true-peak
bars/holds/maxima, Momentary and Short-term loudness, EBU/ATSC/custom guides,
status, diagnostics and measurement provenance. Reference preferences are
persisted with finite-value validation. Exact, unrounded EBU (`>`) and ATSC
(`≥`) decisions remain visible in text rather than colour alone. The view owns
no decoder, DSP or playback state. `LiveAudioMeterWindowController` mounts it in
an activating, resizable per-player panel and preserves command routing to the
owning player while the panel is key. Active readings identify their source and
track; complete decoder provenance remains pending until EOF.
Stable identifiers cover the source/reference/custom controls, status, channel
and loudness readings, diagnostics, provenance, and actions. Dynamic readings
are marked as frequently updated so native accessibility checks can read them
on demand without treating every visual refresh as a new announcement.

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
original decoder tests cover arbitrary byte boundaries, fixed buffering,
malformed and truncated PCM, final revision, source identity/arguments, and a
real bundled-FFmpeg WAVE decode with versioned provenance. The decoder suite also
covers worker admission/cancellation, bounded long-seek arguments, exact
generated AAC/ALAC/AC-3 seek-interval and gain checks, packet framing/checksums,
44.1/96 kHz and 5.1 framing, two-way backpressure/cancellation, final cross-pipe
shutdown ordering, and actual initial/midstream timestamp-gap rejection. Six presentation tests cover
preference validation and exact EBU/ATSC threshold wording. A focused Debug run
of these suites plus settings/numeric-default regressions passes 47 tests. Seven
coordinator tests cover stale callback rejection, one-slot UI coalescing,
pause/buffering freeze and clean resume, every restart cause, retry, EOF, and
cancellation before/after attachment and at deinitialization. These 54 focused
tests pass; Release production verification remains the separate
build/preflight gate.
The focused decoder/coordinator/process run now passes 24 tests, including an
actual paced one-second bundled-FFmpeg decode, same-generation pause/buffering
continuity, suspend before and after attachment, resume, and cancellation while
stopped. These are calculation and process-control tests; synthetic PCM is not evidence of a validated live
source decoder or all programme/transient families.

The timestamp-verified continuation passes the full 649-test Debug suite with no
failures and one expected opt-in real-volume-exhaustion skip. It adds focused
coverage for current-clock startup/retry, source replacement, late metadata,
preference persistence, auxiliary-panel command routing, malformed-snapshot
diagnostics, complete delivery of final subprocess bytes, one-callback admission
limits, suspend/resume, cancellation of blocked consumers, actual bundled-
FFmpeg pipe backpressure at the playback boundary and compressed-seek sample
accuracy, packet framing, both-side backpressure, safe process termination and
source-relative gap retention. Static analysis passes. All 61 release-preflight
checks pass outside the restricted workspace sandbox; the sandbox cannot reach
the normal code-signing trust services and reports a false-negative strict
bundled-FFmpeg signature result.

A subsequent focused session run passes all six tests and closes stale recovery
after source changes: Retry and Reset cannot revive a retained old URL or stream
while replacement metadata is unresolved, and an unsupported selected track
cannot restart the prior track. The next source-readiness revision or a later
supported track starts only its newly resolved request. This is synthetic
lifecycle coverage, not representative-media or native accessibility evidence.

The next 60-test focused integration run covers decoder, playback-source,
coordinator, session, and the generated compressed production path. It confirms
exact framecrc layout identity for real bundled-FFmpeg stereo, `5.1(side)`, and
`7.1` decodes; rejects missing/mismatched layouts; retains peak-only readings
for explicit nonstandard one/two-channel maps; and prevents unsupported-speed
restoration from reviving a replaced source. All 60 tests pass in Debug. This is
generated-media engineering evidence, not representative-programme acceptance.

Each peak row now includes its channel name in the accessibility label (for
example, “Front left, Sample peak”), avoiding ambiguous repeated peak identities
in multichannel layouts. Spoken VoiceOver and complete keyboard traversal remain
native acceptance work.

A preliminary optimized standalone check on this development Mac processed ten
seconds of eight-channel 96 kHz PCM in about 0.13 seconds. It excludes decoder,
UI, scheduling and thermal costs and is not a release-floor performance result.

Remaining work:

- Validate the timestamp-verified decoder on representative real compressed
  sources. Exercise drift failure, seek/loop/reload, EOF revision, cancellation,
  retry and overrun end to end through the mounted production path.
- Production-path numerical references, compressed-source gain checks and
  monitor-routing invariance on both backends.
- Base-M1 concurrent-playback performance, sustained bounded-work observation,
  keyboard operation and spoken VoiceOver acceptance.

See the contract for the complete acceptance matrix; this foundation does not
reduce its scope or mark live meters as shipped.
