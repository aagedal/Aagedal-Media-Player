# Resolve 23.976 relative-time acceptance — 2026-09-19

Status: native player export, editor import/re-export and source identity pass.
This closes the focused 23.976 relative-time round trip; same-frame findings
remain unsupported in Resolve EDL and other-editor acceptance remains separate.

The existing September 19 Debug player opened the generated `24000/1001` source
pair, loaded all eight findings, then opened the separate seven-finding copy
through **Notes → Open Notes Copy…**. Its native **Export → DaVinci Resolve
Markers (.edl)…** action saved the unmodified EDL retained here. The copy omits
only Fixture 5 (the known unsupported duplicate anchor); both movies and both
review files still match their original manifest hashes.

These movies have no embedded source timecode. The exported EDL uses
`NON-DROP FRAME`, relative alignment, exact `24000/1001` rate provenance and
the current A/B URLs. Parsed anchors and durations match the selected review:

| Relative frame | Relative timecode | Duration in frames |
| --- | --- | --- |
| 0 | 00:00:00:00 | 1 |
| 1 | 00:00:00:01 | 1 |
| 1439 | 00:00:59:23 | 3 |
| 1440 | 00:01:00:00 | 1 |
| 14399 | 00:09:59:23 | 3 |
| 14400 | 00:10:00:00 | 1 |
| 14624 | 00:10:09:08 | 1 |

`native-export-provenance.json` retains the export SHA-256, current checkout,
app binary identity (unchanged from Phase 107), expected anchors/durations and
post-export input hashes. Comparing the file with itself was used only for the
helper's fixture-provenance check, never as a round-trip result.

Resolve Studio **21.1.0.14** has the separate project **Aagedal 23976 Marker
Acceptance 20260919** and timeline **23976 relative current sources**, created
at 23.976 with `00:00:00:00` start before any marker import. The read-only
`pre-import-snapshot.json` reports the actual current source-A movie, 14,625
source frames, untrimmed placement from frame 0 through exclusive frame 14,625,
and zero timeline markers. Source B is exported note provenance only.

Automation can select the media-pool timeline, but its right-click menu does
not open. The user completed **Timelines → Import → Timeline Markers from EDL**
using:

`/private/tmp/aagedal-resolve-23976-20260919/source-a_vs_source-b_review.edl`

The actual post-import state was captured through Resolve's Lua console:

```lua
dofile("/Users/truls.aagedal/Developer/Aagedal-Media-Player/scripts/capture-resolve-marker-snapshot.lua")("/private/tmp/aagedal-resolve-23976-20260919/native-snapshot.json")
```

`native-import-validation.json` passes all seven actual markers against the EDL,
including exact text, colors, first/adjacent/final anchors and inclusive range
durations. Native source identity and untrimmed placement also pass, with fresh
unchanged media/review hashes. The snapshot is read-only; no marker was created
or repaired through scripting. `native-export-provenance.json` retains the
earlier export-stage status; the import report records the subsequent result.

The user completed native **Timeline Markers to EDL**, saving the unmodified
`resolve-roundtrip.edl` retained here. The comparison passes **7/7 exact records**,
with no missing or unexpected markers and unchanged post-export hashes for both
media files and both reviews. `native-roundtrip-comparison.json` combines this
result with the captured native source identity. The returned EDL SHA-256 is
`1c92a6adb673b6834a48ca142b4bc91d0b15ddbe2d754f5e7effba3af39940be`.

Recheck with the original fixture files still present (choose a new output path):

```sh
python3 scripts/validate-resolve-marker-roundtrip.py \
  /private/tmp/aagedal-resolve-23976-20260919/source-a_vs_source-b_review.edl \
  /private/tmp/aagedal-resolve-23976-20260919/resolve-roundtrip.edl \
  --rate 24000/1001 --editor-version 21.1.0.14 \
  --fixture-manifest /private/tmp/aagedal-resolve-23976-20260919/fixture-manifest.json \
  --native-snapshot /private/tmp/aagedal-resolve-23976-20260919/native-snapshot.json \
  --output /private/tmp/aagedal-resolve-23976-20260919/native-roundtrip-recheck.json
```

Resolve may append another `.edl` suffix; use the actual saved filename without
modifying its bytes. Keep all re-exported records. The original movie directory
is required for file-provenance verification; retained manifest/sidecar copies
do not relocate or relink the media. All 18 focused helper regressions pass,
including the retained native round trip, captured no-source-timecode case and
rejection of wrong native start, rate and DF mode. The complete script-validator
suite also passes. No new application build or release-candidate
acceptance is implied.
