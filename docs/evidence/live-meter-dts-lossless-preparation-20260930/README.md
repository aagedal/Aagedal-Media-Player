# Lossless DTS-HD MA source preparation — 2026-09-30

The retained authentic DTS-HD MA audio can be measured on a newly qualified
source clock without weakening the production timestamp contract. Compressed
stream-copy extraction followed by Matroska remux preserves every packet and
every decoded PCM sample in the selected prefix. The original local container
continues to fail the unchanged timestamp contract; this preparation does not
establish that its historical source timeline was correct.

## Qualification performed

[The executable qualification script](qualify.py) extracts the first 30 seconds
of audio ordinal zero from the same external local preparation identified in
[the earlier DTS rejection](../live-meter-dts-timestamp-qualification-20260930/README.md).
The source SHA-256 remains
`d52b99beb349bbcbecd2c44bdd02cda4fbf1b2604503c73d4d03665d31d09003`
before and after the operation. Both media products stay in `/private/tmp`;
no source audio or compressed packet bytes are committed.

The extraction copies the coded DTS-HD MA packets into an elementary stream.
The raw demuxer then supplies a clock derived from the stream's packet sample
durations, and stream-copy remux writes a new Matroska audio-only file. There is
no audio re-encoding, filtering, resampling, channel remapping, gain adjustment,
or update to the original media. The preparation starts at source frame zero;
it does not preserve the original container's initial 144-frame offset or
discontinuous timestamps. Its established PCM sequence is the original prefix,
and its established source clock is the explicitly newly prepared clock.

The script successfully verifies:

- All 2,813 packet sizes and SHA-256 payload hashes agree between the original
  selected audio prefix, extracted elementary DTS-HD MA stream, and new MKA.
  Independently inspected packet receipts are retained as compressed JSON.
- All three forms retain DTS-HD MA, 48 kHz, six channels, and `5.1(side)`.
- All six PCM decodes, covering those three forms with bundled FFmpeg 9.0.1
  and the separately installed Homebrew FFmpeg 9.0.2, produce exactly
  34,566,144 bytes of identical interleaved float PCM. The common SHA-256 is
  `38ce7dc7cff6ec1d33c7bf74804f8abaa3c25507ba4a4c6fe030fcea7081b9c5`.
- Bundled decoding of the new MKA with production source-zero timestamp,
  trim, DRC/normalization, stream selection and PCM-format arguments emits
  2,813 contiguous checksummed framecrc packets. Each packet contains 512
  frames. Initial PTS and every cumulative source-clock deviation are zero.
  Its exact endpoint is 1,440,256 frames, or 30.005333333 seconds. The container
  duration rounds to 30.006 seconds.

The two decoders are separate builds of FFmpeg, not independent algorithm
implementations or a trusted numerical loudness/true-peak reference. The
framecrc replay removes playback pacing and outputs framecrc alone; it proves
PCM/timestamp qualification, not native meter lifecycle or audible output.
No native profile or hosted XCTest result is claimed by this qualification.
All checks are assertions against the retained external source rather than
synthetic audio fixtures.

[qualification-summary.json](qualification-summary.json) records identities,
all six PCM digests, exact source frames and clock qualification. Each tool run
has exact arguments, exit status, output digest and retained stderr.

## Reproduction

Run from the repository root, before any native profile starts. Reproduction
recreates the scratch preparations and Matroska metadata can change the MKA
file hash; never rerun against a preparation currently being profiled.

```sh
/opt/homebrew/bin/python3 docs/evidence/live-meter-dts-lossless-preparation-20260930/qualify.py \
  --source /Users/truls.aagedal/Movies/TestVideo/Interstellar_2014_copy.mkv \
  --scratch /private/tmp/aagedal-dts-lossless-qualification-20260930 \
  --bundled-ffmpeg '/Users/truls.aagedal/Developer/Aagedal-Media-Player/Aagedal Media Player/Binaries/ffmpeg' \
  --independent-ffmpeg /opt/homebrew/bin/ffmpeg \
  --independent-ffprobe /opt/homebrew/bin/ffprobe
```

The qualified media is
`/private/tmp/aagedal-dts-lossless-qualification-20260930/source-copy.mka`,
audio ordinal zero. A subsequent native run can qualify six-channel authentic
DTS-HD MA codec payload, source monitoring independence, clock freshness,
cancellation and timestamp-authoritative EOF on this explicit preparation.
Original-container DTS-HD MA acceptance and general discontinuity policy remain
open, as do numerical calibration and hardware/release-floor gates.

## Completed native production observation

The qualified preparation subsequently passes the unchanged production meter
profile on the retained [feature-qualified GPL/Metal candidate](../live-meter-gpl-metal-native-20260930/README.md).
One native XCTest passes in 28.047 seconds, and the unchanged schema-2 profile
validator accepts its complete row. [native-proof-summary.json](native-proof-summary.json)
joins the qualified media, test outcome and sampled production observations.

| Measurement | Result |
| --- | ---: |
| Observation duration / published snapshots | 20 seconds / 404 |
| First reading / maximum snapshot interval | 64.64 ms / 65.36 ms |
| Maximum observation drift / decoded ahead | 197.89 ms / 248.44 ms |
| Cancellation latency / remaining child RSS | 0.306 ms / 0 bytes |
| Exact EOF source interval | 1,152,288–1,440,256 frames |
| EOF timestamp-authorized frames / synthetic silence | 287,968 / 0 |
| EOF snapshots / maximum EOF drift | 120 / 60.43 ms |
| Sampled overall app / child RSS peaks | 169.08 / 16.86 MiB |

The profile applies monitor routing, volume, mute and suppression changes while
paused, verifies that source selection, generation and reduced reading remain
invariant, then observes resumed source progress. Both observation and EOF
starts retain CoreAudio, six decoded source channels and two output channels.
Native output logging succeeds without output initialization/channel-map
errors. This is source preservation on a stereo device; audible output,
surround-device behavior and device switching are not observed.

The app metadata reports the broad `5.1` name while independent FFprobe proves
the actual `5.1(side)` stream. The current meter conservatively uses unknown
speaker roles for that broad metadata name. This run therefore qualifies the
six source channels, peak/lifecycle/EOF path and monitoring independence;
it does not qualify speaker-role loudness weighting or numerical loudness.

The candidate executable SHA-256 is
`e13dc023fa13590ab8331c7d3355ec7dc6b2f3e8ebfb1bfc1b291c6410140706`,
and its test executable is
`17ef28a51cbffec676d24ae7dcbd92d990de385fe3924426a1196c9e082f5372`.
Both, all eight new framework payloads, the original candidate xctestrun, build
receipt/builder, relink command and link map match the earlier identities
before and after the run. No app rebuild, dependency publication or repin occurs.

The tested candidate's source context is
`060f611f7ba1d669a1af7b7846cdf1812f53b531` plus its retained dirty
clock-handoff correction, as identified by the earlier complete source hashes
and diff. Current HEAD is recorded only as run context. Eighteen of twenty
current meter Swift/test files match those build hashes exactly. Decoder Swift
differs only in full-line timestamp explanation comments; comparison to the
hash-matched original Git blob verifies identical remaining code. The later
DTS decoder test additions change the other hash. DSP, coordinator, session,
transport, presentation, source selection and production performance test are
exact matches. All twenty current file hashes remain unchanged through this
native run. These receipts do not claim a clean current-source release build.

Root explicitly released the native test host before this exclusive interval;
no other Xcode/native profile ran concurrently. Unrelated source/document edits
could continue. An awake assertion covers the interval, and power receipts
report no system sleep. Memory and timing are diagnostic samples on the same
M5 Pro/macOS 27.0.1 development host used for the earlier observations, not
release-floor or comparative throughput acceptance.

The first sandboxed launch stops at process inventory before XCTest and is
retained as `first-sandbox-runner.log`. The authorized native-access retry uses
the same prepared xctestrun and passes. Exact preparation and execution scripts
are `prepare-native-profile.py` and `run-native-profile.zsh`; the runner uses the
existing retained native profile script without changing its acceptance policy.
`finish-native-profile.py` independently reruns validation, verifies all
identities and the exact EOF endpoint against qualification, and retains the
test summary, compact attachments, compressed native log, diagnostics and result
file digests. Full app/result/media artifacts stay under `/private/tmp`, which
is not a durable archive. Recreating or re-running this profile needs a new
scratch/native artifact directory to preserve the completed receipts.
