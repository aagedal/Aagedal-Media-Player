# Selected-track live-meter engineering smoke — 2026-09-29

The new schema-2 profiling path was exercised with generated two-track media
through production metadata, MPV playback, the owning live-meter session,
bundled FFmpeg and DSP. These are Debug harness checks, not producer-authentic
or release-floor acceptance. The run used macOS 27.0.1, Xcode 27.0 and an M5 Pro.
It ran from the modified checkout after `158b85d`, whose status is retained in
`environment.txt`; it is not exact clean-commit candidate evidence.

The passing input was a generated 24-second video with two stereo AAC tracks,
44.1 kHz and 48 kHz. Its SHA-256 is
`dfa0cc691d2b3455226b4521c973e06397a3a8220f99ae3dbd5fe541d708950e`.
The same file was supplied twice with explicit audio ordinals 0 and 1.
Both rows passed the strict validator: requested, player and EOF identities
agree, pause/routing/resume invariants pass, cancellation leaves no child,
EOF is authoritative, and the power check reports no sleep.

| Track | Snapshot count | Maximum observed ahead | EOF timestamp frames |
| --- | ---: | ---: | ---: |
| 0, stereo 44.1 kHz | 104 | 241.667 ms | 264,600 |
| 1, stereo 48 kHz | 101 | 241.667 ms | 288,000 |

`summary.json` retains timing, memory and timestamp provenance. Raw build/test
artifacts remain at `/private/tmp/live-meter-track-video-smoke-20260929` and may
be removed by the operating system. The generated media was not added to the
repository. These observations demonstrate deliberate selected-track harness
operation, not independent numerical accuracy or audible speaker correctness.

An earlier audio-only input with mono 44.1 kHz and stereo 48 kHz tracks failed
while measuring ordinal 0. The first run lost synchronization at -294.6 ms;
a repeat timed out waiting for the paused meter state. Both logs show CoreAudio
channel-layout/converter errors, and the repeat also records audio-queue startup
failure. Their input manifests and complete test logs are retained alongside the
passing result. This is an unresolved mono/output interaction; the stereo video
pass does not establish audio-only mono acceptance or invalidate those failures.
Producer-authentic tracks, malformed media, trusted meter reference comparisons,
long-play, native accessibility and the base-M1 matrix remain open.
