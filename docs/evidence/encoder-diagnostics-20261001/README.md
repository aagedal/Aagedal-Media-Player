# Quiet FFmpeg failure diagnostics and DTS fixture recovery — 2026-10-01

Canonical fresh verification of `09e0026a3cd0559327609c80b74a0569616feb8a`
failed one of 760 aggregate tests: 750 passed and nine named optional checks
skipped. The failure occurred in synthetic DTS fixture encoding before the
production decoder began. The [summary](failed-candidate-test-summary.json),
[details](failed-candidate-test-details.json), [log](failed-candidate-tests.log.gz)
and [awake evidence](failed-candidate-power-events.json) retain that rejected
attempt. Static analysis, isolated transport and preflight were not reached;
this attempt is not accepted candidate evidence. A subsequent isolated repeat
passes with unchanged source, but the [direct bounded encoder trials](../dts-fixture-encoder-diagnosis-20261001/README.md)
reproduce SIGBUS in the bundled DCA encoder. Disabling SIMD also fails.

The app previously reduced a stderr-free failed child to `processFailed("")`.
All three FFmpeg wrappers now preserve exit status or signal number when stderr
is empty, whitespace-only or undecodable. Rich stderr and cancellation semantics
are preserved. Three actual-subprocess regressions exercise these cases, a
SIGTERM fixture, detailed diagnostics and successful exits emitting stderr.

The DTS decoder check now uses [pinned synthetic media](../../../Test%20Fixtures/LiveAudioMeter/README.md)
with an exact SHA-256 check; missing/changed bytes fail. Production decoding and
all existing timestamp/frame/channel/EOF assertions remain intact. No retries
or skips were added. The experimental DCA encoder defect remains unresolved;
it is now separate from the decoder regression. The asset is generated locally
and contains no producer-authentic programme material.

Focused optimized Release [summary](focused-test-summary.json) and
[details](focused-test-details.json) pass all 44 tests (30 decoder and fourteen
subprocess checks), with zero skips, failures, expected failures or runtime
warnings. The full script-validator gate also passes. This focused build
reuses DerivedData; a new fresh canonical committed-source run follows. Candidate verification/consumption require 763 aggregate tests,
all seven new Review/meter/diagnostic regressions and the pinned DTS decoder
check, plus both isolated mixed-backend transport directions.
