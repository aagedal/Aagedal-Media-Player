# Review range, decoder shutdown and Premiere scan order — 2026-10-01

Three concrete defects are corrected. Erasing a saved Review range endpoint
now explains the explicit Clear range action on passive departure, preserving
both its saved endpoint and pending draft. Timestamp failures/cancellation now
release downstream PCM callbacks held by playback pacing, retaining the
original failure rather than hanging subprocess shutdown. Premiere XML now
preserves known progressive/top/bottom field order in source and sequence;
unknown order stays unspecified and mixed/unsupported order requires CSV/PDF.
The comparator also detects effective clip overrides and malformed field order.

All 138 [initial focused optimized Release tests](focused-test-summary.json)
pass: 29 Review, 49 exporter, 32 decoder and 28 coordinator checks, with no
skips, failures or XCTest runtime warnings. After that run, the two new decoder
tests were strengthened with a deterministic snapshot-handler handshake.
They establish that the consumer is midway through synthetic silence or
verified PCM before failure/cancellation, without relying on a scheduling delay.

Running that final harness against the original decoder from `d390be5` gives
[two expected failures](decoder-baseline-test-summary.json): blocked completion
and lost typed diagnostics produce four assertions. Cleanup releases the gate,
so the test host does not hang. The fixed source is restored automatically;
[the same two tests pass](decoder-fixed-test-summary.json) without skips or
runtime warnings. These rejected baseline results are regression proof, not a
candidate failure. The final clean-checkout candidate runs the stronger harness.

The [22 Premiere comparator checks](premiere-comparator-tests.log) and
[18 release-script checks](release-script-tests.log) pass. Three new exporter,
one Review and two decoder regressions raise aggregate candidate consumption
to 781, with all six required by exact identity. Both isolated mixed-backend
transport directions remain required. The original initial focused log and
baseline/fixed logs are compressed beside their full summaries/details.
[Proof](proof-summary.json) and [source hashes](source-sha256.json) preserve
the distinction between the initial focus and the final deterministic harness.

Full xcresult bundles remain under `/private/tmp/aagedal-range-meter-field-order-focused-20261001.xcresult`
and `/private/tmp/aagedal-decoder-shutdown-{baseline,fixed}-20261001.xcresult`.
Native Premiere import/marker/render/re-export, keyboard/spoken accessibility,
public dependencies, audible/device/surround, hardware/soak/base-M1 and
signing/notarization/distribution acceptance remain open. No dependency pin,
release version or remote publication changes are made by this batch. Fresh
canonical verification follows at its committed implementation identity.
