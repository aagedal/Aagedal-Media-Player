# Review availability and PDF identity — 2026-09-30

Review error callbacks and lazy-row restoration now defer keyboard focus while
editing is disabled. Re-enabling editing restores the selected finding/field;
passive text/range blur preserves drafts, errors and correction ownership.
Three regressions cover selected versus fallback focus and empty/changed/unchanged
text drafts through availability transitions.

PDF reports now retain complete A/B URLs and each finding’s stored exact frame
ordinals and rational rates. Equal filenames in different directories and
findings captured before different-rate relinking remain distinguishable.
Long URLs wrap and paginate before the findings table. Two regressions preserve
source identity and finding text across unusually long paths.

All **60 focused optimized Release checks pass**, with no skips, failures or
runtime warnings. Detailed result validation explicitly requires all five new
regressions. [Verification](verification.json), summaries/details and compressed
logs retain the source and test outcomes. Full result bundles remain at
`/private/tmp/aagedal-2-plan-next-final-focused-20260930.xcresult`.
The full script-validator gate also passes.

The first focused run passes 58 checks and rejects one long-URL assertion: it
concatenated whole-page text with repeated headers inserted into a URL. The final
check reads the body below the repeated headers and requires both complete URLs
and the finding text. The first failure is retained, rather than treated as a
passing run. A sandboxed launcher could not access normal Xcode manifest/module
caches; only the native-access runs execute tests.

[Normal provenance fixture](provenance.pdf) and [long-source fixture](long-sources.pdf)
are rendered with Poppler. All three pages are visually inspected: source text,
page transitions and finding tables show no clipping or overlap. Fixtures can be
exported again by setting `TEST_RUNNER_COMPARE_REVIEW_PDF_FIXTURE_DIRECTORY` to a
new existing directory during these two tests; existing files are never replaced.

A bounded native-app inventory returns, but earlier repeated app selection hangs
have not supplied an interactive player state. This continuation makes no new
native keyboard, Full Keyboard Access or spoken VoiceOver acceptance claim.
