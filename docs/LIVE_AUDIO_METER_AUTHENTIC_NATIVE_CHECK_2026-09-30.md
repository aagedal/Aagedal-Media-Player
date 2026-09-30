# Authentic live-meter native observations — 2026-09-30

Two producer-original AAC camera recordings complete 90-second production
observations using the local incremental CoreAudio repair. A separate current
app linked with all eight freshly built MPV/FFmpeg frameworks completes authentic
AAC, deliberate Sony FX6 track selections and a sample-preserving ITU 5.1
preparation. The matched FX6 ordinal-zero run completes 120 seconds plus routing,
cancellation and authoritative EOF on the full-built candidate.

The shipping MPVKit package revision remains
`230c3174f1515898f24599147ad61c2a277d0dc2`. These are isolated local dependency
candidates, not shipping-pin or release-floor acceptance. An earlier incremental
FX6 run loses synchronization near EOF; its failure remains retained and
unexplained despite the later successful matched repeat.

A subsequent recipe audit finds that the full-built candidate disables GPL
components and FFmpeg Metal support, whereas the shipping MPVKit-GPL build
enables them. These playback results remain valid for their recorded artifacts,
but do not establish shipping feature parity. The corrected builder requires
the GPL product and the missing Xcode Metal compiler before a replacement build.
See [configuration parity audit](evidence/live-meter-native-output-20260930/clean-rebuild/README.md).

A later feature-qualified fresh GPL/Metal build now passes independent receipt,
source/object/artifact and required-feature checks on both architecture slices.
A separately linked corrected current Release app passes GoPro AAC and FX6 mono
ordinals zero/seven five-second observation/EOF profiles without native output
errors. Two pending DSP/clock races are deterministically fixed, while historical
FX6 causality remains unproven. These later results supplement the historical
configuration-limited runs below. See [new artifact profiles](evidence/live-meter-gpl-metal-native-20260930/README.md)
and [fresh GPL/Metal build](evidence/coreaudio-gpl-metal-20260930/README.md).

## Inputs and completed runs

The GoPro and DJI originals retain the exact SHA-256 identities from
[the camera metadata check](METADATA_REAL_MEDIA_VALIDATION.md). The Sony FX6
original is from the same external camera-media collection, with eight separate
48 kHz PCM24 **mono tracks**. Eight selectable tracks do not constitute an
eight-channel surround layout.

| Input | Duration | Selected audio | SHA-256 |
| --- | ---: | --- | --- |
| `DolomitesSet1-Hero9-GX019609.MP4` | 109.7096 s container / 109.6533 s audio | AAC stereo, 48 kHz, ordinal 0 | `e8e87cd4fdc21085fb1df8c540ed4ed8a2687f615a8d1c77c69da41cb8f6b20d` |
| `NightSet1-Action4-DJI_20230905195641_0033_D.MP4` | 109.6533 s | AAC stereo, 48 kHz, ordinal 0 | `9bde57a41e90bc1fb4cd0aab7e0865f4786f939044d884424d9f10c2b4f20f00` |
| `OJ_FX6A0021.MXF` | 139.84 s | PCM24 mono, 48 kHz, explicit ordinals 0 and 7 | `5d1c636920c80e7ce83af6486a8de9184c5cacee8a316e799dbb52e8f02174a8` |
| ITU 6ch VinCntr, prepared 5.1(side) | 83.220458 s | PCM16, six channels, 48 kHz, ordinal 0 | Prepared `01fd864e6ad367d792443023ace2713cddb12c3cbaa2d6e6afede57c5a92f159` |

The ITU original hash is
`ef2a0baef7f50db39eddfb1ba6f2a5445646050d113f81c6365cddca7f0448a0`.
Its classic PCM header contains no speaker mask. The temporary preparation
preserves every PCM word and channel position and supplies the existing
reference workflow's explicit L/R/C/LFE/Ls/Rs `5.1(side)` mask `0x60f`.
The original and prepared PCM both hash to
`5e1020672b02d963f98aab2d827961656f941da79ab4b14733f62b574737848f`.
This is qualified prepared-layout coverage, not direct speaker-role inference
for the unlabelled original. The preparation receipt and script are retained;
no source audio is added to the repository.

| Artifact run | Local dependency candidate | Completed observations | Result |
| --- | --- | --- | --- |
| `compressed-90s` | Retained incremental repair | GoPro 90 s; DJI 90 s | 2 schema-2 rows pass; XCTest 196.125 s |
| `fx6-selected-120s` | Retained incremental repair | Ordinal 0 proceeds through observation/routing/resume, then fails near EOF; ordinal 7 is not reached | XCTest fails at 122.755 s; no complete row or passing summary |
| `fullbuild-authentic-30s` | Fresh full MPV + seven FFmpeg frameworks | GoPro 30 s; FX6 ordinal 7 30 s; prepared ITU 5.1 30 s | 3 schema-2 rows pass; XCTest 114.634 s |
| `fullbuild-fx6-120s` | Same full-built candidate | FX6 ordinal 0 120 s | 1 schema-2 row passes; XCTest 128.388 s |

All six passing rows satisfy the unchanged native-output/profile validator:
explicit requested/resolved track identity, sampled child memory, active
source-channel monitoring matrix, invariant meter generation/source/paused
reading during routing, resumed source progress, child cancellation to zero
RSS, and final timestamp-verified DSP EOF. Both FX6 selections report eight
available tracks, matching metadata and FFmpeg audio ordinals. All twelve
observation/EOF starts in passing runs identify CoreAudio and retain successful
native logging receipts, with no output-initialization or AudioConverter
channel-map errors. The rejected run also has no such output errors.

The ITU observation retains six decoder channels before and during the active
mute matrix while native output has two channels. The same check retains one
source channel for FX6 mono and two for AAC stereo. This exercises source
preservation on the current stereo output; it does not test a surround device.

## Sampled timing and memory

The host is a MacBook Pro Mac17,8, M5 Pro, 64 GB, macOS 27.0.1 (26A434),
Xcode 27.0 (27A266a). The retained native output inventory identifies the default
MacBook Pro Speakers with two channels at 48 kHz. Tests had exclusive native
app/XCTest transport intervals. Other dependency build/audit work occurred
during this continuation, so these sampled observations are not comparative
CPU/throughput benchmarks. All four retained intervals report no system sleep.

App/child peaks below include the separate near-EOF segment. They are sampled
independently every 20 ms, may miss brief peaks, and need not be simultaneous.

| Candidate / source | Observation | Snapshots | First reading | Maximum snapshot interval | Maximum decoded ahead | App / child peak | Cancellation |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Incremental / GoPro | 90 s | 1,782 | 64.75 ms | 204.86 ms | 249.97 ms | 412.05 / 20.14 MiB | 0.85 ms |
| Incremental / DJI | 90 s | 1,786 | 65.21 ms | 201.01 ms | 249.97 ms | 470.02 / 20.77 MiB | 0.92 ms |
| Full-built / GoPro | 30 s | 604 | 65.90 ms | 203.11 ms | 249.93 ms | 397.02 / 20.05 MiB | 0.60 ms |
| Full-built / FX6 ordinal 7 | 30 s | 548 | 168.49 ms | 191.60 ms | 250.00 ms | 526.62 / 103.11 MiB | 1.30 ms |
| Full-built / prepared ITU 5.1 | 30 s | 603 | 108.60 ms | 87.38 ms | 249.87 ms | 528.72 / 21.16 MiB | 0.95 ms |
| Full-built / FX6 ordinal 0 | 120 s | 2,273 | 178.39 ms | 194.72 ms | 250.00 ms | 583.61 / 103.14 MiB | 1.22 ms |

The full-built FX6 ordinal-zero EOF interval is exactly source frames
6,424,320–6,712,320, with 288,000 timestamp-authorized frames and no synthetic
priming silence. Its maximum recorded absolute observation/EOF drift is
230 ms. Decoder normalization/DRC remain disabled; the 250-ms worker admission
and clock freshness limits are unchanged.

## Retained synchronization failure

The incremental FX6 ordinal-zero run starts its EOF segment at source 133.84 s.
It becomes unavailable at native/player source 134.20 s, reporting decoded
source drift of **−260.0 ms**. The test stops promptly and exports its diagnostic
attachments; no passing summary is written. The healthy 120-second observation
alone does not qualify that rejected manifest.

The coordinator already has bounded initial catch-up before establishing clock
synchronization. Once synchronization is established, it rejects drift beyond
250 ms. The failing diagnostic is consistent with a subsequent freshness breach
near startup, but the retained data do not isolate decoder pacing, native clock
advancement or callback scheduling as its cause. The rejected segment has no completed timestamp provenance, so these records
neither establish nor exclude a PCM source-position error.

Full-built ordinal 7 subsequently completes EOF with 220-ms maximum recorded
drift, and the matched full-built ordinal-zero 120-second repeat completes EOF
with 230-ms maximum drift. Those passes do not prove that the full rebuild fixes
the earlier synchronization failure. Reliable repeated FX6 near-EOF behavior
remains an investigation item; no freshness bound or decoder option was relaxed
and no speculative production correction was made.

## App and dependency identities

A fresh Release `build-for-testing` used source head
`36ae497ac4094c9490a80a42a670fd7f2399c605` and the unchanged shipping package
resolutions. Review-only edits occurred during compilation; before/during/after
source records are retained. Meter and metadata sources were unchanged.
These are development test binaries, not clean release candidates.

The original shipping-pin profiling test app was built at
`/tmp/aagedal-live-authentic-current-dd-20260930/Build/Products/Release/Aagedal Media Player.app`.
Its executable SHA-256 is
`b6857df558cd09c8c2448979bf9108f5d3c9e2981f0ec89981e1fbd9253b05d4`.
After final profile identity checks, the root reused that original derived-data
directory to verify the completed Review edits. Its current app path therefore
does not promise the historical profiling binary. Both copied repaired apps
retain their independently identified profile binaries.
Each profile uses a separate copied app, replays the actual compiler-generated
linker invocation with candidate frameworks searched first, redirects all new
linker outputs to that copy's directory, and verifies its ad-hoc signature.
The original app and all recorded dependency inputs remain unchanged.

| Copied test app | Executable SHA-256 |
| --- | --- |
| Incremental repaired candidate | `4763ecd1ec5b87c6d86c62366f10c16811354636b9ab34948b9f29401ae98a0f` |
| Full-built repaired candidate | `6efe7fb0ab2e9c0251bb560a6de8a9a0cb12656eb0f95ff2bae68e5aaea84319` |

The full-built link map identifies objects from **all eight** freshly built
frameworks under `/tmp/aagedal-coreaudio-clean-build-v4-20260930/MPVKit/dist`:
Libmpv, Libavcodec, Libavdevice, Libavfilter, Libavformat, Libavutil,
Libswresample and Libswscale. Other auxiliary frameworks retain their pinned
original artifacts. The source meter subprocess still uses the app's normal
bundled FFmpeg 9.0.1. This gives full-built framework playback evidence without
claiming a clean rebuild of every MPVKit auxiliary dependency or a published
package repin.

After the final run, the original/candidate executables, test bundle, framework
payloads, manifests and retained linker artifacts are rehashed and unchanged.
The profile validator recomputes every requested external media hash; its 23
regression tests also pass. Text/JSON evidence, manifests and actual relink/run
scripts are in
[`evidence/live-meter-authentic-sustained-20260930`](evidence/live-meter-authentic-sustained-20260930).
Full build logs, link maps, `.xcresult` bundles, attachments and copied apps remain
under `/tmp/aagedal-live-authentic-20260930`; temporary storage is not a durable
archive.

These observations advance authentic compressed, deliberate multi-track,
qualified six-channel and sustained native production-path coverage. Trusted
numerical comparisons for these camera programmes, device switching, actual
audible output, malformed-media native behavior, VoiceOver, supported macOS,
30-minute soak and the base 2020 M1 Air/8 GB release-floor check remain open.
