# Feature-qualified GPL/Metal candidate native profiles — 2026-09-30

A current Release app and test bundle, including the clock-handoff correction
and retained clock-failure diagnostics, complete three authentic production-path
meter observations linked with all eight newly built GPL/Metal MPV/FFmpeg
frameworks. Native XCTest passes in 39.557 seconds and the unchanged profile
validator accepts all three schema-2 rows.

The dependency artifact is the independently verified second build under
`/private/tmp/aagedal-coreaudio-gpl-metal-build-v2-20260930`. Its immutable builder
identity and `MPVKit-GPL` feature configuration pass verification, including
FFmpeg Metal support and both arm64/x86_64 artifact slices. This native run uses
arm64 only. The failed builder-identity receipt of the earlier first build is
not used for these observations. Upstream auxiliary artifacts remain the pinned
inputs recorded by the clean builder; this is not a rebuild of every auxiliary
dependency or a published package repin.

`prepare-candidate.py` copies the root's corrected current test host from its
focused Release DerivedData, replays the actual compiler-generated linker
invocation against its current object files, places both fresh framework search
roots first, and redirects every linker output into the copied candidate. The
link map identifies objects from all eight new frameworks and the ad-hoc app
signature verifies. Original host/test, copied candidate/test, dependency
frameworks, receipt and builder snapshot identities remain unchanged after the
run. Actual linker commands and origin receipts are retained here; raw link
maps, apps and `.xcresult` remain external.

The source head during preparation is
`060f611f7ba1d669a1af7b7846cdf1812f53b531`, with the clock-handoff source/test
correction still dirty. `source-status.txt`, `source.diff` and the complete
Swift `source-sha256.json` identify those current build inputs. Subsequent Git
commits do not change the recorded binary identities. These are development
test binaries, not clean release-candidate acceptance.

| Producer-original source / requested ordinal | Source channels | Observation / EOF snapshots | Maximum recorded EOF drift | Exact EOF source interval |
| --- | ---: | ---: | ---: | --- |
| GoPro AAC / 0 | 2 | 102 / 119 | 135.175 ms | 4,979,374–5,263,360 |
| Sony FX6 PCM24 / 0 | 1 | 105 / 121 | 240 ms | 6,424,320–6,712,320 |
| Sony FX6 PCM24 / 7 | 1 | 95 / 120 | 230 ms | 6,424,320–6,712,320 |

Every observation lasts five seconds and completes selected-track identity,
active monitor-matrix invariance, pause/resume progress, child cancellation to
zero RSS and authoritative timestamp-verified DSP EOF. All six starts identify
CoreAudio with two native output channels, preserving the selected one- or
two-channel source measurement. Release logging receipts succeed and the
unchanged validator finds no native output initialization/channel-map errors.
FX6 reports eight selectable mono tracks, not an eight-channel surround source.
The same external hashes as the earlier authentic observations are recomputed;
media stays external.

The first preparation links and signs successfully but stops while inspecting
non-UTF-8 symbol bytes in the linker map. That attempt is retained separately;
no native test ran on it. Path inspection now replaces undecodable symbol bytes
while matching every framework path exactly, and a fresh preparation produces
the qualified tested copy. This changes only evidence inspection.

Root's canonical build may overlap the profile interval after its initial
process inventory. Timing and memory values are diagnostic samples, with no
comparative performance claim. Power receipts show no system sleep. The
five-second rows do not qualify sustained playback, prove historical FX6
failure causality, demonstrate audible output/device switching, or close
supported-macOS/base-2020-M1/8-GB release acceptance. The shipping package pin
remains `230c3174f1515898f24599147ad61c2a277d0dc2`.

`proof-summary.json` joins the exact result bundle and three accepted rows.
Per-run native logs, manifests, diagnostics, summaries and power/identity
receipts are under `authentic-5s`. External app/result artifacts remain under
`/private/tmp/aagedal-live-meter-gpl-metal-native-ready-20260930`; temporary
storage is not a durable archive.
