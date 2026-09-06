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
- Range selection requires a known file duration. Unknown-duration sources can
  still use whole-file analysis.

## Validation

The complete 400-test Release suite, static analysis, and all 61 release
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

Manual checks: mark an In/Out range, measure it, change a marker while another
measurement is running, and confirm no old result appears. Switch back to
Whole File and verify the range label disappears. Copy both result types and
check their JSON bounds. Cancel one stream while another is running and confirm
only the chosen stream stops.
