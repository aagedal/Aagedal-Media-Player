# Playback inspector acceptance — 2026-10-15

The Release arm64 app build and 64 hosted tests pass on macOS 27.0.1 with no
failures or skips. The [XCTest summary](tests-summary.json) records the final
run. [Candidate/source hashes](candidate-identity.json) identify the tested
app. The existing verified audio/scope dependency overlay was reused; no
MPVKit compilation, shipping repin or provider-gate change was made.

Five new tests cover bounded finite input, native text-editor focus, independent
per-player values, same-file reconstruction versus new-file reset, and the
actual libmpv `audio-delay` property. The native test applies an offset before
context initialization, loads generated video/audio, changes offsets live,
sends a rapid series of updates, then pauses, seeks and resumes while retaining
the requested value. Existing backend lifecycle, metadata loudness analysis,
programme analysis, source meter and scope-parser regressions also pass.

Native UI checks used two generated 12-second FFV1/PCM stereo MKV fixtures:

- Metadata and Playback tabs are visible in the right-hand inspector. Inactive
  tab content is omitted from accessibility navigation.
- Typed `125` is retained in the offset field and reflected in the slider.
  The initial check exposed the player's timecode shortcut intercepting the
  first digit; the final build checks the native text responder and fixes it.
- B starts at zero while A retains +125 ms. B accepts −75 ms, and returning to
  A still shows +125 ms. Selecting a settings source does not switch the
  monitored source or comparison alignment.
- Entering 5000 displays the bounded 2000-ms value. Reset shows zero and disables
  itself. The interface uses the system number formatting.
- A completed metadata analysis (−18.5 LUFS integrated, 0.0 LU LRA, −16.5 dBTP)
  and its loudness chart remain after switching to Playback and back.
- Both a small window with a scrolling sidebar and a zoomed window were
  inspected. Controls remain inside the sidebar.

The UI checks establish operation and result retention, not physical lip-sync
accuracy. AVFoundation/ProRes RAW audio offset remains explicitly unavailable;
this work does not add an AVFoundation retiming pipeline or alter source-QC and
export timing.

Candidate: `build/playback-inspector-candidate-20261015/Aagedal Media Player.app`.
Open the inspector (Command-I), then Playback. No environment flag is needed.
Full local evidence is under `/private/tmp/aagedal-player-audio-probe-20261015/`:
`inspector-build-final.log`, `inspector-tests-final.log`, and
`inspector-tests-final.xcresult`.
