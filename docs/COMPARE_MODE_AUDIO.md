# Compare Mode audio inspection

Compare Mode starts with source A audible. Use the audio source control to
monitor A or B, then choose All Channels or an individual matched channel.
Monitoring does not change either encoded file or the persisted mute setting.

The audio-layout details button beside the channel menu shows the currently
selected track's channel count, reported layout, and numbered channel labels
for each source. A warning indicates differing layouts or channel counts.
Changing the selected audio track updates these details.

Recognized layouts pair channels by speaker role, so a Center channel can be
compared even when its position differs between the two tracks. Roles that
exist on only one source are listed as unmatched; use All Channels to hear the
complete selected track. For example, 5.1 back-surround and 5.1 side-surround
layouts share Left, Right, Center, and LFE but have different surround roles.

If a layout is unspecified or unrecognized and the channel counts agree,
channel choices explicitly say “by position.” This compares channel indices;
it does not establish that they carry the same speaker role or content.
Unknown layouts with differing channel counts cannot provide reliable pairs.

These controls describe routing and metadata. They do not measure loudness,
peak level, or compliance. Peak/true-peak and calibrated loudness meters remain
separate roadmap work.

Before release, verify track switching, channel isolation, All Channels,
keyboard traversal, and VoiceOver with representative multitrack and
multichannel files on both playback backends.
