# DTS timestamp qualification — 2026-09-30

The retained DTS-HD MA rejection is intentional under the existing source-time
contract. Source-zero seeking does not cause it, and an ordinary generated DTS
stream in a millisecond Matroska container does not reproduce it. This evidence
does not establish whether the local prepared file's timestamps are malformed,
whether an earlier remux accumulated rounding, or whether DTS-HD MA needs a
different independently qualified timestamp policy. No tolerance or production
timestamp behavior changes.

## Direct replay and independent inspection

The external source is the same local preparation used by the
[extended native observation](../live-meter-gpl-metal-extended-20260930/README.md).
[identities.json](identities.json) retains its independently reread size and
SHA-256, and the bundled decoder identity. Original media remains external and
is not redistributed. Tool versions and exact arguments accompany every probe.

[The paced production replay](paced-production-framecrc-command.json) retains
the production seek, pacing, DRC/normalization options, stream selection,
source-zero filters, sample format, and tee outputs. Only a 0.2-second bound and
discarded stdout PCM are added. It reproduces the eighth-packet failure at
expected frame 3,728, actual frame 3,672.

Two five-second diagnostic replays retain the same filters and decoder but
remove pacing and use framecrc as the sole output. One uses the production
`-ss 0 -accurate_seek`; the other omits input seeking. Their entire output,
including checksums, is byte-identical (SHA-256
`1085634813a36db46fd351644fe2ea25aa6102a684a0f23b21c77233e58c9a01`).
Neither resamples, changes channels, or resets timestamps from sample counts.

| Replay | PCM packets | Initial PTS | Deviation from anchored PCM clock | First rejection |
| --- | ---: | ---: | --- | --- |
| Bundled decoder, source-zero seek | 469 | 144 frames | −88 to 0 frames | Packet 8, −56 frames |
| Bundled decoder, no input seek | 469 | 144 frames | −88 to 0 frames | Packet 8, −56 frames |
| Generated DTS core / Matroska | 19 | 0 frames | 0 frames | None |

The decoded local-source sequence begins 144, 648, 1,160, 1,656, 2,168, 2,664,
3,176, 3,672. These packets each contain 512 verified PCM frames. Individual
adjacent overlaps are only 8 or 16 frames, but their cumulative displacement
reaches 56 frames (1.167 ms) by packet eight. Across five seconds it forms a
bounded sawtooth reaching 88 frames (1.833 ms), rather than steadily growing
clock drift. A bound alone does not prove that samples may be shifted to match
playback without changing the defined source timeline.

Independent Homebrew ffprobe inspection declares the source time base as
`1/1000`, 48 kHz, six source channels and DTS-HD MA. All 469 inspected decoded
source frames contain 512 samples; adjacent millisecond timestamp steps are
10 ms (211), 11 ms (203), and 12 ms (54). Relative to the first timestamp plus
cumulative 512-frame counts, those source PTS deviate by −112 to 0 frames.
This exceeds the displacement attributable to a single independent rounding
onto a millisecond grid. It does not identify the earlier preparation process
or a producer defect. The decoder changes the exact source/output timestamp
values, but the problematic sequence already appears in independent source
inspection and is unchanged by removing input seeking.

[analysis-summary.json](analysis-summary.json) records packet counts,
deviations, first failures and output identities. Framecrc retains packet size
and Adler-32, so the observation is tied to decoded PCM rather than inferred
solely from elapsed wall time.

## Regression scope

`testTimestampedProcessorRejectsRetainedDTSCumulativeTimestampOverlap` replays
the retained timestamp sequence with independently checksummed synthetic
six-channel PCM. It verifies failure at exactly 3,728/3,672, persistent rejection
on PCM/EOF, and absence of a final qualified measurement. It protects against
an implementation that checks only each adjacent timestamp and accidentally
accepts the accumulated overlaps.

`testBundledDecoderPreservesContiguousDTSInMillisecondMatroskaContainer`
generates a redistributable 0.2-second, six-channel DTS core fixture with the
bundled encoder. It verifies 9,600 source frames, preserved six-channel output,
zero synthetic initial silence, and timestamp-authoritative final drainage.
Its independent decoder replay contains 19 contiguous packets, including the
384-frame tail. This is a codec/container regression, not DTS-HD MA or numerical
compressed-media calibration acceptance.

The two modified Swift files pass `swiftc -frontend -parse`. Hosted XCTest is
delegated to the parent task's integrated Release run; this document does not
claim that suite has run. Production comments now state explicitly that the
unchanged one-millisecond tolerance is measured against cumulative PCM, and
that a coarse container time base does not alone qualify larger deviations.

Native DTS-HD MA acceptance remains open. A future policy change needs
independent source-time provenance and regression coverage for genuine gaps,
overlaps, seeks and cumulative drift; increasing the tolerance for this one
prepared file would not provide that evidence. The broader sustained native,
hardware, supported-machine and compressed numerical release gates remain as
recorded in the existing 2.0 readiness plan.
