# Authentic ITU live sample/true-peak comparisons — 2026-09-30

The opt-in optimized Release test passes in 250.041 seconds without skips,
failures or runtime warnings. The shipping timestamp-verified live decoder and
Swift DSP retain per-channel maxima after EOF FIR drainage. All nine channels'
sample peaks and reconstructed true peaks agree exactly (0 dB difference) with
the independent integer-PCM Annex 2 calculation.

| Original programme | Channels | Source frames | Maximum sample-peak error | Maximum true-peak error |
| --- | ---: | ---: | ---: | ---: |
| Mono voice/music | 1 | 3,998,849 | 0 dB | 0 dB |
| Stereo | 2 | 3,991,527 | 0 dB | 0 dB |
| Six-channel centre voice | 6 | 3,994,582 | 0 dB | 0 dB |

The numerical tolerance is 1e-7 dB. Lossless PCM16 is exactly representable in
the decoder's Float32 output, and both independent implementations use the same
published four-phase FIR. This checks decoding and numerical implementation;
it is not a published programme target or a device calibration tolerance.
Every channel, including LFE, participates. Exact silence is represented by null
and must match the independently calculated channel's silence.

The original hash-pinned WAVs and their provenance are described in
[the reference contract](../../AUDIO_PROGRAMME_REFERENCES.md). The six-channel
live preparation retains unchanged PCM words/order with the explicitly documented
`5.1(side)` speaker mask. Source audio is outside this repository.

The measurement receipts require the exact original frame count, source-rate
time base, zero synthetic initial silence, all 50-ms publications plus the final
snapshot, and eleven FIR-tail frames without advancing the source endpoint.
The independent report retains full-precision per-channel actual/reference
values and differences, rather than rounded whole-programme output.

The same runner reconfirms the three official integrated targets, independent
LRA and offline true-peak comparisons, and 4,896 live M/S readings within
0.0005 LU. A final independent rerun against the unchanged live receipts verifies
the explicit-null rejection added by code review; all sixteen calculator and
validator tests pass. Missing/duplicate sources, wrong decoder/layout provenance,
incomplete EOF/coverage, non-finite values and per-channel silence mismatches fail.

Reproduction:

```bash
ITU_LOUDNESS_DERIVED_DATA=/tmp/aagedal-itu-live-dd-20260930 \
  scripts/check-itu-programme-loudness.sh \
  /tmp/new-itu-live-peak-check /tmp/aagedal-itu-live-references-20260930
```

Full logs, calculator snapshots, oracle windows and result bundle remain at
`/private/tmp/aagedal-itu-live-peaks-complete-20260930`. Source hashes and full
artifact hashes accompany the retained summaries. This is working-tree
engineering evidence with parallel changes, separate from clean-candidate
verification. Earlier build attempts caught concurrent test isolation errors;
their separate failed logs remain under `/private/tmp/aagedal-itu-live-peaks*`.

These whole-programme live maxima do not establish per-bucket peak timing,
display ballistics, owning playback/session behavior, native audio output,
transport changes, compressed authentic inputs, hardware or spoken accessibility
acceptance. Those gates remain open.
