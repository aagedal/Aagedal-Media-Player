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
The raw production artifact labels those measurements as unreferenced
observations. A separate independent PCM calculation now checks programme LRA,
and a second independent calculation checks programme true peak, as described
below. These calculated comparisons preserve the original observation labels.

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

## Independently calculated programme LRA

`scripts/itu-programme-lra-reference.py` reads the same three hash-pinned
original WAVs using Python's standard library, without FFmpeg, the app's DSP,
or a third-party loudness library. It derives comparison values from
[EBU Tech 3342 (2023), sections 3.1 and 5](https://tech.ebu.ch/docs/tech/tech3342.pdf),
using the published 48 kHz K-weighting coefficients and energy weights in
[ITU-R BS.1770-3, Annex 1, Tables 1–3](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-3-201208-S!!PDF-E.pdf).
Each input starts with fresh filter state. Three-second windows advance by
100 ms; 1.5 seconds of trailing silence flush the file-based analysis, and
only complete windows are retained. The calculator applies the absolute
−70 LUFS gate, the −20 LU relative gate based on average energy, and the
10th/95th percentile selection with the reference algorithm's rounding rule.
The original six-channel order comes from BS.2217-2: L/R/C/LFE/Ls/Rs.
Its LFE is excluded and surround channels receive 1.41 energy weights.

The runner requires agreement within **±1 LU**, a project regression tolerance
chosen to match Tech 3342's minimum-requirement test tolerance. These derived
values are **not published ITU programme LRA targets**, and this comparison does
not establish certification. Production analyzes the original file without
the calculator's explicit trailing silence; window alignment and percentile
implementations can also differ within this tolerance. The calculator supports
only the pinned 48 kHz PCM16 mono, stereo, and specified six-channel references.

Each runner invocation first checks the independent calculator against all four
directly synthesized Tech 3342 tone sequences (10, 5, 20, and 15 LU), absolute
stereo calibration, channel/polarity isolation, LFE exclusion, gating and
percentile edge cases. Invalid formats, truncated PCM, changed source hashes,
missing/duplicate production records and non-finite measurements are rejected.
The runner retains `lra-calculator-tests.log`, a copy and SHA-256 of the
calculator, and `independent-lra-comparison.json` with both calculated and app
values, their differences, window/gate counts and explicit target provenance.
The raw `measurements.json` retains its original observation labels.

The fresh Release runner on 2026-09-08 passes all three official integrated
targets and all three independent LRA comparisons. All nine calculator tests
also pass.

| Original programme | Independent LRA (LU) | App LRA (LU) | App minus reference (LU) |
| --- | ---: | ---: | ---: |
| Mono Voice+Music −23 | 15.8698 | 15.9 | +0.0302 |
| Stereo VinL+R −23 | 14.5295 | 14.6 | +0.0705 |
| 6ch VinCntr −23 | 10.9416 | 10.8 | −0.1416 |

The fresh run is retained in `/tmp/aagedal-programme-lra-fresh-20260908`,
including `independent-lra-comparison.json`, the complete production result
bundle and all nine calculator checks. The earlier comparison against retained
results remains at `/tmp/aagedal-programme-lra-independent-final-20260908.json`.
To recheck an existing production result without rebuilding or launching the app:

```bash
python3 scripts/test-itu-programme-lra-reference.py
python3 scripts/itu-programme-lra-reference.py /path/to/references \
  /path/to/measurements.json /tmp/new-independent-lra-comparison.json
```

## Independently calculated programme true peak

`scripts/itu-programme-true-peak-reference.py` processes the same three original
48 kHz PCM16 WAVs using only Python's standard library and the four-phase,
12-tap-per-phase FIR coefficients published in
[ITU-R BS.1770-5 Annex 2, printed pages 18–19](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf).
The 4× interpolation calculates each channel independently, including LFE,
and takes the maximum absolute reconstructed value. Fresh zero filter state
and 11 trailing zero frames retain the complete FIR response at file boundaries.
Every published coefficient is an exact multiple of 1/8192, so Python integer
dot products represent the filter exactly before conversion to dBTP.

Memory stays bounded to 4,096-frame chunks plus 11 preceding samples per
channel. A triangle-inequality bound skips a block only when none of its FIR
outputs can exceed the channel's established maximum. Tests compare this
optimization against full convolution across several chunk sizes. The report
retains per-channel sample/reconstructed peaks and evaluated/skipped block
counts, together with original hashes and calculator/coefficient provenance.

The **±0.4 dB project regression tolerance** was selected before these programme
results were calculated: it uses the larger absolute error allowance of the
[Tech 3341 Table 1 tone cases 15–19](https://tech.ebu.ch/docs/tech/tech3341.pdf)
as a symmetric comparison budget. This is **not an official programme tolerance
or a published programme true-peak target**. Two compliant meters can differ
because of interpolation filters and grid under-read; this finite FIR is an
independent estimate, not an exact continuous-waveform maximum.

The runner first requires all 11 standalone calculator tests to pass. These
cover all five analytic tone cases with both polarities, intersample peaks above
full scale, channel isolation, LFE inclusion, final-sample flushing, chunk
boundaries, safe block skipping, explicit silence, malformed PCM, complete
source identity, invalid measurements, rejected comparisons, and preserved
existing output files. The runner retains `true-peak-calculator-tests.log`,
the calculator and its tests, and `independent-true-peak-comparison.json`.

The independent comparison on 2026-09-09 passes against the retained Release
production measurements from 2026-09-08:

| Original programme | Independent true peak (dBTP) | App true peak (dBTP) | App minus reference (dB) |
| --- | ---: | ---: | ---: |
| Mono Voice+Music −23 | −4.7755 | −4.8 | −0.0245 |
| Stereo VinL+R −23 | −7.9265 | −7.9 | +0.0265 |
| 6ch VinCntr −23 | −6.8393 | −7.0 | −0.1607 |

The largest reconstructed-versus-sample peak difference at these programmes'
overall peaks is only 0.1982 dB. These programme comparisons alone therefore
cannot reject a sample-peak-only implementation at the chosen tolerance;
the existing phase-sensitive synthetic references supply that separate check.

The complete standalone result is retained at
`/tmp/aagedal-programme-true-peak-independent-20260909.json`. To reproduce
against an existing production result without rebuilding or launching the app:

```bash
python3 scripts/test-itu-programme-true-peak-reference.py
python3 scripts/itu-programme-true-peak-reference.py /path/to/references \
  /path/to/measurements.json /tmp/new-independent-true-peak-comparison.json
```

The normal opt-in programme runner now runs both independent calculations after
its fresh production measurements. It fails if either comparison exceeds its
regression tolerance. These three authentic programme comparisons add true-peak
implementation evidence; independently published programme true-peak targets,
other sample rates, and broader programme genres remain separate coverage.

## Fresh integrated run — 2026-09-09

The updated programme runner completed end to end against the current Release
build, retaining its own `.xcresult` and all three production measurement
attachments at `/tmp/aagedal-programme-complete-20260909`. All three official
integrated targets pass, all nine LRA and eleven true-peak calculator checks
pass, and both independent programme comparisons reproduce the values above.
This confirms the runner with fresh production evidence rather than only
comparing earlier artifacts. Separately, the complete app suite passes all
479 Release tests with both original ITU sets enabled, zero failures and zero
skips. Static analysis and all 61 release-preflight checks pass.

## Measured result — 2026-09-08

All three references passed at **−23.0 LUFS** through the rebuilt Release app
on the development M5 Pro. The isolated run took 1.455 seconds and retained all
three measurement attachments. The six-channel file has no explicit speaker mask
in the app metadata; the bounded reader reports its layout as unspecified and
the analyzer uses its normal decoder layout handling. No 7.1 correction applies.

Artifacts: `/tmp/aagedal-itu-programme-check-20260908`, including
`measurements.json`, original hashes and `ITUProgrammeLoudness.xcresult`.
Temporary storage is not a durable archive; source URLs, test hashes and the
runner retain the reproducible record. Integrated loudness is assessed against
published programme targets; the separate LRA calculation above adds independent
implementation evidence.

## Remaining programme coverage

The [EBU v5 test set](https://tech.ebu.ch/publications/ebu_loudness_test_set)
adds narrow/wide stereo programme references: integrated −23 ±0.1 LUFS in
[Tech 3341 Table 1, cases 7–8](https://tech.ebu.ch/docs/tech/tech3341.pdf), and
LRA 5 ±1 / 15 ±1 LU in [Tech 3342 Table 1, cases 5–6](https://tech.ebu.ch/docs/tech/tech3342.pdf).
The official EBU ZIP returned HTTP 403 in this environment on 2026-09-08;
both the download linked by the publication page and its legacy
`/docs/testmaterial/ebu-loudness-test-setv05.zip` address were retried with the
same result. A fresh request to the publication page's current ZIP URL also
returned HTTP 403 during the independent-calculator continuation. Those EBU
programme LRA cases remain unmeasured; the derived ITU comparison above does
not close that gap in published programme-target coverage. Respect the EBU material's internal
R&D terms and do not add its audio to the repository. The official v5 ZIP was
retried on 2026-09-09 and still returned HTTP 403; the response headers are
retained at `/tmp/aagedal-ebu-v05-download-20260909.headers`.
The independent programme true-peak comparison above now adds coverage on the
retained ITU originals. Published programme true-peak targets, immersive layouts,
live-meter behavior, and release-floor hardware profiling remain separate work.

### Published-target acceptance handoff — 2026-09-10

A fresh primary-source check confirms that the two outstanding programme
checks have different prerequisites:

| Check | Published target available? | What is needed to close it |
| --- | --- | --- |
| EBU narrow/wide programme LRA | Yes: Tech 3342 Table 1, cases 5–6, **5 ±1 LU** and **15 ±1 LU** | Obtain the original EBU programme files, pin their identity, and measure both through the production service. |
| Independently published programme true peak | Not in the programme rows of the reviewed EBU/ITU documents | Identify an authoritative programme file **and its published true-peak value/tolerance**, then add a separate production comparison. |

The [EBU publication page](https://tech.ebu.ch/publications/ebu_loudness_test_set)
still identifies v5.0. A request to its previously documented
`/files/live/sites/tech/files/shared/testmaterial/ebu-loudness-test-setv05.zip`
address again returned HTTP 403 on September 10. Response headers are retained
temporarily at `/tmp/aagedal-ebu-recheck-20260910.headers`. The download has not
been validated or extracted. Repeating this request alone cannot advance the
acceptance check; a successful authorized download is the next prerequisite.

When the EBU originals become available, retain them outside the repository
and inspect the included readme before selecting the two programme files.
Record the archive source, original filenames, SHA-256, sample format and
duration. Add an opt-in test following `ITUProgrammeLoudnessTests` and a runner
that rejects missing or duplicate programme records. Analyze each entire file
from the beginning with fresh meter state. Assert both the LRA targets above
and the **−23 ±0.1 LUFS** integrated targets in
[Tech 3341 Table 1, cases 7–8](https://tech.ebu.ch/docs/tech/tech3341.pdf).
Keep true peak labelled as an observation unless the archive supplies a
separately attributable target. Retain a fresh Release `.xcresult` and both
programme measurements before changing the plan's acceptance status.

Obtaining the EBU archive does **not by itself** establish a published
programme true-peak target: Tech 3341 assigns true-peak targets to synthetic
signals 15–23, while its authentic-programme rows specify integrated loudness.
[BS.2217-2](https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BS.2217-2-2016-PDF-E.pdf)
likewise supplies integrated targets for the retained ITU programmes.
The independent FIR comparison above remains valid regression evidence,
with explicitly derived targets. Neither a general delivery peak ceiling nor
the app's own measured peak should be substituted for a published reference
value. This review did not identify a qualifying published programme true-peak
target; it does not assert that no such dataset exists elsewhere.

## Official eight-channel gain reference

A separate optional check uses ITU's original
[1770Conf-23LKFS-8channel archive](https://www.itu.int/dms_pub/itu-r/oth/11/02/R11020000010042ZIPM.zip).
[BS.2217-2, printed page 5](https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BS.2217-2-2016-PDF-E.pdf)
specifies its eight-channel gain-check target as −23 LKFS; the report's
page 1 specifies ±0.1 LKFS tolerance. This is a tone-based gain reference,
so it adds independent conventional 7.1 weighting evidence without closing the
authentic programme LRA or true-peak gaps above.

The downloaded original contains 48 kHz, 16-bit PCM with **no speaker mask**.
The ITU report specifies its channel order as L/R/C/LFE/Lss/Rss/Lrs/Rrs;
conventional WAVE 7.1 stores the rear pair before the side pair. The test pins
the complete original by SHA-256, reorders its PCM words to
`[0,1,2,3,6,7,4,5]`, and writes a temporary WAVEFORMATEXTENSIBLE container with
speaker mask `0x63f`. It performs no gain change, decoding, or resampling.
An independently calculated SHA-256 pins the prepared PCM payload as well.
Only the temporary, explicitly labelled 7.1 reference goes through production
`MetadataService` and `FFmpegService.analyzeLUFS`. The test requires the
conventional 7.1 weighting correction to be recorded in the result.

This preparation is necessary: neither the original's channel count nor a
decoder's guessed 7.1 order supplies its missing speaker metadata. This check
does not establish direct support for the unlabelled original, nor immersive
layouts. LRA and true peak are recorded only as unreferenced observations.

Extract the official archive into an external directory and run with native
player automation idle:

```bash
ITU_7_1_DERIVED_DATA=/tmp/aagedal-itu-7-1-build \
  scripts/check-itu-seven-point-one-loudness.sh /tmp/new-itu-7-1-results /path/to/references
```

The runner builds Release with pinned package versions, injects the opt-in
directory into a temporary XCTest manifest, and retains environment details,
input hash, build/test logs, `.xcresult`, and `measurements.json`. It rejects
missing/duplicate measurements, wrong source or prepared hashes, absent
correction provenance, and results outside the official integrated tolerance.
The downloaded audio is never added to the repository.

The prepared official reference passed at **−23.0 LUFS** through the rebuilt
Release app on the development M5 Pro on 2026-09-08, with conventional 7.1
correction provenance present. Artifacts are retained in
`/tmp/aagedal-itu-7-1-check-final-20260908`, including `measurements.json` and
`ITUSevenPointOneLoudness.xcresult`. The original archive and extracted WAV
remain outside the repository at `/tmp/itu-8channel-23-20260908.zip` and
`/tmp/aagedal-itu-eight-channel-references-20260908`. These temporary locations
are not durable archives; the source link, pinned hashes, and runner provide
the reproducible record.
