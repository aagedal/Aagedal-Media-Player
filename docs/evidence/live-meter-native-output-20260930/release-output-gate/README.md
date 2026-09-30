# Current Release native-output rejection — 2026-09-30

The revised native profiler was run at clean source
`7bccab4f619eb88f7a1ad08de1c6fddf9e8943d9`, after its canonical verification.
The unchanged generated stereo-video input was explicitly selected at audio
ordinals zero and one. Release MPV logging receipts are present for all four
player loads (observation and EOF for each track).

The production-path XCTest passed in 26.065 seconds and retained two schema-2
source-meter rows. Their source/hash, routing, resume, cancellation, EOF and
boundedness evidence passes the source-meter validator. Both rows are saved
here with an explicitly rejected filename, not a passing profile summary.

The native log also contains AudioConverter channel-map rejection and
`[ao/coreaudio] error: unable to set the input channel layout on the audio unit`.
The final validator therefore rejects the run and the runner exits **1**.
No `summary.json` is created. This confirms the current Release logging and
failure gate on the actual native path: a successful video clock and source
meter cannot mask output initialization errors.

The failed run is not audible-output, producer-authentic, hardware or power
acceptance. The runner's post-validation power checks are not reached on this
deliberate rejection. Full results and diagnostic attachments remain at
`/private/tmp/aagedal-native-output-release-gate-20260930`; their hashes accompany
the retained rows, full native log, manifest, environment and runner error.

```bash
LIVE_AUDIO_METER_PROFILE_CONFIGURATION=Release \
LIVE_AUDIO_METER_PROFILE_DERIVED_DATA=/tmp/aagedal-itu-live-dd-20260930 \
  scripts/profile-live-audio-meter.sh /tmp/new-release-output-gate \
  --audio-stream-order 0 /tmp/live-meter-engineering-multitrack-video-20260929.mp4 \
  --audio-stream-order 1 /tmp/live-meter-engineering-multitrack-video-20260929.mp4
```

The linked dependency defect and checked repair candidate are recorded in
[the native-output diagnosis](../../../LIVE_AUDIO_METER_NATIVE_OUTPUT_DIAGNOSIS_2026-09-30.md).
No production audio-output policy or dependency binary has been changed.
