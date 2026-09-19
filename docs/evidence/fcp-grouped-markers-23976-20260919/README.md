# Final Cut grouped-marker native verification — 2026-09-19

**All eight findings retained in seven one-frame markers** in Final Cut Pro
12.3 at 24000/1001 fps, with a known XML attribute whitespace limitation.

The production exporter now uses one-frame markers at each finding’s original
start. It preserves inclusive range endpoints in each finding’s note. Findings
at the same frame share a clearly labelled marker (`QC 004 + QC 005 (2 findings)`),
with separately labelled complete note/classification/source context for each.
The source review remains eight separate findings. No keyword ranges are added.

The regression `testFinalCutProRetainedEightFindingFixturePreservesEveryFinding`
loads the retained Phase 109 original review and invokes the production exporter.
Its optional `FCP_MARKER_FIXTURE_OUTPUT` environment variable writes a new file
without overwriting evidence. For this run, xcodebuild received
`TEST_RUNNER_FCP_MARKER_FIXTURE_OUTPUT=/private/tmp/aagedal-resolve-23976-20260919/fcp-grouped.fcpxml`.
This is a production-exporter artifact, **not** a native player UI export: the
rebuilt player showed a blank content view after loading source A. That native
UI issue is uninvestigated and is not claimed fixed by this change.
The test snapshot uses a 610-second duration and the existing generated A/B media.

`original.fcpxml` passes Final Cut’s bundled FCPXML 1.9 DTD. Finder Open imported
it unmodified into a new **Aagedal FCP Grouped Acceptance 20260919** library
beside the fixture media. File → Export XML re-exported the selected **Aagedal
Compare Review** event with General metadata, version 1.14, into
`fcp-grouped-roundtrip.fcpxmld`. `returned.fcpxml` is the unchanged Info.fcpxml.
The previous failure library and QuickEdit were not used for this import.

Both files contain seven markers at frames 0, 1, 1439, 1440, 14399, 14400,
14624, each exactly one frame long. All titles and all eight findings’ content,
including range endpoints, classifications, Unicode and A/B provenance, match
when accounting **only** for XML’s replacement of literal tab/CR/LF attribute
characters by spaces. Final Cut writes those literal characters on re-export;
therefore this is not an exact-whitespace round trip. The grouped marker retains
both QC 004 and QC 005 in full. The comparison JSON records this limitation
explicitly rather than reporting exact parsed note equality.

All four fixture hashes remain unchanged. The new library’s source-A copy
matches the original movie hash. The source manifest and eight-note review are
retained in `../fcp-markers-23976-20260919/`; its seven-finding Resolve selection
is not used here.

All 31 exporter tests pass, including the original data-loss fixture, duplicate
anchors, nested/overlapping ranges, adjacent anchors, invalid ranges and exact
fractional timing. Test evidence is at
`/private/tmp/aagedal-phase110-fixture-tests.xcresult`.

This replaces Phase 109’s conservative overlap rejection. It closes the focused
finding-loss issue; other rates/source starts, raster/default duration behavior,
native player UI export and exact whitespace round-trip acceptance remain open.
