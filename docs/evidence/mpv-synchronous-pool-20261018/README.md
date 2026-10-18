# Synchronous window pool-boundary experiment

This implements the controlled synchronous pool experiment requested by the
[retirement handoff](../../MPV_NATIVE_RASTER_HANDOFF.md), following the
[allocation-origin evidence](../mpv-allocation-stacks-20261018/README.md).
It is a reduced construction/close experiment, separate from sustained playback.

## Retained observation

The arm64 Release build, deep/strict signature verification and **77 focused
hosted checks** pass with zero failures, skips or runtime warnings, including all
20 native raster fixture cases, native scopes, comparison publication provenance
and loupe/capture lifecycle checks. [XCTest summary](focused/summary.json) and
[candidate receipt](candidate-receipt.json) retain source/binary and fixture identity.
No MPVKit compilation was needed.

The arm64 Release experiment records 144 scalar snapshots across all 36
synchronous lifecycles. Every control window survives close and the following
within-pool snapshots, then retires at outer-pool drain. Every nested-treatment
window survives close, then retires at nested-pool drain. This holds in all six
iterations of each content configuration with alternating arm order. The 24
explicitly installed AppKit/SwiftUI hosts show the same pattern; every pure Swift
sentinel has already retired when the constructor/close helper returns.

These matched reduced fixtures establish retirement across the explicit pool
boundary in this process. They narrow the construction/close case without
attributing an autorelease insertion site, carrying the observation over to
production-root playback, or explaining earlier workload memory rejections.
[Scalar summary](pool-summary.json) and the compressed complete observation receipt
retain every arm and checkpoint, including initial observations and identities.

## Method

One synchronous main-actor XCTest creates 36 windows: six paired iterations
for each of three content configurations. `bare` installs no custom content
(NSWindow still creates its framework default content); `appkit` installs an
NSView; `swiftui` installs an NSHostingView containing a static black rectangle.
Each uses the comparison fixture's 960×540 `.titled`, `.buffered`, nondeferred
window, `isReleasedWhenClosed=false`, order-front, detach-content, and close
operations. No media, decoder, production comparison root, or live scope is mounted.

Each arm has its own explicit outer autorelease pool. The treatment runs its
construction/close helper inside an additional nested pool; the control runs
that same helper directly in its outer pool. Arm order alternates each iteration.
The non-inlined helper returns before any retirement observation so its explicit
strong locals have expired. A pure Swift sentinel verifies this ARC boundary.
The weak registry records scalar identity/liveness after close, after the inner
boundary, before outer drain, and after outer drain: 144 snapshots in total.

There are no awaits, run-loop pumping, relationship getters, or logging/JSON
serialization inside the pools. Scalar snapshot/dictionary construction does
occur inside each arm's pools and is part of these observation conditions.
Live construction counts, exact fixture coverage, sentinel retirement, and
monotonic weak retirement are asserted. AppKit liveness is an observed result,
not a platform-independent synchronous deallocation requirement. The complete
receipt is retained as an XCTest attachment and in the action log.

## Reproduce

From the repository root, `prepare.py` verifies the committed baseline bundle,
existing scope delta and complete local MPVKit package, then prepares current
app/test sources without compiling the dependency. It requires the retained
local paths named in that script; restore them using the handoff if absent.
Build the prepared app for testing with the arm64 Release command in the retained
build log, then run `python3 docs/evidence/mpv-synchronous-pool-20261018/run-validation.py`.
This checks the signature, runs focused hosted validation with all 20 native
raster fixtures, and strictly validates/retains the synchronous observations.
An initial postprocessing attempt rejected Xcode's escaped action-log JSON;
the original script/error are retained separately. The corrected collector reads
the unescaped xcodebuild stdout and validates all 144 observations from the same
passing test run. `run-validation.py --collect-existing` repeats collection without
rerunning XCTest; `collection-inputs.json` pins this final collector and its inputs.
The `.xctestrun` source remains unchanged; the focused runner uses a temporary
copy with the native provider explicitly enabled. Ordinary provider defaults
and shipping package pins remain unchanged.

## Interpretation limits

A release across a pool boundary supports a bounded pool-lifetime observation
under this fixture and observer. It does not identify autorelease insertion,
retaining ownership paths, or the cause of sustained workload memory growth.
The static host and synchronous lifecycle differ from the async production-root
comparison workload; no run-loop/framework-delayed retirement is qualified here.
Earlier rejected memory/drift/fallback runs and detached-host survival remain
unexplained. No production teardown, capture scheduling, memory gate, MPVKit,
shipping package pin, or native-provider default changes are justified by this
experiment. Quiet-host, authentic-media, sanitizer and physical HDR qualification
remain separate work.
