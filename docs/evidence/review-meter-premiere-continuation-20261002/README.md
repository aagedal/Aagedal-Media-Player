# Review, meter panel and Premiere continuation — 2026-10-02

The batch fixes explicit Review Return using stale saved text after a
same-sidecar merge, terminal meter-controller reopening, and authored CR/CRLF
normalization in the Premiere XML carrier. The independent Premiere comparator
also rejects nested scalar XML instead of dropping child/tail text.

| Focused optimized Release gate | Result |
| --- | --- |
| Review text commit | 37 passed |
| Live-meter coordinator/decoder/session/window/transport/source/display/DSP/presentation | 113 passed |
| Review report exporter | 52 passed |
| New required identities | Seven, all passed |
| Skips, failures, expected failures, runtime warnings | Zero in corrected focused runs |
| Complete script-validator suite | Passed, including 31 Premiere checks |

The two new panel tests fail on the preceding implementation because a closed
controller becomes visible again. [Baseline summary](meter-baseline-summary.json)
and detailed cases retain those failures. The
[comparator reproduction](comparator-baseline-reproduction.json) retains the
preceding false exact-match and corrected invalid result for hidden nested text.

Summaries, detailed cases, compressed build/test logs and
[source hashes](source-sha256.json) bind the focused results. Tests use optimized
Release with recorded package versions and the verified unchanged offline cache
at `/private/tmp/aagedal-itu-live-dd-20260930/SourcePackages`. Full xcresult bundles
remain under `/private/tmp/aagedal-review-return-accepted-20261002.xcresult`,
`/private/tmp/aagedal-live-meter-lifecycle-20261002/` and
`/private/tmp/aagedal-premiere-whitespace-focused-20261002.xcresult`; temporary
storage is not a durable binary archive. Initial sandbox cache denials were
resolved through normal Xcode/xcresulttool cache access, without package changes.

Candidate/release checks require all seven new identities and 795 aggregate
tests, plus both isolated mixed-backend transport directions. Focused checks
alone do not establish a clean committed-source canonical candidate.

Native Premiere binding returned only a menu bar after 1,947 seconds and no
usable project state. No new native acceptance is inferred. Parsed carrier
whitespace coverage does not establish Premiere's treatment of user formatting.
All five retained native XML receipts preserve their recorded differences;
their media bytes are absent from the committed receipts and are not re-proved.
Interlaced/PAR/rotation/range/rate/conform, keyboard/spoken accessibility,
dependency publication/repins, audible/device/surround, sustained/base-M1 and
signing/notarization/distribution gates remain open. No release was published.
