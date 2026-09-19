# Fresh Resolve marker import — 2026-09-19

Resolve Studio 21.1.0.14, project **Aagedal Adjacent Marker Acceptance
20260919**, timeline **Unique markers semicolon**, 29.97 DF with start
`00:00:58;00` set before the first marker import. The user performed the native
**Timelines → Import → Timeline Markers from EDL** action.

The seven-finding import passes: relative frames `0, 1, 59, 60, 16241, 16242,
18280`, durations `1, 1, 3, 1, 3, 1, 1`. Exact marker text, including Unicode,
tabs, classification labels and historical source URLs, is preserved in the
API's `name` field; the API's `note` field is empty. No extra markers exist.
First/adjacent frames and minute/ten-minute DF boundaries are correct.

- `unique-markers.edl`: September 15 native app export with only event 005
  (Fixture 5, duplicate relative frame 60) omitted. No positions were changed.
- `resolve-marker-api.tsv`: actual read-only `GetMarkers()` results captured
  through Resolve's Lua console after import. Tabs/newlines inside text fields
  are escaped as `\t`/`\n`; metadata precedes the tabular header.
- `native-import-validation.json`: exact frame/duration/color/text comparison
  against that EDL, input/API hashes and unchanged-media/sidecar verification.
- `fixture-manifest.json`: fresh generated media/sidecar identities. The movies
  and original eight-finding sidecar remain outside the repository at
  `/private/tmp/aagedal-resolve-adjacent-20260919`.

The prior adjacent-frame displacement does not reproduce in this fresh import.
Its earlier cause is not established; no coordinate fix is justified by this
result. Same-frame findings remain deliberately rejected by the app exporter.

Native re-export remains pending. This reduced diagnostic does not establish
complete editor acceptance: it retains historical source URLs from September
15 rather than the fresh generated media paths, omits one finding, and covers
only 29.97 DF. Other rates, current-source identity and other editors remain
separate gates. See [the interchange run sheet](../../COMPARE_MODE_INTERCHANGE.md).
