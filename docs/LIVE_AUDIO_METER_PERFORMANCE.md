# Representative live-audio-meter acceptance

The opt-in production harness runs the live meter against explicit external
media instead of generated fixtures:

```bash
scripts/profile-live-audio-meter.sh /tmp/new-live-meter-profile \
  /path/to/representative-deliverable.mov \
  /path/to/representative-multichannel.mxf
```

For deliberate selected-track coverage, prefix a file with
`--audio-stream-order N`, where `N` is FFmpeg's zero-based audio-only stream
ordinal (`0:a:N`), not the toolbar row or the container-wide stream index:

```bash
scripts/profile-live-audio-meter.sh /tmp/new-live-meter-track-profile \
  --audio-stream-order 0 /path/to/representative-multitrack.mov \
  --audio-stream-order 1 /path/to/representative-multitrack.mov
```

The selector applies only to the immediately following file; omitted selectors
request audio ordinal zero. The same file may appear for different audio
ordinals, but duplicate file/ordinal requests fail. The production player
selects the requested track before opening the meter in both the observation
and near-EOF segments. An unavailable ordinal or unsupported selected format
fails the run. These controls enable the multi-track acceptance case; passing
representative artifacts still need to be collected and reviewed.

The [selected-track engineering check](LIVE_AUDIO_METER_SELECTED_TRACK_ENGINEERING_CHECK_2026-09-30.md)
records a generated two-track plumbing pass and retained mono native-output
failures. Those generated Debug observations do not close representative or
release-performance acceptance.

The artifact directory must not exist. Each input must have at least 20 seconds
of audio, and at least ten seconds more than the selected observation interval,
in a format currently supported by the live meter: one through eight channels
at 44.1, 48, or 96 kHz. This preserves transport headroom for the pause, routing
and resume checks before the separate near-EOF segment. Use producer-authentic,
permission-cleared files whose codec, channel order, level and expected duration
are independently known. Inputs are never copied into the repository.

`LIVE_AUDIO_METER_PROFILE_SECONDS` selects the paced observation interval from
5 through 30 seconds; the default is five seconds. Use
`LIVE_AUDIO_METER_PROFILE_DERIVED_DATA` to select a compatible Xcode build
cache. Keep other tests and native app automation idle while profiling because
the isolated XCTest host assumes its direct child process is the meter's bundled
FFmpeg instance.

The runner uses Release by default. `LIVE_AUDIO_METER_PROFILE_CONFIGURATION=Debug`
can reuse a Debug cache for engineering harness checks; the configuration is
retained in `environment.txt`. Collect release performance acceptance with the
default Release configuration.

## Production path and retained evidence

For each file, the test reads uncached-or-cached production metadata through
`MetadataService`, constructs the same `MediaItem` used by the app, and lets
`PlayerController` choose and start its production playback backend. A
window-equivalent `LiveAudioMeterSession` resolves the selected track and runs
the bundled FFmpeg timestamp stream and `LiveAudioMeterDSP` through the normal
coordinator. It does not replace those components with test doubles.

The first segment starts at source zero and records:

- selected codec, declared layout, channel count, sample rate, metadata-library
  stream ordinal, requested and resolved FFmpeg audio ordinals, explicit
  selection flag, available track count, track label and playback backend;
- source-frame advance, first-snapshot latency, maximum observed snapshot
  interval, publication count, absolute clock drift and decoded-ahead high-water;
- initial/peak XCTest-host RSS and sampled direct-child RSS;
- an A/B-independent monitor-routing check that pauses playback, retains the
  reduced reading, changes output volume, mute, playback suppression and channel
  mute, and requires the meter generation, selected source and paused reading to
  remain unchanged before successfully resuming; and
- cancellation latency from closing the meter session until the FFmpeg child
  has no remaining resident process.

The second segment starts within six seconds of the container end and requires
an authoritative final DSP snapshot. It retains FFmpeg version, frame-CRC
timestamp source and time base, timestamp frame count, exact decoded source
interval, any timestamp-authorized codec-priming silence, disabled decoder
DRC/normalization flags, snapshot count, wall time, clock/ahead high-water and
app/child RSS.

The runner retains the exact git commit and working-tree state, macOS and
hardware description, Xcode version, initial and final power state, input paths
and SHA-256 hashes, build/test logs, `.xcresult`, exported attachments,
sleep/wake events and validated `summary.json`. It fails if macOS reports sleep
during the measured interval. The source JSON attachment carries basenames and
hashes; `inputs.json` retains the explicit absolute input mapping.

The JSON validator recomputes every external input SHA-256 and fails closed on
missing or replaced inputs, duplicate file/track requests, manifest/hash
mismatches, unsupported or malformed source metadata, unknown backends,
non-finite timing, absent snapshots or child-memory sampling, decoded work beyond
the 250 ms admission bound, routing retargeting, incomplete cancellation, and
missing/inconsistent EOF timestamp provenance. The timestamp time base must be
exactly `1/sampleRate` for the selected stream, as emitted by the production
decoder. The requested observation must remain within the runner's 5–30 second
range, and reported first-snapshot latency and snapshot intervals must fit within
the recorded observation wall time. These are evidence-consistency checks;
they do not establish a UI cadence or first-reading performance target.
Run its fast regression tests
directly with:

```bash
python3 scripts/test-live-audio-meter-profile-validation.py
```

Schema 2 also requires the retained input request and both segment identities
to agree on the selected audio stream. A repeated file with a different selected
track is a distinct coverage row; repeating the same file/track is rejected.
The JSON evidence carries the selection intent so an implicit default-track
run cannot be relabelled as deliberate multi-track coverage.

The test is deliberately skipped with a named reason during ordinary XCTest and
canonical candidate verification unless the runner supplies its environment.
Its identifier is in the release evidence validator's explicit opt-in allowlist;
an unexpected skip remains a candidate failure.

## Acceptance matrix and limits

One passing file is a production-path observation, not representative-media
acceptance. Before closing the live-meter release gate, retain passing artifacts
for the actual delivery families being claimed, including at minimum compressed
stereo, uncompressed multichannel, a supported six- or eight-channel layout,
multiple tracks with deliberate selected-track coverage, and malformed or
unsupported media with actionable app behavior. Compare readings with trusted
reference tools and record expected programme/transient values separately; this
harness validates provenance, lifecycle and bounded operation, not independent
meter calibration.

Run the final matrix on the base 2020 M1 MacBook Air with 8 GB RAM, include a
long-play observation appropriate to the release decision, and perform the
documented native keyboard/VoiceOver checks. The harness samples RSS every
20 ms, so brief peaks can be missed; parent and child maxima need not be
simultaneous. It does not measure GPU use, thermals, energy, speaker correctness,
audible output, UI drawing cadence, or every malformed-media failure. Passing
artifacts therefore **enable but do not by themselves complete** representative-
media, accuracy, accessibility, soak, or base-M1 release acceptance.
