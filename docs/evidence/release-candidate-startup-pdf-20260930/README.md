# Integrated startup, PDF and dependency-payload continuation

Canonical optimized Release verification passes for clean implementation commit
`f2370dcfdee472e8c3aca24b8885d7aa0e489818`, using fresh DerivedData and the
validated unchanged offline package cache. No previous build products are reused.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 756 total: 747 passed, nine named opt-in skips |
| Six new app regressions | Passed, explicitly required in detailed validation |
| Isolated mixed-backend transport | Both directions passed, no skips |
| Release static analysis | Passed |
| Release preflight | All 61 checks passed |
| Script-validator gate | Passed, including 16 reconstruction and 17 publication checks |
| Final source/package/cache identity | Passed |
| Sleep, failures, expected failures, runtime warnings | Zero |

[Proof summary](proof-summary.json), exact test summaries/details, compressed
logs, environment/power receipts and [source hashes](source-sha256.json) retain
the accepted result. Full `.xcresult` bundles and built products remain at
`/private/tmp/aagedal-2-plan-startup-pdf-final-canonical-20260930`; temporary
storage is not a durable binary archive. The package lockfile SHA-256 remains
`6aea6d64326f3040345c3523a0a39c95d53335777e233b3aa311e8ba90ad475d`.

The implementation changes are:

- Live-meter startup assesses the requested source position before first PCM,
  enforcing the existing two-second catch-up allowance and canceling stalled
  workers. Requested positions cannot establish decoder synchronization.
- PDFs explicitly label source versus relative timecodes and retain complete
  values in wrapped finding text, including after different-rate relinking.
- Reconstruction audits require the exact declared source/input inventory;
  extra ignored sources, stale builds/caches, directory redirects, external
  Git pointers and nonregular files are rejected before reading the payload.
- Comparison mismatch labels avoid overflowing integer conversions and
  32-bit hour truncation, while preserving distinct finite duration values.

Additional focused receipts retain 26 Coordinator and 43 companion Debug
passes, 41 optimized Release report-export passes and thirteen final optimized
Release comparison passes, all with zero skips/failures. These focused runs
were made during independent shared-checkout work; canonical acceptance comes
from the committed-source run above. The [PDF receipt](review-timecode-provenance/verification.json)
records visual checks of all four pages across
[normal provenance](review-timecode-provenance/provenance.pdf),
[long-source](review-timecode-provenance/long-sources.pdf) and
[different-rate relink](review-timecode-provenance/timecode-provenance.pdf)
fixtures, with no clipping or overlap.

The [real reconstruction audit](payload-inventory-verification.json) passes
11,089 source files and twenty auxiliary ZIPs: exactly 11,109 payload files.
Its externally pinned publication manifest SHA-256 remains
`3eb8f8dd20ce2de6802b7d080e6df30a69ca00b6706dc408823291576b96616c`.
The unchanged local stage/workspace paths are recorded in that receipt.
This audits input inventory rather than compiling, publishing or repinning.

The first full verifier build was deliberately canceled before acceptance
when independent review found the six-significant-digit duration fallback
could collapse distinct values. Its incomplete environment and compressed
log are retained. The first focused correction run then rejected one expected
label: Swift uses scientific notation at the Int conversion boundary. Its
failure summary/details/log remain beside the passing final run; the revised
check requires both exact scientific labels and distinguishable nearby values.
These attempts supply no passing candidate evidence. Sandboxed Xcode/xcresult
launches could not write normal host caches; accepted runs use native access.

This batch supplies no new native keyboard/Full Keyboard Access/spoken
VoiceOver, editor, audible/device/surround, sustained hardware/base-M1,
public dependency publication/repin or distribution acceptance. Subsequent
documentation retention commits preserve this implementation result; release
consumption still requires matching-HEAD and package evidence.
