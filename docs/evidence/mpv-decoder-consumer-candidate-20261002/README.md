# Guarded MPV decoder-raster consumer candidate — 2026-10-02

Canonical optimized Release verification passes at clean implementation commit
`d18b349b34cafb848e08061aeebc0a0d0643b386` with fresh DerivedData and freshly
resolved published package pins.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 826 total: 817 passed, nine named opt-in skips |
| New provider/loupe regressions | All eight required identities passed |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Static analysis | Passed |
| Source release preflight | All 61 checks passed |
| Script validators | Passed |
| Source/package/cache/power identity | Passed |
| Failures, expected failures, runtime warnings, sleep | Zero |

The linked shipping MPVKit pin is unchanged. The real MPV fallback test retains
its expected preview/quadrants and rejects source proof even when screenshot
and coded dimensions match. Synthetic response tests qualify consumer rejection
and memory layout; they do not establish a provider's raster provenance.

Full products/result bundles remain at
`/private/tmp/aagedal-2-decoder-consumer-candidate-20261002`. Temporary storage is
not a durable binary archive. Later provider-candidate or documentation work does
not replace matching-HEAD release consumption. The general MPV source-pixel gate,
editor/native/hardware acceptance and signed distribution remain open. See the
[provider engineering status](../../MPV_DECODER_RASTER_PROVIDER.md) and
[manual completion checklist](../../RELEASE_2_MANUAL_COMPLETION.md).
