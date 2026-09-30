# FX6 synchronization qualification continuation — 2026-09-30

`prepare-repeat.py` creates a new manifest for the retained local incremental
or full-built candidate, verifies every copied app/test/linked-dependency identity
and the producer-original FX6 SHA-256, and requests ordinal zero or seven. It
does not rebuild, relink, modify the shipping dependency pin or overwrite any
historical manifest. The full-built artifact retains the previously recorded
GPL/Metal feature-parity limitations. A five-second observation is for repeated
startup/near-EOF investigation, not sustained-play qualification.
The incremental identity manifest also carries receipts for the original
shipping-pin DerivedData cache. The earlier authentic-check report documents
that root subsequently reused that cache; these unrelated historical receipts
are recorded separately as `unlinkedOriginalCacheChanges`, while any change to
the actual copied candidate or its linked artifacts fails preparation.

Current source also retains bounded clock rejection context after removing the
invalid visible reading and cancelling the decoder. The native harness now
attaches the rejected generation, request start, decoded endpoint, playback
clock, drift, publication count, prior synchronization/ahead suspension state
and final worker allowance. A coordinator regression covers the near-EOF
failure, worker cancellation, stale callback isolation and retry reset. The
250-ms freshness/admission limits and FFmpeg pacing remain unchanged. Historical
binaries do not include this new diagnostic instrumentation.

`testvideo-duration-inventory.json` records a read-only FFprobe inspection of 76
audio/video containers under the established external `Movies/TestVideo` test
collection. All probes succeeded. No source has 1,810 seconds of audio and
container headroom for the existing 1,800-second sustained observation. The
longest source reports 1,420.109206 seconds; the authentic Sony FX6 source
remains 139.84 seconds. This inspection cannot close the authentic 30-minute
gate. It does not substitute a concatenated or looped source. Input media stays
external; duration inspection alone does not establish permission or complete
meterability/accuracy.

The profile validator's existing 23 regressions pass, and `git diff --check`
passes. Root will compile and execute the new coordinator regression in its
focused and canonical verification; this folder's native runs use historical
binaries and cannot qualify the new instrumentation.

Root's first focused Release run compiles the instrumentation and executes 21
coordinator tests: 20 pass and the new test fails solely on its expected worker
allowance. The test assumed the exact decimal boundary 6,453,600; the existing
gate floors the binary representation of playback time 134.20 before adding
12,000 frames, producing 6,453,599. The assertion is corrected to that strict
existing bound; production code and thresholds are unchanged. The first failure
is retained in `first-focused-failure.log` and its JSON receipt. Root's corrected
Release run passes all 34 focused checks, including all 21 coordinator tests;
the targeted test and suite receipts are retained in `corrected-focused.log`.

Three five-second repeats each pass the unchanged profile validator and native
XCTest on the current M5 Pro host:

| Retained candidate / selected ordinal | Observation / EOF snapshots | Maximum recorded EOF drift | XCTest wall time |
| --- | ---: | ---: | ---: |
| Incremental / 0 | 104 / 121 | 220 ms | 13.314 s |
| Full-built / 0 | 105 / 120 | 230 ms | 13.484 s |
| Full-built / 7 | 98 / 120 | 240 ms | 13.472 s |

Every EOF interval covers source frames 6,424,320–6,712,320 exactly, with 288,000
timestamp-authorized frames, final DSP EOF and no synthetic initial silence.
Selected mono source tracks remain one channel while native output uses stereo.
Both starts per run report CoreAudio and native logging receipts; the unchanged
validator rejects output-initialization/channel-map errors and accepts all three
rows. Copied candidate app/test and linked-dependency hashes match before/after.
These runs do not reproduce the retained incremental near-EOF failure; three
passes do not establish its cause or reliable repeated behavior.

The fresh corrected GPL/Metal dependency build was running concurrently; each
run retains its process inventory showing active Xcode/Clang work. The repeats
are diagnostic observations, not comparative timing/performance benchmarks.
Power records show no system sleep. Original media, copied apps and `.xcresult`
bundles remain external under `/private/tmp/aagedal-fx6-repeat-20260930` and the
historical candidate directory; temporary storage is not a durable archive.
Per-run manifests, playback diagnostics, native logs, validated summaries,
power receipts and identities are retained here. `repeat-results.json` joins
their native receipts. The shipping pin, feature-parity qualification, audible
output/device checks, 30-minute soak and base-2020-M1/8-GB release gates stay open.
