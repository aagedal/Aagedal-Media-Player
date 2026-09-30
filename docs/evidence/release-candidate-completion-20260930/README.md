# Integrated 2.0 continuation verification — 2026-09-30

Canonical optimized Release verification passes for clean implementation commit
`f5411b154dd6065a4901132a487b27ccf6d51058`. A detached source-only clone uses
fresh DerivedData, the unchanged validated package cache and 38 hashed existing
generated fixtures. No build database or products are copied.

| Gate | Result |
| --- | --- |
| Aggregate XCTest | 745 total: 736 passed, nine named opt-in skips |
| Five new Review/DTS regressions | All passed; exact required-test validation |
| Isolated mixed-backend transport | Two passed, no skips |
| Focused Review/decoder Release tests | 47 passed, no skips |
| Release static analysis | Passed |
| Release preflight | All 61 checks passed |
| Script validators and power/source/package/cache checks | Passed |
| XCTest failures, expected failures and runtime warnings | Zero |

[Proof summary](proof-summary.json), test reports, compressed logs, source and
fixture hashes, and power receipts retain the accepted run. Complete result
bundles remain at `/private/tmp/aagedal-2-plan-completion-verification-v2-20260930`.
Temporary storage is not a durable archive of apps or result bundles.

The first verifier launcher used the clone's script with the original checkout
as working directory. It was stopped before Xcode built the app and restarted
with the clone explicitly selected into a new output directory. No app
verification is attributed to that aborted launcher. A sandboxed focused
preflight also rejected the bundled binary signature; the same unchanged source
passes all 61 checks with native macOS security-service access. Both focused
preflight outputs are retained.

## Independent script-only correction

Independent review reproduces host Git attributes changing reconstruction
semantics despite configuration isolation. Commit `9c32a44` disables inherited
attributes and adds an active adversarial UTF-16 regression. Sixteen publication
tests, eighteen clean-candidate tests and the final complete script-validator
gate pass. Actual retained-stage reconstruction also passes under the hostile
attributes file; see [reconstruction follow-up](../coreaudio-offline-reconstruction-20260930/README.md).

[Script follow-up identity](script-followup-source-identity.json) proves every
app/test Swift source and the package lockfile match the canonical run. Its
final script tests are retained separately. This does not attribute a new app
build or full XCTest run to the script-only commit.

The [eight-hour programme profile](../programme-eight-hour-production-20260930/README.md)
passes all six workloads without sleep as a separate observation against the
same verified implementation. These checks leave public dependency publication/repin,
native keyboard/Full Keyboard Access/spoken VoiceOver, DTS-HD MA qualification,
hardware/soak/editor and distribution acceptance open. Documentation retention
does not replace the normal matching-HEAD release-consumption gate.
