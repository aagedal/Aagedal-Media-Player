# Paused comparison alignment diagnosis — 2026-09-30

The first canonical Release verifier at clean source commit
`8626ae9` fails one mixed-backend test. It records 722 passes, eight explicit
optional skips and one failure (731 total), with no expected failures or runtime
warnings. The failed test is
`CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryApplyManualAlignmentDuringTransport()`.
Both paused offsets (+0.5 and −0.5 seconds) fail to settle, and their following
secondary-paused assertions fail. The aggregate summary retains the first
assertion; detailed outcomes retain all four. The primary remains paused at its
requested two-second frame while the secondary is playing.

The unchanged test passes in a fresh isolated Release runner (one pass, no
skips/failures/runtime warnings). This is evidence of an intermittent failure,
not a passing canonical candidate or proof of its cause. No sleep is observed
during the failed suite. The canonical verifier stops at XCTest failure, before
isolated transport, analysis, preflight and final identity validation.

Raw result bundles and full logs remain at
`/tmp/aagedal-authentic-continuation-candidate-20260930` and
`/tmp/aagedal-manual-alignment-isolated-20260930.xcresult`.
The retained environment, summaries, details, isolated validator and power
receipt have SHA-256 identities in `evidence-sha256.json`.

The subsequent investigation tests the concrete mechanism in which an
asynchronously published primary playing observation arrives after explicit
Pause, and an alignment/seek mistakenly uses that observation to resume B.
The first failure lacks instantaneous controller-state witnesses establishing
that mechanism as its cause. Regression results and the final correction will
be recorded separately below.

## Deterministic baseline regression

The new regression runs against unchanged production controller code, using
real paused MPV decoders and an explicitly simulated delayed primary playing
cache. MPV's asynchronous event handler publishes that cache on the main queue;
changing the cached flag does not send Play to its decoder. Alignment/seek
resumes B, which is still playing and reaches 3.208333 seconds instead of the
requested 2.5 ± 1/24 seconds. A stays at two seconds. The executed test fails in
1.758 seconds; its three assertions are retained in the baseline detailed result.
This establishes the delayed-observation bug, while the original mixed-backend
failure's precise event ordering remains unobserved.

`reconstructed-baseline-test-source.swift` contains the executed test function
reconstructed after the run, before later reload/shuttle extensions. It is not
an original whole-file snapshot. The baseline raw bundle/log are at
`/tmp/aagedal-pause-intent-baseline-executed-20260930.{xcresult,log}`. Earlier
cache/sandbox and compilation attempts did not execute the regression and are
separate; they are not counted as its failing baseline.

## Correction and focused verification

Explicit Pause now belongs to the primary controller identity. It remains
authoritative through alignment/seek, readiness, geometry reload and audio-track
selection. Replacing only B preserves that intent; a different A or session stop
clears it. Explicit Play/toggle/forward/reverse shuttle clears the intent and
cancels the old pause-settlement task. The next toggle resumes even if the
previous decoder playing observation is late.

All **15 optimized Release cases pass**, with no skips, failures, expected
failures or runtime warnings: the new delayed-observation regression, both
manual-alignment and shared-transport directions, and ten lifecycle cases.
The exact detailed validator requires the new case and all four live transport
cases. Controller/test source hashes are in `corrected-source-identities.json`;
source snapshots, log and result bundle remain under `/tmp/aagedal-pause-intent-final-*`.
The new regression tests actual paused frame positions through reload and
explicit toggle/shuttle recovery, keeping the 1/24-second tolerance unchanged.
The initial Pause-only correction raises consumption to 732 aggregate tests
plus both isolated shared-transport directions. The additional loading regression
subsequently raises the floor to 733. A full clean committed-source verifier
is still required; this focused pass does not replace it.

An intermediate corrected run passed the original alignment/seek mechanism,
both manual directions and lifecycle checks, but an added reload assertion
recorded transient B playing publications during backend initialization despite
final A/B paused states. The final reload assertion measures actual decoder
clocks through `playbackTimeSnapshot()` after 500 ms, alongside paused states,
so teardown/cache notifications are not mistaken for decoder Play. The original
alignment observation assertion remains. `reconstructed-interim-test-source.swift`
is explicitly reconstructed; the raw failed intermediate bundle remains at
`/tmp/aagedal-pause-intent-fixed-20260930.xcresult`. The final extended test is not
claimed byte-identical to the original baseline function.

## Replacement loading and delayed Play acknowledgement

Read-only review found a missed route in the correction: replacing B temporarily
clears its URL while metadata loads, so keyboard Play/shuttle and the playback
button formerly called A directly. Those controls now keep using the session
while `isLoading`, allowing explicit playback to clear preserved Pause intent.
A separate suspended-loader regression exercises deliberate Play, slow forward
and Pause through replacement on real AVFoundation/MPV backends. Its first
16-case focused run passes (`loading-routing-*` receipts), but waits for A's
playing acknowledgement before releasing metadata and therefore does not cover
the delayed-ack path.

The extended regression holds only A's MPV playing cache at its old paused value
while the real decoder advances through B readiness. After acknowledging A,
B remains paused at 3.083333 seconds while A reaches 5.208333. The test fails
in 7.555 seconds (`loading-ack-baseline-*` receipts). Exact before-fix full source
snapshots are retained in `/tmp`, with hashes in the baseline source identity
receipt. This reproduces the second bug without changing either decoder's real
transport or increasing the tolerance/deadline.

The session now retains explicit loading playback intent until B readiness
can arm drift monitoring. The monitor starts B after A acknowledges Play.
New loads, stop, Pause and terminal failure/timeout clear the capture; existing
generation/preparation checks prevent an obsolete load consuming a later
request. This is production-path transport evidence; no native keyboard
command delivery, Full Keyboard Access or spoken VoiceOver acceptance is added.
All **16 final optimized Release cases pass**, with no skips/failures/expected
failures/runtime warnings. The detailed validator requires both new regressions,
both manual-alignment directions and both shared-transport directions; ten
lifecycle cases also pass. `final-focused-*` retains those results, and
`final-source-identities.json` hashes the exact controller/test/command/button
sources against the retained full snapshots. The final delayed-ack case runs
in 4.750 seconds. Consumption requires 733 aggregate tests plus both isolated
transport directions. The fresh clean committed-source candidate run follows.
