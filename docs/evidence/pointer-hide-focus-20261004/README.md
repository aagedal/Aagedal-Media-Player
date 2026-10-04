# Pointer hide zone and control focus — 2026-10-04

The right-edge cursor-hide zone previously used the automatic-hide interaction
guard. Playback/toolbar focus can linger after a pointer click, vetoing explicit
hiding: the cursor and traffic lights disappear while the toolbar and playback
controls remain visible.

Explicit pointer hiding now overrides ordinary button/slider focus and control
hover. Active timecode editing and open Review/loupe/comparison popovers remain
protected. Automatic hiding still respects keyboard focus; Tab reveals controls
and cancels pending hiding without changing normal focus traversal.

Focused optimized Release build/test passes 14 overlay and command tests with
zero failures, skips or runtime warnings. The regression tests pointer hiding
with retained focus during playback and pause, keyboard restoration and leaving
the zone. Active-editing protection passes separately. All 19 release-script
checks pass. Candidate/release verification now requires both identities and
at least 839 aggregate tests (one added case, one renamed existing case).
No fresh full canonical verification is claimed for this correction.

Source hashes, XCTest summary and detailed results are retained here. The full
result bundle/log remain at `/tmp/aagedal-pointer-hide-20261004.xcresult` and
`/tmp/aagedal-pointer-hide-20261004.log`; temporary storage is not a durable
archive. The focused rebuild reused the October 3 DerivedData, so its app products
now contain this correction and are not the earlier candidate's byte identity.

Manual check: click Play/Pause, timeline/volume and toolbar controls, then enter
the hide zone. Confirm controls/cursor disappear both playing and paused; leave
and confirm restoration, then repeat and press Tab. Repeat with timecode editing
and each popover open to confirm they remain visible. This receipt does not claim
a new native pointer/VoiceOver acceptance run.
