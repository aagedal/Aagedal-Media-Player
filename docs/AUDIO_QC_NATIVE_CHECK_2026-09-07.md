# Native concurrent loudness check — 2026-09-07

The local M5 Pro on macOS 27.0 ran the Release app based on `1d0f7ce` and this
continuation. The test fixture contains two independent copies of the one-hour
5.1 ALAC stream from `AUDIO_LOUDNESS_PERFORMANCE.md`. It was created by stream
copy, without changing its samples:

```bash
'Aagedal Media Player/Binaries/ffmpeg' -hide_banner -loglevel error \
  -i /tmp/aagedal-loudness-fixtures-20260907/1h-5.1.m4a \
  -map 0:a -map 0:a -c copy -n /tmp/aagedal-native-two-streams-20260907.m4a
```

## Findings and corrections

Native pointer/accessibility-tree checks started both stream jobs and observed
two independent analyzing states. Cancelling stream 1 returned it to Measure;
stream 2 continued and completed at −13.4 LUFS, 0.0 LU, and −18.1 dBTP. The
surviving result retained separate accessible metric labels and units.

The original Cancel button shared a row with progress text. The native tree
flattened that combination into a single row, and clicking the row's center
missed the small button. Cancellation now has its own full-width action row,
with the stream-specific accessible label retained. The final built app
confirmed that clicking that accessible row cancels immediately; a subsequent
Measure starts a fresh job.

A second reproduction hid the inspector during a running measurement and
reopened it immediately. The job was still analyzing: native inspector
collapse retained its SwiftUI content, so `onDisappear` was insufficient.
The fix observes `isPresented` as well, cancels tasks and feedback, and
invalidates their generations when hidden. Starting new work while hidden
is rejected. Completed measurements remain available when reopening.

After rebuilding, starting a fresh job, hiding the inspector, and reopening
returned both streams to Measure with no stale analyzing indicator. This
verifies the native hide/reopen path that the previous pure generation tests
did not exercise. The final build also passed hiding/reopening with Command-I
after retrying an explicitly cancelled job. The app remained paused throughout
these checks.

Final verification passed all 409 Release tests, Xcode static analysis, and all
61 release-preflight checks. The five loudness-profile validator tests and the
12 isolated metadata-profile workloads also pass.

## Limits

This is a focused native interaction check, not a timing benchmark. It does
not establish spoken VoiceOver narration, Full Keyboard Access traversal,
concurrent UHD/HDR playback responsiveness, or process-level memory bounds.
The computer-use API offers no pointer-only move, so actual timeline hover
acceptance remains pending. Broader audio acceptance stays in `AUDIO_LOUDNESS.md`.
