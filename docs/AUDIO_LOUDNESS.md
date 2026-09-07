# Audio loudness analysis

The metadata inspector provides offline loudness analysis for each audio stream.
Choose **Whole File** or **In–Out Range**, then **Measure LUFS** under that stream.
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
encoded as strings (`"-Infinity"`, `"Infinity"`, or `"NaN"`).

## Limits

- These are offline summaries, not live momentary/short-term meters or a
  broadcast standards compliance verdict.
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
The tests write stereo Float32 WAV samples directly in Swift; FFmpeg is only
the analyzer, not the signal generator or expected-value oracle. The selected
[EBU Tech 3341 (2023), Table 1](https://tech.ebu.ch/docs/tech/tech3341.pdf)
references cover:

- Cases 1 and 2: absolute integrated calibration at −23 and −33 LUFS (±0.1 LU),
  synthesized independently at 44.1, 48, and 96 kHz.
- Case 4: a 100-second level sequence that exercises absolute and relative
  gating, with an expected integrated result of −23 LUFS (±0.1 LU).
- Cases 15–19: phase-sensitive true peaks at three frequencies, with 10 ms
  fades and the specified +0.2/−0.4 dB tolerance. The final case reconstructs
  above full scale despite unclipped input samples.

[EBU Tech 3342 (2023), Table 1](https://tech.ebu.ch/docs/tech/tech3342.pdf)
cases 1–4 add independent loudness-range references at 44.1, 48, and 96 kHz.
The four level sequences have expected ranges of 10, 5, 20, and 15 LU, using
the specified ±1 LU tolerance. The five-segment fourth case checks that
relative gating excludes the quietest sections instead of reporting the full
30 dB level span. Each segment is a directly synthesized, in-phase stereo
1 kHz tone lasting 20 seconds; each file receives a fresh analysis.

This is a selected reference regression set, not full EBU/ITU certification.
Remaining reference coverage includes authentic programme material,
transient true peaks, and additional channel layouts. True-peak phase
references currently cover 48 kHz; the additional sample rates cover
calibration and synthetic LRA.

The expanded 410-test Release suite passes without failures or skips on
2026-09-07, as do Xcode static analysis and all 61 release-preflight checks.
The additional calibration/LRA coverage comprises 18 independently synthesized
references across the three sample rates; it does not change analysis behavior.

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
