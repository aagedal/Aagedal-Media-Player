# Official programme loudness references

This optional check feeds three original ITU programme WAVs through the app's
`MetadataService` and production `FFmpegService.analyzeLUFS`. It complements the
independently synthesized references in `AUDIO_LOUDNESS.md` with authentic
voice/music content. It does not establish complete standards certification.

## Sources and targets

[ITU-R BS.2217-2](https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BS.2217-2-2016-PDF-E.pdf)
publishes the programme references and a −23.0 ±0.1 LKFS integrated target.
The app displays the equivalent integrated result in LUFS. These are original
48 kHz, 16-bit PCM WAV files, measured from the beginning over the whole file.

| Reference | Channels | Official archive |
| --- | ---: | --- |
| Mono Voice+Music −23 | 1 | [Download](https://www.itu.int/dms_pub/itu-r/oth/11/02/R11020000010037ZIPM.zip) |
| Stereo VinL+R −23 | 2 | [Download](https://www.itu.int/dms_pub/itu-r/oth/11/02/R11020000010039ZIPM.zip) |
| 6ch VinCntr −23 | 6 | [Download](https://www.itu.int/dms_pub/itu-r/oth/11/02/R11020000010031ZIPM.zip) |

The [ITU download directory](https://www.itu.int/oth/R1102000001/en) provides
these archives. Reference audio is not redistributed in this repository.
Obtain it directly from ITU and retain the exact WAV filenames. The test pins
SHA-256 hashes of all three original files and requires the complete set before
a run can pass. It checks source channels and sample rate as well as loudness.

No programme-specific LRA or true-peak targets are supplied for these rows.
The result artifact labels those measurements as unreferenced observations;
they must not be presented as independent accuracy checks.

## Reproduction

Extract all three archives into one external directory, then run:

```bash
ITU_LOUDNESS_DERIVED_DATA=/tmp/aagedal-itu-build \
  scripts/check-itu-programme-loudness.sh /tmp/new-itu-results /path/to/references
```

Use a new artifact directory and keep native player automation idle. The runner
builds Release using pinned package versions and injects the reference directory
into a temporary XCTest manifest. It retains input hashes, app revision, working
changes, OS/Xcode versions, build/test logs, `.xcresult`, and measurements.
It rejects missing or duplicate result records, including a test that returns
without its opt-in environment. Ordinary regression runs do not require network
access or downloaded programme media.

## Measured result — 2026-09-08

All three references passed at **−23.0 LUFS** through the rebuilt Release app
on the development M5 Pro. The isolated run took 1.455 seconds and retained all
three measurement attachments. The six-channel file has no explicit speaker mask
in the app metadata; the bounded reader reports its layout as unspecified and
the analyzer uses its normal decoder layout handling. No 7.1 correction applies.

Artifacts: `/tmp/aagedal-itu-programme-check-20260908`, including
`measurements.json`, original hashes and `ITUProgrammeLoudness.xcresult`.
Temporary storage is not a durable archive; source URLs, test hashes and the
runner retain the reproducible record. Only integrated loudness is assessed
against independent programme targets here.

## Remaining programme coverage

The [EBU v5 test set](https://tech.ebu.ch/publications/ebu_loudness_test_set)
adds narrow/wide stereo programme references: integrated −23 ±0.1 LUFS in
[Tech 3341 Table 1, cases 7–8](https://tech.ebu.ch/docs/tech/tech3341.pdf), and
LRA 5 ±1 / 15 ±1 LU in [Tech 3342 Table 1, cases 5–6](https://tech.ebu.ch/docs/tech/tech3342.pdf).
The official EBU ZIP returned HTTP 403 in this environment on 2026-09-08;
those programme LRA cases remain unmeasured. Respect the EBU material's internal
R&D terms and do not add its audio to the repository. Programme true-peak
references, immersive layouts, live-meter behavior, and release-floor hardware
profiling remain separate work.
