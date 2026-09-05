# Manual comparison alignment

Open the alignment button beside the comparison alignment status. The offset
uses **B time = A time + offset**: +2 seconds shows B two seconds into its file
when A is at the beginning. −2 seconds holds B at its start until A reaches two
seconds. When the sources have no overlap, B stays at its nearest boundary.

Enter a signed offset in seconds or choose **A frames** to use source A's frame
rate (30 fps fallback when unavailable). Frame units are elapsed frames, not
SMPTE labels; fractional rates such as 29.97 use their rational time base.
**Apply** replaces the automatic offset. **−1 A frame** and **+1 A frame** nudge
the current offset. **Automatic** restores embedded source-timecode alignment,
or relative-start alignment if either source lacks timecode.

The offset applies while paused and during playback. The timeline's shared
interval updates immediately. It remains during a same-pair decoder reload,
but replacing B or leaving Compare Mode resets it. It is not a saved preference
or a sidecar setting. Existing review notes preserve the A/B positions recorded
when created; new notes and comparison captures use the new mapping.

## Verification

- With matching timecode, set +2 seconds and confirm B shows A's time plus two
  seconds. Set −2 seconds and check B holds at zero until A reaches two seconds.
- With missing timecode, nudge one A frame at 23.976, 25, 29.97, and 59.94 rates.
- Repeat while paused, playing, stepping, and scrubbing on MPV/MPV,
  AVFoundation/AVFoundation, and mixed pairs.
- Set a non-overlapping offset, then restore Automatic during playback. Check
  that B resumes and the overlap indication changes.
- Reload the pair or change render resolution and confirm the offset remains.
  Replace B and confirm automatic alignment returns.
- Reach activation, units, entry, Apply, nudges, and Automatic by keyboard and
  VoiceOver. Confirm the player window and controls do not move.
