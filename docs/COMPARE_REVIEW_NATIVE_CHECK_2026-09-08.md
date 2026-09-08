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
Relink cancellation and a destination created after preview are checked in the
continuation below. Broad pointer interaction and focus-ring acceptance remain. Export
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

## Continuation: cancellation and destination races

A further native check used fresh A/B copies under
`/tmp/aagedal-review-conflicts-20260908/cancel`. Escape cancelled both the
relink file picker and the explicit mapping confirmation. The review remained
empty and neither path created a destination sidecar.

A second preview was opened against the original two-note sidecar. Before
confirming, a disposable file was created at the exact displayed destination.
Return then produced **Could Not Relink Notes**, explaining that a review already
exists and will never be overwritten. The destination retained its exact bytes;
SHA-256 also confirmed that the original sidecar remained unchanged. Evidence
is retained in that temporary directory's `evidence.json`.

The initial player window was only 270 points wide. Its original comparison
toolbar extended beyond the visible window, preventing practical pointer access
to Review. Expanding the window made the controls usable. This finding prompted
the responsive toolbar change documented below; it is separate from the passed
relink data-safety behavior. These checks used native accessibility actions and
Escape/Return, not Full Keyboard Access or spoken VoiceOver.

The expanded Release suite passes all 453 tests with no failures or skips,
including both official ITU reference opt-ins and the eight BWF regressions.
The run took 116.765 seconds (116.966 including suite overhead), retained in
`/tmp/aagedal-bwf-toolbar-full-20260908.xcresult` and its matching log.

## Rebuilt responsive-toolbar acceptance

The verified Release build reopened fresh A/B copies in
`/tmp/aagedal-review-conflicts-20260908/conflict`. At the native 270-point width,
screenshots confirmed that Comparison controls, Review, Exit, Loupe and
Inspector were all visible. The compact popover exposed the remaining controls;
selecting Vertical Wipe and setting its slider to 75% updated native state.
Scrolling reached **Replace comparison file**, which dismissed the popover and
opened the native picker. Escape cancelled it without changing the pair.

Review opened directly from the narrow toolbar. Typing a note and pressing
Return created a frame-0 finding, independently confirmed in the saved sidecar.
Expanding to 1,728 points restored the full toolbar and retained Vertical Wipe,
75% and the saved note. Exit Compare Mode returned to single-source controls.

This closes the reproduced toolbar-clipping case. Full Keyboard Access,
spoken VoiceOver, every popover at every screen edge, all comparison modes,
and focus rings during live resize remain broader acceptance work.
Static analysis and all 61 source-tree release-preflight checks also pass.
