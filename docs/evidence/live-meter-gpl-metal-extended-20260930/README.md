# Extended GPL/Metal native meter observations — 2026-09-30

The independently linked [feature-qualified GPL/Metal candidate](../live-meter-gpl-metal-native-20260930/README.md)
passes a 120-second producer-original Sony FX6 mono-track observation, a
90-second producer-original GoPro AAC stereo observation, and a 30-second
six-channel AC-3 observation. A separate DTS track in the same local Matroska
file is rejected by the production timestamp verifier. Its failure is retained
alongside the passes; this is not general DTS acceptance.

| Input / audio ordinal | Observation snapshots | Maximum observation / EOF drift | Exact EOF source frames |
| --- | ---: | ---: | --- |
| Sony FX6 PCM24 / 7 | 2,395 | 230 / 180 ms | 6,424,320–6,712,320 |
| GoPro AAC / 0 | 1,796 | 216.6 / 120.94 ms | 4,979,374–5,263,360 |
| Local Matroska AC-3 / 2 | 603 | 208 / 117 ms | 5,675,664–5,954,688 |

Every passing row uses the unchanged schema-2 validator and verifies selected
track identity, source-channel preservation through monitor routing,
pause/resume progress, cancellation to zero child RSS, and timestamp-authoritative
final DSP drainage. CoreAudio initializes with two native output channels in
all seven segment starts, including the rejected DTS start. No native output
initialization/channel-map failures occur. Six source channels measured while
monitoring in stereo do not establish surround hardware or audible output.

The six-channel file is an existing local short Matroska preparation, not a
verified producer-original recording or a numerical calibration reference.
Its fourteen selectable audio tracks include DTS ordinal zero and AC-3 ordinal
two. Original media stays external; independently reread SHA-256 identities
are retained in [media-identities-after.json](media-identities-after.json).

## Retained DTS rejection

The DTS native test fails promptly with `expected frame 3728 but received 3672`
after one published snapshot. No passing summary is created. Native playback
continues with six decoded source channels and two output channels while the
meter clears its measurement to Unavailable.

[The bundled-decoder replay](dts-bundled-framecrc.txt) uses the production
source-zero filter/decoder arguments, with only a 0.2-second output bound and
discarded PCM added for inspection. Its unchanged checksummed packets contain
512 frames each, starting at PTS 144, 648, 1160, 1656, 2168, 2664, 3176 and
3672. Initial source silence accounts for 144 frames; the eighth packet should
start at 3728 on the contiguous PCM clock. The 56-frame deviation exceeds the
existing 48-frame (one millisecond at 48 kHz) limit. Independent source-frame
inspection also shows irregular millisecond timestamps. This identifies the
rejection trigger, but does not prove a producer error, missing audio samples,
or an acceptable timestamp normalization policy. The tolerance is unchanged.

## Identity and acceptance limits

[Proof summary](proof-summary.json), individual XCTest summaries, compressed
native logs, attachments, inputs, xctestrun manifests and power receipts retain
the three passes and one rejection. The app/test and all eight framework
identities match their earlier independently linked candidate before and after
these runs. That earlier source snapshot identifies the tested binaries;
the current repository HEAD is recorded as run context only. No build database
or original app was copied or modified for these observations.

The first sandboxed launcher stops at process inventory before XCTest; the
same prepared runner then executes with normal native test-host access. A
temporary awake assertion covers all four runs, and no sleep occurs. Parallel
metadata compilation can overlap these intervals, so memory/timing observations
are diagnostic rather than comparative performance acceptance.

External apps/result bundles remain at
`/private/tmp/aagedal-gpl-metal-meter-repeat-20260930`; their file hashes are
retained here. Temporary storage is not a durable artifact archive. Public
dependency publication/repin, 30-minute playback, supported-macOS/base-M1,
audible/device-switch/surround hardware and trusted compressed-media numerical
acceptance remain open. The historical intermittent FX6 failure's cause is
still unproven.
