# Integrated bounded-reader continuation verification — 2026-09-30

The canonical optimized Release verifier passes for implementation commit
`82597597ba3e4f854799b03857a916d864873cab` from a clean detached Git clone with
fresh DerivedData. Shipping package revisions and app version 1.6.1 (163) are
unchanged. This verifies the committed Review correction ownership, retained
meter failure context, clock/handoff race corrections and dependency builder
tooling. The separate local dependency candidates are not shipping repins.

| Gate | Accepted result |
| --- | --- |
| Aggregate XCTest | 738 total: 730 passed, eight allowlisted opt-in skips |
| Five new app regressions | All passed; exact-count/required-test validation retained |
| Isolated mixed-backend transport | Two passed, no skips |
| Static analysis | `ANALYZE SUCCEEDED` |
| Source release preflight | 61 checks passed |
| Script syntax and validator self-tests | Passed, including 18 builder and 15 release-script tests |
| Runtime warnings / failures / expected failures | Zero in both XCTest bundles |
| Verification power evidence | No sleep observed |
| Final source/package cache identity | Clean source, unchanged pinned cache checkouts |

The accepted environment is macOS 27.0.1 (26A434), arm64 MacBook Pro, Xcode
27.0 (27A266a). The verifier ran from 19:27:01 to 19:32:36 UTC.
`source-and-preparation-identity.json` records the command, exact source files,
lockfile, clean checkout and full FFmpeg binary used for fixture preparation.
Summaries and complete test details are retained alongside validation, preflight,
script and power receipts. `external-artifact-sha256.json` binds original logs
and every file in both accepted result bundles and the rejected first bundle.
Full apps, DerivedData, logs and result bundles remain under
`/private/tmp/aagedal-2-plan-integrated-with-fixtures-20260930`; temporary storage
is not a durable archive.

## Rejected missing-fixture attempt

The first clean clone lacked the ignored `Test Fixtures/Generated` tree.
XCTest reported 738 total tests, 686 passes and 52 skips without failures,
but the unchanged verifier correctly rejected 44 unexpected fixture skips.
Its original summary, details and rejection are retained in
`rejected-missing-generated-fixtures`; full artifacts remain under
`/private/tmp/aagedal-2-plan-integrated-candidate-20260930`.

The existing opt-in `scripts/generate-test-fixtures.sh` then generated schema-5
fixtures using the full Homebrew FFmpeg 9.0.2 encoder build. The generation log,
manifest and complete generated-file SHA256 inventory are retained here. A new
verifier directory passed with the existing eight opt-in skips. No skip rule,
test expectation, timeout or synchronization tolerance was relaxed.

## Acceptance limits

These automated results do not close spoken accessibility, supported-macOS,
base-M1/8-GB, audible/device/surround, sustained authentic playback, remaining
editor or distribution acceptance. Separate bounded-MXF production evidence and
GPL/Metal native profiles identify their own source and binary inputs. Immutable
upstream dependency publication, fresh package resolution and shipping repins
remain open. This documentation retention commit follows the verified
implementation commit; release consumption still requires matching final HEAD
and retained evidence under the ordinary release checks.
