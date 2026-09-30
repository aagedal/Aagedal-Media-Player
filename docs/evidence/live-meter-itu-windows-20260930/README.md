# Authentic ITU live-decoder/DSP window comparisons — 2026-09-30

The opt-in Release test passes on the development Mac in 250.129 seconds.
All 2,487 momentary and 2,409 short-term readings agree with independent
FFmpeg `ebur128` readings within 0.0005 LU. The test's acceptance tolerance
is 0.1 LU; the observed difference is within the oracle's three-decimal output
precision. Each reading is matched at its exact exclusive source-sample
endpoint, on the 100-ms grid after its complete 400-ms or 3-second window.

| Original programme | Momentary readings | Short-term readings | Maximum M error, LU | Maximum S error, LU |
| --- | ---: | ---: | ---: | ---: |
| Mono voice/music | 830 | 804 | 0.0004996883 | 0.0004992254 |
| Stereo | 828 | 802 | 0.0004989346 | 0.0004999778 |
| Six-channel centre voice | 829 | 803 | 0.0004998206 | 0.0004984697 |

The original ITU WAVs were freshly downloaded from the three official archives
in [the reference contract](../../AUDIO_PROGRAMME_REFERENCES.md); all original
SHA-256 identities match the existing pinned references. No programme audio is
stored in the repository. The six-channel original lacks a speaker mask, so
its unchanged PCM words/order were placed in a temporary `5.1(side)` extensible
WAVE, using the ITU-declared L/R/C/LFE/Ls/Rs roles. The independently calculated
payload hash is retained. The unlabelled original is not claimed to have
automatic live-meter speaker-role support.

The reference is FFmpeg's C `ebur128` filter with dual-mono compensation disabled.
The measured path is the production timestamp-verified decoder feeding the
Swift `LiveAudioMeterDSP` at its normal source rate. It verifies complete
window coverage, exact EOF source position, `1/48000` timestamp provenance and
absence of synthetic initial silence. These M/S targets are reference-tool
calculations; ITU publishes a separate whole-programme integrated target.

The same runner reconfirms all three official −23 ±0.1 LUFS integrated targets,
the existing independent PCM LRA comparisons and the existing Annex 2 FIR
true-peak comparisons. Those whole-programme checks retain their established
tolerances and do not supply new live sample/true-peak acceptance.

Run:

```bash
ITU_LOUDNESS_DERIVED_DATA=/tmp/aagedal-itu-live-dd-20260930 \
  scripts/check-itu-programme-loudness.sh \
  /tmp/new-itu-live-check /tmp/aagedal-itu-live-references-20260930
```

Full logs, raw oracle readings, every measured/reference window, and the
`.xcresult` are retained at `/private/tmp/aagedal-itu-live-reference-check-20260930`.
The source test/runner hashes and full-artifact hashes accompany the durable
summary files here. This is a working-tree implementation check based on
`5399ec5`, with source identity recorded separately; it is not a clean-commit
candidate verification.

This closes a numerical decoder/DSP evidence gap for these authentic inputs.
The owning playback/session/display path, native audio output, transport
changes, broader delivery families, compressed authentic sources, long-play,
release-floor hardware and spoken accessibility remain separate acceptance.
