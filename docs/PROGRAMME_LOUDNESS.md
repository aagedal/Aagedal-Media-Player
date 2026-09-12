# Programme loudness from separate mono tracks

The metadata inspector's **Programme Loudness** section measures selected mono
audio tracks together as one stereo or 5.1 programme. It appears when metadata
identifies at least two mono audio streams. The existing individual-track
measurements remain available below it.

## Common deliverables

| File contents | Programme layout and assignments |
| --- | --- |
| Eight mono tracks; tracks 1–2 are stereo and 3–8 are unused | Choose **Stereo**, assign Left to Track 1 and Right to Track 2. Tracks 3–8 are excluded. |
| Eight mono tracks containing a 5.1 programme and two unused tracks | Choose **5.1**, then assign Left, Right, Centre, LFE, Left Surround and Right Surround to their actual tracks. Leave the two spare tracks unassigned. |
| Multiple stereo programmes stored as mono pairs | Choose **Stereo** and select the two tracks belonging to the desired programme. Measure each programme separately. |

Stereo initially uses the first two known mono tracks. Choosing 5.1 initially
assigns the first six known mono tracks in L, R, C, LFE, Ls, Rs order. **Confirm
the assignments before measuring**: delivery channel orders vary. Each speaker
role has an editable track picker; a track cannot occupy two roles. Incomplete
or duplicate assignments disable measurement. Changing layouts resets the
assignments, and changing the file resets them to the stereo starting point.

No layout is inferred from silence. Eight tracks alone do not establish whether
a file contains stereo, surround, alternate languages or unrelated material.
Unassigned tracks are excluded even when they contain loud audio.

## What is measured

Choose **Whole File** or **In–Out Range**, then **Measure Programme LUFS**. Scope
is shared with the individual-track measurements. The programme result shows
integrated loudness in LUFS, loudness range in LU and maximum true peak in dBTP.

The analyzer places the assigned mono signals into separate programme channels,
then runs loudness analysis on that multichannel signal. It does not average or
add previously measured LUFS values, normalize levels, or downmix the channels.
Opposite-polarity stereo therefore does not cancel as it would in a mono sum.
5.1 LFE is excluded from integrated loudness; surrounds receive their speaker
weighting. True peak includes all assigned channels, including LFE.

This is offline source analysis. Playback volume, mute, solo and output routing
do not change it. It is not a live meter or a compliance verdict. Existing
single-stream stereo and surround files can continue to use their stream's
**Measure LUFS** action without assembling a programme.

Assigned tracks retain their positions on the file timeline. Missing leading
or trailing time and timestamp gaps are treated as silence, so a shorter track
does not truncate the programme and a delayed track does not move earlier.
Whole File spans the known file duration, including any video-only tail.
Selected ranges use file-relative seconds and an exclusive Out point. This
differs intentionally from an individual-track measurement that reports no
samples when the track has no audio in the selected interval.

## Cancellation and saved provenance

**Cancel Programme Analysis** stops the job. Closing/hiding the inspector or
changing media cancels it too. Changing assignments, layout, scope or applicable
trim points clears the old result and cancels any outstanding programme job.
Late completion from an earlier job cannot replace the current result. A
completed result can be measured again; a failed job can be retried.

**Copy Metadata as JSON** adds a separate `programmeLoudness` object containing:

- `mapping.layout`: `stereo` or `surround5Point1`.
- `mapping.audioStreamIndices`: zero-based **audio-only** stream ordinals in
  FL, FR order, or FL, FR, FC, LFE, SL, SR order. These are not absolute
  container stream numbers; the UI displays the same audio ordinals starting
  at 1.
- `loudness`: integrated loudness, loudness range, true peak and, for a selected
  interval, the exact requested `analysisRange`.

The root metadata duration establishes the whole-file interval. Individual
measurements stay under their respective `audioStreams[].lufs` objects. As in
the existing export, non-finite values such as silence's negative-infinite
true peak are represented as strings. Only the current programme mapping's
result is included; no previous programme measurements are silently retained.

## Limits and verification

This first implementation supports known mono streams assigned to Stereo or
5.1(side). It requires a known positive file duration and valid sample rates.
Mixed source sample rates are resampled to the highest selected rate; source
levels are not normalized. Mixed mono/multichannel assembly, 7.1 assembly,
automatic empty-track detection and stored per-file mapping presets are not
part of this implementation.

Processing uses one cancellable FFmpeg job, bounded diagnostic retention and a
streaming filter graph; no whole-file PCM output is created. Each assigned
channel is padded and trimmed to the finite requested interval before explicit
speaker-channel joining. Each assigned track uses a separate demux input to
avoid cross-track buffering and the reproduced loss of channels in a late
selection from an eight-hour split-mono file. The [production programme profiling harness](PROGRAMME_LOUDNESS_PERFORMANCE.md)
records whole-file and early/late range timing and parent/FFmpeg memory for
stereo and 5.1 assemblies from eight mono tracks. Representative production
content, base-M1 performance and hands-on keyboard/VoiceOver acceptance remain
separate checks.

`ProgrammeLoudnessTests` compares split-mono programmes against independent PCM
references, covering eight-track stereo with silent or loud spare tracks,
opposite polarity, 5.1 weighting/LFE placement, reordered assignments, delayed
and shorter channels, ranges, sample rates, silence, errors and cancellation.
`ProgrammeLoudnessControllerTests` covers replacement, mapping changes, retry,
stale completion and JSON separation/provenance. See
[existing loudness references](AUDIO_LOUDNESS.md) for the underlying analyzer's
calibration and remaining accuracy limits.

The September 11, 2026 final Release run passes all 552 tests with no failures
or skips, including the real metadata/controller measurement, official ITU
references and APFS recovery. Static analysis and all 61 release-preflight
checks pass. Evidence is recorded with Phase 82 of the
[follow-up improvement plan](../FOLLOW_UP_IMPROVEMENT_PLAN.md).
