# Premiere export and Review range departure — 2026-10-01

Implementation commit `b8115c2` passes a fresh optimized Release build and all
90 focused XCTest checks, with no skips, failures or runtime warnings. The
independent XCTest evidence validator accepts the complete summary/details.
Source-tree release preflight passes all 61 checks with the unchanged shipping
package pins. See [proof summary](proof-summary.json) and
[source identities](source-sha256.json).

The new Premiere exporter creates legacy FCP7 `xmeml` v5 XML with source A on
V1 and sequence markers. It preserves exact timebases, source start timecode,
relative frame anchors, inclusive ranges, classifications and full A/B URLs.
Same-frame findings share a labelled marker with their original text/ranges
retained individually in its comment. Relinking to shorter media extends the
review sequence rather than claiming extra source frames. Unrepresentable
rates, unsupported raster/PAR combinations and quarter-turn rotations fail
with actionable errors. The carrier has no audio track.

Five new exporter regressions and the new production-metadata matrix pass.
Existing tests also check Premiere's rejection of incompatible stored rates,
invalid/overflow ranges and acceptance after deliberate timebase migration.
The production matrix checks eight common rates, with separate real 29.97/59.94
DF minute-boundary exports. Ten XML/CSV pairs are retained in `fixtures/`;
[media identities](media-sha256.json) refer to the generated engineering
sources, rather than producer-authentic footage.

Review now flushes pending range edits when a row or range field leaves the
hierarchy, preserving live correction ownership, unavailable editing and
rejected drafts. Three new regressions pass. Native keyboard/Full Keyboard
Access/spoken VoiceOver acceptance remains open.

These are engineering checks, not a Premiere import/re-export acceptance
claim. Native editor conform, marker intervals, whitespace and re-exported
source provenance still require separate observed evidence. The temporary
full result bundle remains at
`/private/tmp/aagedal-premiere-focused-20261001/Focused.xcresult`; the built
app and modified fixture-producing xctestrun remain beside it. This focused
run does not replace matching-HEAD canonical release verification.
