# Playback inspector

The [arm64 acceptance record](evidence/playback-inspector-20261015/README.md)
records 64 passing tests and native UI checks. A candidate app is at
`build/playback-inspector-candidate-20261015/Aagedal Media Player.app`.

The right-hand Inspector has Metadata and Playback tabs. The toolbar inspector
button and Command-I open the same panel. Each window remembers its selected
tab while the view is mounted. Metadata stays mounted behind the Playback tab,
so switching tabs preserves completed loudness results and lets an in-progress
analysis finish. Closing the inspector still cancels its analysis workers.

Playback initially provides an audio sync offset for MPV. A positive value
plays audio later relative to video; a negative value plays it earlier. The
slider covers −2,000 to +2,000 ms in 10-ms steps, with an exact integer
millisecond field and Reset. Non-finite input is rejected and values outside
the supported range are clamped. AVFoundation/ProRes RAW playback shows the
control as unavailable. Playback must have a ready audio track to edit it.
The playback keyboard handler yields to native text editors so entering the
offset does not activate timecode entry or playback shortcuts.

In Compare Mode the Playback tab has an A/B source selector. Each controller
owns its own offset, including when that source is not currently monitored.
Changing the selector does not change audible monitoring or comparison
alignment. Offsets survive pauses, seeks, track changes and reconstruction of
the same file's playback backend. Loading a different URL resets only that
controller's offset. No offset is persisted as a global preference.

The MPV wrapper caches the requested offset before initialization and applies
it once its drawable creates the context. Live changes use libmpv's
`audio-delay` property, in seconds. This requires no MPVKit rebuild or package
repin. Source loudness calculations and exports retain the file's original
timing; this control does not compensate for the native audio probe's buffering.
