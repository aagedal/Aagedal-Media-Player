# Local CoreAudio dependency repair candidate — 2026-09-30

The retained IINA repair now passes the app's actual Release production live-meter
harness on this host. Two independently built local candidates passed the four
previous generated selections: audio-only mono and stereo, and both explicit
stereo-video ordinals. The final builder candidate also passed a hash-verified
Sony original. All nine schema-2 rows pass the **unchanged** profile validator,
including its native-output error rejection and required logging receipts.

This advances the repair from initialization/compile-only evidence to local
production-path evidence. The shipping MPVKit package pin remains unchanged,
and the [unchanged-package Release run](../release-output-gate/README.md) remains
rejected. This is not release acceptance or a published dependency repair.

| Local candidate | Inputs | XCTest | Validator | Native logging receipts |
| --- | --- | --- | --- | --- |
| First coherent versioned framework (`v3`) | Audio-only ordinals 0/1; stereo-video ordinals 0/1 | 1 test, 0 failures; 52.048 s | 4 rows pass | 8 |
| Final builder output | Same four selections; Sony ordinal 0 | 1 test, 0 failures; 64.842 s | 5 rows pass | 10 |

All 18 observation/EOF diagnostic starts identify `coreaudio`, with no retained
AO initialization or AudioConverter channel-map errors. Audio-only mono retains
one decoded source channel and two device-output channels; stereo retains two
of each. The production harness checks source-channel counts before and during
the active mute matrix, routing invariance, resumed source-frame progress,
child-process cancellation and final EOF drainage. Clock-drift and decoded-ahead
bounds were not changed. Driver identity and error-free logs still do not prove
actual audible output.

The authentic source is the original Sony recording
`/Users/truls.aagedal/Movies/TestVideo/Sony A1 Card/M4ROOT/CLIP/20260502_TRA_MOV_0240.MP4`,
SHA-256 `d8f32f9e827dba821a8101c7dd713580e37b03e9723c4ffbf136919829d6fbe1`,
111.36 seconds, stereo 48 kHz PCM, explicit audio ordinal zero. Its identity
matches [the earlier real-media check](../../../METADATA_REAL_MEDIA_VALIDATION.md).
The shorter known Sony original is 13.44 seconds and does not meet this harness's
20-second input requirement. Source authenticity does not supply a calibrated
or trusted live numerical reference.

## Incremental rebuild and provenance

[`rebuild-mpv-coreaudio-candidate.py`](../../../../scripts/rebuild-mpv-coreaudio-candidate.py)
checks the retained MPVKit revision, patch and three touched source hashes. It
copies the source into a new output directory, applies the attributed IINA patch,
and recompiles `ao_coreaudio.c` and `ao_coreaudio_chmap.c` for arm64 and x86_64 using
the cached flags/generated headers and current SDK. Each original object must
match the corresponding object extracted from the app's resolved framework;
the arm64 CoreAudio object must also match the diagnosed binary hash.

The script substitutes only those two objects into a copied archive for each
architecture. It rejects duplicate archive member names and verifies the member
list and every object payload afterward: **218 other objects per architecture
remain byte-identical**. Archive symbol indexes are regenerated. It builds a
universal versioned framework, preserves its binary symlink, rejects a binary
symlink escaping the isolated framework, and creates an XCFramework/ZIP checksum.

This is an incremental dependency rebuild, not a clean build of every MPVKit
component. The final receipt fingerprints the entire cached source tree,
generated headers, compile databases and compiler; the upstream source revision
is explicitly qualified as coming from the retained diagnosis. Compiler arguments
fail closed on unknown flags and response files so diagnostic/profiling/temp
outputs cannot accidentally write into the input cache. The original production
candidate was built with the six safety checks available at that time; the
follow-up below strengthens those checks without changing its retained evidence.

```bash
python3 scripts/rebuild-mpv-coreaudio-candidate.py \
  /Users/truls.aagedal/Developer/MPVKit \
  /tmp/aagedal-mono-20260930-derived/Build/Products/Debug/Libmpv.framework \
  /tmp/new-coreaudio-candidate
```

The first and final candidates contain identical patched C/header contents.
Their absolute build paths appear in compiled diagnostics, so artifact hashes
are recorded separately. Only the final candidate was produced with the final
builder's additional fail-closed flags and provenance fields.

## Actual production harness and retained evidence

An isolated Release `build-for-testing` used current app source and the normal
pinned dependencies. The actual generated app linker invocation was replayed
with the candidate's framework directory first in its search path. Link maps
confirm both patched CoreAudio objects came from that candidate. The resulting
isolated test app was signed ad hoc, and its exact generated XCTest manifest
ran the existing `LiveAudioMeterPerformanceTests` production harness without
source or playback-option substitutions. No subsequent Xcode rebuild replaced
the candidate before these runs. The worktree was in development during the
build; the starting Git revision and diff hash are retained rather than claiming
a clean release binary.

[`proof-summary.json`](proof-summary.json) ties the final builder hash, input
identities, build/link artifacts, test durations, logging receipts and passing
rows together. [`final-build-receipt.json`](final-build-receipt.json) and
[`first-build-receipt.json`](first-build-receipt.json) retain dependency provenance.
Each run directory retains its manifest, validator summary, full native log and
playback diagnostics. Full build logs, actual relink commands, `.xcresult`
bundles and exported attachments remain under
`/tmp/aagedal-coreaudio-production-candidate-20260930`;
the final universal candidate and ZIP remain under
`/tmp/aagedal-coreaudio-rebuilt-final-20260930`.

No power/sleep acceptance check was performed in this isolated manifest-run
procedure. Only arm64 playback on the current default two-channel output was
exercised. The IINA candidate's device-switch refresh work remains open. A full
MPVKit build, immutable artifact publication/checksum and app package repin,
followed by supported-device/macOS, device-switch, surround, actual audible-output
and base-M1 checks, remain necessary before closing the shipping native-output
gate. No fallback driver, forced-stereo policy or freshness-limit relaxation was
introduced into production.

## Input-preservation guard follow-up

The builder now fingerprints the cached source tree, framework payload and
symlinks, retained patch/identity record, compile databases, generated headers
and the four cached objects before running build tools. It rechecks every
recorded input before writing a successful receipt. Any mismatch fails the
build, and only a matching result receives `inputsUnchanged: true`. Files can
remain in a failed output directory; a ZIP without a successful receipt does
not establish a verified candidate.

Archive member paths are rejected before extraction, including absolute paths,
parent traversal and control characters. Cached `-arch` and `-target` flags must
agree with the requested architecture, with no repeated flags. Source and
framework symlinks must remain inside their respective trees, so the copy cannot
pull unrecorded external source payloads or retain links to the original
framework. Twelve builder safety regressions pass.

An actual universal incremental rebuild using the same retained checkout and
resolved framework completed successfully at
`/tmp/aagedal-coreaudio-input-guards-final-20260930`. Both architecture archives
retain 218 unrelated objects byte-for-byte, and the final input snapshot matches
the initial snapshot. Its [receipt](input-guard-rebuild-receipt.json) records
the new candidate/ZIP identities and complete input snapshot. The native
production harness was not rerun for this follow-up candidate; the earlier
candidate's playback evidence above remains tied to its original identities.

These checks verify the recorded cached inputs were preserved. They do not
establish an upstream clean source tree, a full immutable build of all dependency
components, or immutable SDK/external dependency headers. Those release-build
requirements and the shipping package repin remain open.
