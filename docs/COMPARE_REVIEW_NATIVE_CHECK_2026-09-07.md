# Focused native review check — 2026-09-07

The local Release app built from `308769a` was exercised on the M5 Pro with
macOS 27.0 through native accessibility actions and keyboard events. Copies of
the generated 24 fps reference and delivery fixtures were placed in
`/tmp/aagedal-review-native-20260907`; no original review data was edited.
Both sources used normal MPV playback. This is partial workflow evidence,
not completion of the keyboard or VoiceOver release gate.

## Observed results

- Opening Comparison Review focused **Note at current frame**. Typing
  `Check title edge and audio sync` and pressing Return created one note at
  source-A frame 0 and cleared the draft while retaining focus.
- Tab reached **Filter review notes**. Typing `missing` showed **0 of 1 notes**
  and **No Matching Notes** without removing the stored finding.
- Export remained available with that filter active. After opening its menu,
  Down/Return selected CSV; Return in the native save panel saved the report.
  The popover displayed its saved filename.
- Reading the exported CSV confirmed the hidden finding, A/B frame 0,
  source timecodes `01:00:00:00` and `01:00:01:00`, exact rates `24/1`, and
  both full source URLs. The file uses actual CRLF record separators.
- Clearing the filter restored the finding. Its classification disclosure
  exposed severity, category, status, and inclusive-range controls through
  accessibility. Range editing was not reliably completed through the
  automation interface and is not recorded as a pass.

The initial accessibility tree called the icon controls **Add** and **Trash**.
The continuation adds explicit **Add review note**, **Review note at source A
frame …**, and **Delete review note at source A frame …** labels so repeated
rows carry a source-frame context.

After the integrated build, reopening the same pair restored its saved note.
The rebuilt native accessibility tree verified all three new labels, including
**Review note at source A frame 0** and **Delete review note at source A frame 0**.
All 415 Release tests passed without failures or skips; static analysis and all
61 release-preflight checks also passed. Test artifacts are retained at
`/tmp/aagedal-continuation-20260907-2305.xcresult` (temporary storage).

## Remaining acceptance

Full Keyboard Access was not enabled or changed; Tab between text fields is
not evidence that every control is keyboard reachable. Opening the review and
export menu used accessibility clicks. Spoken VoiceOver narration, full keyboard
creation/classification/range editing/export, native relinking and conflict
handling, and complete narrow-window review layouts remain unverified.

The current computer-use interface offers no pointer-only movement, so native
timeline hover/no-seek acceptance also remains open. Real NLE import/re-export
and release-floor performance require their separate validation matrices.

## September 8 follow-up

`COMPARE_REVIEW_NATIVE_CHECK_2026-09-08.md` records distinct expanded field
labels, keyboard inclusive-range submission and successful native relinking
with byte-for-byte preservation of the original sidecar and complete findings.
Full keyboard/VoiceOver, compact layouts, relink cancellation and conflict
acceptance remain separate.
