# Audio loudness analysis

The metadata inspector provides offline loudness analysis for each audio stream.
Choose **Whole File** or **In–Out Range**, then **Measure LUFS** under that stream.
For stereo or 5.1 stored as separate mono tracks, use the new **Programme
Loudness** section to assign channels and measure one combined programme.
See [programme loudness](PROGRAMME_LOUDNESS.md) for eight-mono-track workflows,
explicit speaker mapping, excluded spare tracks and measurement provenance.
The selected range uses the player's existing In and Out timeline markers, in
seconds from the start of the media. Both markers must be finite, the In point
must be non-negative, and the Out point must be later and within the known file
duration. The Out point is exclusive, matching FFmpeg's decoded-sample trim.

Results show integrated loudness (LUFS), loudness range (LU), and true peak
(dBTP) from the bundled FFmpeg `ebur128=peak=true` filter. Sample trimming runs
before that filter, so material outside the selected interval does not affect
the range result. This is analysis of the source stream; player volume, mute,
channel audition, and output routing do not change the measurement.

Changing analysis scope clears results for all streams. Changing In/Out markers
also clears selected-range results and cancels outstanding range jobs. Changing
media or closing the inspector cancels outstanding work. Each running analysis
also has a Cancel button. Generation checks prevent cancelled or replaced jobs
from publishing stale results.

**Copy Metadata as JSON** includes measured values under each stream's `lufs`
object. Range measurements also include `analysisRange.start` and
`analysisRange.end` in seconds. Whole-file results omit `analysisRange`.
Non-finite values, such as negative-infinite peak for digital silence, are
encoded as strings (`"-Infinity"`, `"Infinity"`, or `"NaN"`). Corrected conventional 7.1
measurements include `lufs.weightingCorrection` with value
`bs1770Conventional7Point1RearChannels` and a readable `lufsNote`.
Uncorrected 7.1 results retain `lufsWarning`. Previously exported results
without correction provenance remain decodable and are treated as uncorrected.

## Limits

- These are offline summaries, not live momentary/short-term meters or a
  broadcast standards compliance verdict.
- Conventional eight-channel `7.1` analysis corrects the bundled FFmpeg's rear
  weighting using an analysis-only channel-label mapping. Other eight-channel
  layouts and streams without explicit matching metadata do not receive this
  correction. Uncorrected 7.1 measurements remain qualified in the inspector
  and JSON. This does not establish conformance for immersive layouts.
- Analysis decodes the source up to the Out point, including material before
  the In point; a selection late in a long source can still take time. Cancel remains
  available while it runs.
- Very short or silent selections may not yield meaningful integrated
  loudness or loudness range. Read the values in the context of the selected
  duration; there is no target-level pass/fail indicator.
- A selection with no decoded samples reports an error instead of a loudness
  result. This can happen before a delayed audio stream starts, even when the
  range is within the file's duration. Digital silence still contains samples
  and remains measurable.
- Range selection requires a known file duration. Unknown-duration sources can
  still use whole-file analysis.

## Validation

The complete 404-test Release suite, static analysis, and all 61 release
preflight checks pass on 2026-09-06. The silence fixture uses lossless ALAC in
M4A so it also exercises the metadata parser's supported audio-container path.

`LoudnessAnalysisTests` covers whole-file stream mapping, sample-trim ordering,
invalid/decoded-invalid ranges, and negative stream indices. Its bundled-FFmpeg
test generates a six-second tone whose second half is 20 dB quieter, then
measures non-integer selections in each half and checks their integrated and
true-peak differences plus JSON range-bound round-trip. It also repeats the
quiet selection in a container whose timestamps begin seven seconds above zero
to check that range markers remain relative to the source. A second delayed
audio stream checks that its one-second offset remains aligned with the source
timeline. A generated digital-silence case exercises the actual metadata JSON
export path and verifies that a negative-infinite peak still exports. This verifies selected
sample isolation; it is not a standards certification test.

Additional generated fixtures compare mono, 5.1, and quiet mono tracks in the
same container. They verify independent stream selection, the expected R128
surround-channel weighting and LFE exclusion, unchanged per-channel true peak,
and selected-range consistency. Malformed audio and nonexistent stream
selections must fail instead of returning a measurement. A deterministically
pre-cancelled analysis must report cancellation, after which a fresh analysis
of the same file succeeds. Independent references and focused native
concurrent-job checks are described below; broader playback/performance
acceptance remains separate.

Independent numerical references now supplement the relative-level fixtures.
The tests write Float32 WAV samples directly in Swift; FFmpeg is only
the analyzer, not the signal generator or expected-value oracle. The selected
[EBU Tech 3341 (2023), Table 1](https://tech.ebu.ch/docs/tech/tech3341.pdf)
references cover:

- Cases 1 and 2: absolute integrated calibration at −23 and −33 LUFS (±0.1 LU),
  synthesized independently at 44.1, 48, and 96 kHz.
- Case 4: a 100-second level sequence that exercises absolute and relative
  gating, with an expected integrated result of −23 LUFS (±0.1 LU).
- Cases 15–19: phase-sensitive true peaks at three frequencies relative to
  each sample rate (44.1, 48, and 96 kHz), with 10 ms fades and the specified
  +0.2/−0.4 dB tolerance. The final case reconstructs above full scale despite
  unclipped input samples.

[EBU Tech 3342 (2023), Table 1](https://tech.ebu.ch/docs/tech/tech3342.pdf)
cases 1–4 add independent loudness-range references at 44.1, 48, and 96 kHz.
The four level sequences have expected ranges of 10, 5, 20, and 15 LU, using
the specified ±1 LU tolerance. The five-segment fourth case checks that
relative gating excludes the quietest sections instead of reporting the full
30 dB level span. Each segment is a directly synthesized, in-phase stereo
1 kHz tone lasting 20 seconds; each file receives a fresh analysis.

Thirteen additional 48 kHz fixtures use explicit WAV speaker masks and
independently synthesized channel samples for 2.1, 3.0, 5.1(side), and the
front/LFE portion of 7.1. Isolated front and side speakers verify both their
ordering and their expected loudness; the side surrounds use the 1.41 energy
weight documented in [ITU-R BS.2217-2, Table 1](https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BS.2217-2-2016-PDF-E.pdf).
Expected levels derive from the calibrated stereo sine and the sum of channel
energy weights, with a ±0.1 LU regression tolerance. A separate LFE signal
20 dB above the stereo pair must leave integrated loudness at −23 LUFS while
raising true peak to −3 dBTP in each LFE-bearing layout. The
[WAVEFORMATEXTENSIBLE speaker mask](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ksmedia/ns-ksmedia-waveformatextensible)
sets channel positions directly; no FFmpeg pan or synthesis filter creates
these fixtures.

Conventional 7.1 correction uses the rear ±135° unit energy weight and side
±90° weight of 1.41 from
[ITU-R BS.1770-5, Annex 3, Tables 4–5](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf).
The bundled FFmpeg assigns 1.41 to both pairs. The app now applies
[FFmpeg channelmap](https://ffmpeg.org/ffmpeg-filters.html#channelmap) after
sample trimming, relabelling BL/BR as FLC/FRC in an analysis-only
`7.1(wide-side)` layout. Those labels select unit weights without scaling
samples, so integrated loudness, gating, and LRA receive corrected energy while
true peaks retain original amplitudes. Playback and exported media are unchanged.
The graph uses named inputs; a missing source speaker fails analysis instead of
silently accepting an expanded stereo input. It requires both eight channels
and explicit conventional `7.1` metadata, never channel count alone.

Independent speaker-mask references now isolate all seven non-LFE speakers
at 44.1, 48, and 96 kHz. The former two expected failures are normal standards
assertions. Additional coverage checks mixed front/rear/side energy, loud LFE
peaks, selected ranges, rear-pair relative gating/LRA, rear intersample peaks,
and byte-for-byte Float32 sample preservation through the production graph.
Legacy/corrected JSON provenance and mismatched source-layout rejection are
also covered. The production profiler supplies the same layout metadata as the
inspector so future conventional 7.1 profiles exercise this correction.

This is a selected reference regression set, not full EBU/ITU certification.
Twelve independent transient references add a short, band-limited pulse at
44.1, 48, and 96 kHz, each with amplitudes +0.5, −0.5, +1.2, and −1.2.
The signal is `A × sinc(t / 8)² × cos(πt / 2)`, where
`sinc(u) = sin(πu) / (πu)` and `t` is measured in sample periods from the
pulse center. Its continuous absolute maximum is exactly `|A|`: both factors
have magnitude at most one and reach one at the center. Its highest frequency
is 3/8 of the sample rate, below Nyquist. The center lies halfway between two
samples, keeping the sample peak more than 3 dB below the known continuous
peak. Even the ±1.2 pulses have input samples below full scale.

Swift writes one second of Float32 PCM directly, retaining over 2,000 envelope
widths on either side of the center; the discarded envelope is below 3×10⁻⁸
of the peak. The meter must recover `20 log10(|A|)` dBTP within +0.2/−0.4 dB
and exceed sample peak by more than 2.5 dB. These analytic transient
regressions exercise both polarities and above-full-scale reconstruction;
they are not additional official EBU test vectors. Remaining reference
coverage includes authentic programme material and immersive channel layouts.

Eighteen further analytic cases cover two different pulse families at the same
three sample rates: `0.8 × sinc(t / 12)³ × cos(πt / 3)` has signed envelope
sidelobes and a spectral limit of 7/24 of the sample rate;
`0.8 × sinc(t / 16)² × (cos(πt / 2) + cos(πt / 3)) / 2` combines two carriers
and has a spectral limit of 5/16 of the sample rate. Each has an exact
continuous absolute peak of 0.8 (−1.9382 dBTP), since all factors have
magnitude at most one and equal one at the center. One-second Float32
fixtures place the center halfway between samples. The discarded envelope
bounds are below 1.7×10⁻¹⁰ and 5.4×10⁻⁸ of peak, respectively, at all three
rates. These fixtures are finite approximations to the ideal band-limited
functions, not exactly band-limited finite records.

Each family is measured in the left channel alone, right channel alone, and
both stereo channels with opposite polarities. The last placement would
cancel in an incorrect stereo sum; true peak must remain the maximum of
the individual channels. The same +0.2/−0.4 dB tolerance applies, and the
measured peak must exceed sample peak by 0.8 dB. Independent bundled-FFmpeg
probes of the mono formulas report −1.9 dBTP, except the two-carrier pulse at
44.1 kHz, which reports −2.0 dBTP; their sample peaks are −3.2620 and
−4.0514 dBFS. The new XCTest cases additionally exercise the production
analyzer and all three stereo placements. Three analytic pulse families
still do not establish accuracy for every transient or standards certification.

The Phase 53 continuation passes all 435 integrated Release tests with zero
failures or skips in 111.298 seconds, including the 18 additional transient
cases and direct Float32 7.1 WAVE-to-loudness regression. Static analysis and
all 61 release-preflight checks pass. Evidence is retained temporarily at
`/tmp/aagedal-continuation-full-verified-20260908.xcresult` and
`/tmp/aagedal-continuation-analyze-20260908.log`.

The earlier Phase 52 focused Release loudness suite passes all 27 tests on 2026-09-08,
with zero failures, expected failures, or skips. The final full Release suite
passes all 426 tests in 110.897 seconds, also with no failures or skips, and
Xcode static analysis succeeds. An earlier full run recorded five premature
test-host exits while native UI checks were running; the clean full rerun with
UI automation stopped passed without those exits. Local evidence:
`/tmp/aagedal-transient-loudness-suite-20260908.xcresult`,
`/tmp/aagedal-improvements-full-isolated-20260908.xcresult`, and
`/tmp/aagedal-improvements-analyze-20260908.log`. The interrupted run is retained
separately at `/tmp/aagedal-improvements-full-20260908.xcresult`.

The expanded 415-test Release suite passes without failures or skips on
2026-09-07, as do Xcode static analysis and all 61 release-preflight checks.
The additional calibration/LRA coverage comprises 18 independently synthesized
references across the three sample rates. The subsequent channel-layout coverage
adds 13 references in three tests; neither changes production analysis behavior.

On 2026-09-08 the focused 18-test Release loudness suite and complete 417-test
Release suite pass with no skips or unexpected failures; Xcode static analysis
also passes. That earlier run recorded the two strict expected rear-weight failures
subsequently corrected in Phase 51. This expansion adds ten phase references, four isolated 7.1
speaker references, and JSON coverage ensuring the qualification accompanies
only measured 7.1 results.
The final suite was repeated after the inspector warning wrapping fix:
417 tests passed in 104.997 seconds, followed by successful static analysis.
Local artifacts: `/tmp/improvements-final-rebuilt-20260908.xcresult`,
`/tmp/improvements-final-rebuilt-tests-20260908.log`, and
`/tmp/improvements-final-analyze-20260908.log`.

Phase 51 validation on 2026-09-08 passes all 425 Release tests with zero
failures, expected failures, or skips (110.435 seconds). Static analysis and
all 61 release-preflight checks also pass. The final suite includes a
multi-stream MOV test that obtains the selected 7.1 layout through production
metadata parsing before measuring it. Local temporary artifacts:
`/tmp/loudness-correction-full-20260908.xcresult`,
`/tmp/loudness-correction-full-20260908.log`,
`/tmp/loudness-correction-analyze-20260908.log`, and
`/tmp/loudness-correction-preflight-approved-20260908.log`.
Native layout/VoiceOver acceptance of the revised correction text remains open;
the earlier native warning check below predates this correction.

Empty-range fixtures check both an interval beyond EOF and an interval before
a delayed stream begins. Analysis requires FFmpeg's output clock to advance
before accepting its summary, because FFmpeg can otherwise report success
with default loudness and peak values despite processing no audio samples.
The same fixture verifies that real digital silence and the delayed stream's
audible interval continue to produce results.

Manual checks: mark an In/Out range, measure it, change a marker while another
measurement is running, and confirm no old result appears. Switch back to
Whole File and verify the range label disappears. Copy both result types and
check their JSON bounds. Cancel one stream while another is running and confirm
only the chosen stream stops.

Original ITU voice/music, stereo and 5.1 programme files now supplement the
synthetic references. All three pass the published −23 ±0.1 LKFS integrated
target through the production service, with original file hashes checked before
measurement. [Programme reference methodology and results](AUDIO_PROGRAMME_REFERENCES.md)
describe downloads, reproduction and limits. The optional runner also compares
their LRA to an independent standard-library PCM implementation of EBU Tech 3342,
validated against all four official analytic tone sequences. Calculated values
of 15.8698, 14.5295, and 10.9416 LU agree with production within 0.15 LU for
mono, stereo, and six-channel programmes, respectively (±1 LU regression
tolerance). These are independently derived values, not published programme
LRA targets. The same runner now also compares programme true peaks to an
independent implementation of the published ITU four-phase FIR; the three
results agree within 0.17 dB against a ±0.4 dB project regression tolerance.
Those are derived comparisons, not independently published programme targets.
The original EBU narrow/wide programme set remains inaccessible with HTTP 403
on September 10; its published programme LRA checks and independently
published programme true-peak acceptance remain open. The
[acceptance handoff](AUDIO_PROGRAMME_REFERENCES.md#published-target-acceptance-handoff--2026-09-10)
separates their prerequisites. Additional content/layouts and live meters
remain separate.

## Keyboard and accessibility acceptance

Channel Solo and Mute items in the playback audio menu use native checked
controls. The menu's accessible value includes which channels are enabled;
this describes channel routing, independently of master mute and volume.
Loudness scope, measurement, and cancellation controls identify their audio
stream, and each result exposes its metric label together with its value.

Before claiming Full Keyboard Access or VoiceOver acceptance:

1. Open a multitrack, multichannel file and navigate to the audio menu using
   the keyboard. Solo a channel, mute it, then choose All Channels. Verify
   checked states, enabled-channel descriptions, and audible output agree.
2. Traverse the inspector's controls for each stream. Confirm the stream
   identity and Whole File/In–Out scope are announced without ambiguity.
3. Start two stream measurements and cancel one. Verify the chosen job stops,
   focus remains usable, and the other result includes its metric and units.
4. Select an interval before a delayed stream begins. Verify the empty-audio
   explanation can be reached, then change to an interval containing samples
   and retry successfully.

These are remaining native acceptance checks; source changes and automated
analysis tests do not establish spoken narration or full keyboard traversal.

A focused native control check is recorded in
`AUDIO_QC_NATIVE_CHECK_2026-09-06.md`; it does not close the wider acceptance matrix.

For reproducible whole-file and early/late-range profiling on long multichannel
files, use `scripts/profile-audio-loudness.sh`. The workload and local baseline
are documented in `AUDIO_LOUDNESS_PERFORMANCE.md`; reference accuracy and
concurrent playback acceptance remain separate.

The [September 7 native check](AUDIO_QC_NATIVE_CHECK_2026-09-07.md) verifies two
simultaneous stream jobs, independent cancellation and completion, and cleanup
when the inspector is hidden and reopened. Inspector visibility now explicitly
owns cancellation because native collapse can retain its SwiftUI content.
Cancel Analysis has its own full-width row for an unambiguous target.
Full Keyboard Access and spoken VoiceOver acceptance remain open.


A September 8 native check used a generated one-second 48 kHz, 24-bit PCM
7.1 MOV in the rebuilt Release app. The inspector identified `8 (7.1)`,
exposed the complete qualification in its accessibility tree, and retained
it while displaying a completed silence measurement (−70.0 LUFS, 0.0 LU,
negative-infinite true peak). An initial screenshot caught truncation in the
native List row. The final layout explicitly removes the row's line limit;
a rebuilt screenshot confirms the entire qualification wraps at the normal
approximately 270-pixel inspector width. This is layout and accessibility-tree
evidence, not spoken VoiceOver or Full Keyboard Access acceptance.

The later [September 8 correction check](AUDIO_QC_NATIVE_CHECK_2026-09-08.md)
verifies the revised pre/post-measurement correction text using an isolated
rear-speaker tone, and confirms the complete scope heading after moving it
above the segmented control. Full Keyboard Access and spoken VoiceOver
acceptance remain open.
