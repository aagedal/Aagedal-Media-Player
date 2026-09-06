# Native audio QC check — 2026-09-06

Focused native accessibility actions exercised the Release app built from
`9164b66` plus the Phase 42 changes, on the existing M5 Pro/macOS 27.0 test
machine. Only the generated `Test Fixtures/Generated/multichannel-5.1.m4a`
fixture was opened for this check. No production media was used.

## Observed results

- Track discovery exposed `#0 • ALAC • 5.1 • 48 kHz. All channels enabled`.
- Selecting Solo → Center changed the accessible audio-menu value to
  `Enabled channels: Center`.
- Selecting Mute → Center while Center was soloed changed it to
  `All channels disabled`.
- All Channels restored `All channels enabled`.
- The inspector exposed `Loudness analysis scope for audio stream 1` and
  `Measure loudness for audio stream 1`.
- Activating measurement displayed combined accessible rows for
  `Integrated Loudness, 4.0 LUFS`, `Loudness Range, 0.0 LU`, and
  `True Peak, 0.0 dBTP`. These are fixture observations, not calibrated
  reference measurements.
- Selecting In–Out Range cleared the whole-file results and exposed
  `Set valid In and Out points within the file to measure a range.`
- Whole File and All Channels were restored before closing the app.

## Limits

Actions used native accessibility clicks, not a complete keyboard traversal.
The automation tree did not report individual menu checkmark values, so native
checked-state narration is not certified. No audible output, VoiceOver speech,
Full Keyboard Access, concurrent-job cancellation, or delayed-stream error
presentation was verified in this session. The latter service behavior is
covered by the generated empty-selection regression tests.

The final integrated Release suite passed all 404 tests without failures or
skips. Xcode static analysis and all 61 release-preflight checks passed.
