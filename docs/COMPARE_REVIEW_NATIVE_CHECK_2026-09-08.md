# Native review labels, range editing and relinking — 2026-09-08

The final Release app was exercised with disposable copies of the generated
24 fps A/B MOV fixtures in `/tmp/aagedal-review-native-rf64-20260908`.
The original media and all pre-existing review data were untouched. Native
accessibility actions and keyboard events were kept separate from test runs.

## Observed results

- Return created `Range and source identity acceptance` at source-A frame 0;
  the note survived quitting/rebuilding/reopening the same pair.
- Expanded review controls expose separate source-frame labels for severity,
  category, status, inclusive end, Apply, current-frame end, seek and clear.
  An intermediate build put the disclosure label on every child. The final
  implementation labels only the disclosure text, and the rebuilt native tree
  confirms the child labels remain distinct.
- Tab navigated from the new-note draft to the filter, the stored note text,
  and the inclusive end field. Typing `24` and pressing Return saved a 0–24
  inclusive range and showed its range marker. The JSON sidecar independently
  confirms `primaryEndFrame: 24`, with both recorded rates still `24/1`.
- Direct accessibility clicks did not reliably focus the end field; an earlier
  attempt typed `24` into the draft and created a second disposable point note.
  That note was retained and included in the subsequent relink check. This
  is not evidence that direct-click range editing or every keyboard control
  works. The expanded content is in a small scroll area; its exposed scroll-to-
  bottom action revealed offscreen controls. Compact layout/focus visibility
  and complete pointer/Full Keyboard Access acceptance remain open.
- A copied pair in the `relocated` subdirectory opened with an empty review.
  **Relink Notes…** selected the original sidecar and presented the two findings
  plus original sidecar, previous A/B, current A/B, and new sidecar paths.
  Each path has its role label and complete path in the accessibility tree.
- Return activated **Confirm A/B Mapping and Relink**. The destination showed
  two notes. Comparing the sidecars proved both complete note records were
  unchanged, including IDs, text, classifications, timestamps, exact frame
  rates and the inclusive range. Source identities point to the copied pair.
  SHA-256 verified that the original sidecar remained byte-for-byte unchanged.

## Limits

This validates native saved-note restoration, contextual labels, keyboard range
submission, and the successful explicit-relink path. Review opening and relink
activation used accessibility actions; it is not an all-keyboard workflow.
Full Keyboard Access and spoken VoiceOver were not enabled or claimed.
Existing-destination conflicts, relink cancellation, broad pointer interaction,
and narrow-window/focus-ring acceptance still require native checks. Export
and NLE round-trip acceptance are tracked separately.

## Integrated verification

All 444 Release tests pass without failures or skips, including the three
original ITU programme references enabled during the full run. The suite took
116.353 seconds (117.407 seconds including suite overhead). Xcode static
analysis and all 61 release-preflight checks pass.

Artifacts: `/tmp/aagedal-rf64-itu-full-20260908.xcresult`,
`/tmp/aagedal-rf64-itu-analyze-20260908.log`, and
`/tmp/aagedal-itu-programme-check-20260908`. Temporary artifacts may be removed;
this record, reference hashes and reproduction scripts remain in the repository.
