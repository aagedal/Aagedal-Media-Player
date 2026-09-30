# Clean eight-hour production programme profile — 2026-09-30

The corrected split-mono production analyzer passes all six workloads on a
new eight-hour, eight-mono-track ALAC fixture: whole-file, first 30 seconds and
last 30 seconds for Stereo and 5.1. The actual Release service, bundled FFmpeg,
metadata loading and selected-role mapping run through the existing opt-in
profiler at clean implementation commit
`f5411b154dd6065a4901132a487b27ccf6d51058`.

Every Stereo scope returns −18.1 LUFS; every 5.1 scope returns −13.4 LUFS.
Every result has 0.0 LU range and −18.1 dBTP. The explicit
[tone consistency check](tone-consistency-validation.json) compares all six
results with these previously established repeated-tone expectations. The
historical late-range −21.1 LUFS defect does not recur. This is consistency
evidence, not a new published calibration or an independent measurement of
every speaker's contribution.

| Layout | Scope | Wall time | Parent initial RSS | Parent sampled peak RSS | Children sampled peak RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| Stereo | whole | 96.297 s | 224.47 MiB | 253.34 MiB | 226.53 MiB |
| Stereo | early | 0.255 s | 155.31 MiB | 155.31 MiB | 78.31 MiB |
| Stereo | late | 8.666 s | 155.33 MiB | 155.33 MiB | 226.03 MiB |
| 5.1 | whole | 296.996 s | 155.34 MiB | 172.36 MiB | 612.92 MiB |
| 5.1 | early | 0.723 s | 172.67 MiB | 172.67 MiB | 169.22 MiB |
| 5.1 | late | 23.257 s | 172.70 MiB | 172.70 MiB | 610.42 MiB |

The measured interval is 22:46:13–22:53:22 Europe/Oslo, with no sleep/wake
interruption. The host is an 18-core Apple M5 Pro with 64 GB RAM, macOS 27.0.1
(26A434) and Xcode 27.0. No concurrent app build/test or computer-use interaction
runs during measurement. One actual XCTest passes with no skips or runtime
warnings. The structural validator, power gate and final package-cache validation
all pass.

## Input and provenance

The generated file is 4,652,793,673 bytes, with all eight mono 48 kHz ALAC tracks
exactly 28,800 seconds long. Its SHA-256 is independently unchanged before and
after the profile:
`da22385a1c31bfa3cba2d7fdc73c7fd61ad2c1ef2eecedc5c18348ac6ad2ac5c`.
It follows the documented ten-second seed/stream-copy loop recipe with
`-t 28800`. It is newly generated and differs in file hash from the historical
September 12 fixture; no byte identity with that earlier input is claimed.

[Input/source/product identities](source-input-and-product-identity.json),
[ffprobe inspection](input-probe.json), [measurements](summary.json), native
XCTest exports, compressed build/test logs and power endpoints/events retain
the observation. The profiler runs normal build-for-testing against the same
clean source clone and canonical DerivedData. Its default package-cache location
is linked to the already validated exact external cache; no database or app is
copied. The clone and pinned cache remain clean/unchanged afterward. Product
hashes are observed after the completed profile.

The external full result bundle and app are retained under
`/private/tmp/aagedal-programme-eight-hour-production-20260930` and the canonical
verification DerivedData. The generated input remains under
`/private/tmp/aagedal-programme-eight-hour-20260930`. Temporary storage is not a
durable archive.

## What this closes and what remains

This closes the named clean eight-hour production-service rerun left open by
the sleep-interrupted September 12 diagnostic and its independent graph check.
It confirms usable consistent whole/early/late measurements with the corrected
independent-input graph on a large packet-count fixture.

The 5.1 child sampled peak is about 613 MiB, much greater than its early-range
169 MiB. Container indexes still scale with duration; constant memory is not
claimed. RSS is sampled every 20 ms after metadata loading, with parent and
summed direct children measured separately. Short peaks/grandchildren and earlier
metadata peaks can be missed. This is a single observation, not a controlled
comparison with the older host/toolchain run.

Producer-authentic programme codecs/content, role-specific long-file references,
base-M1/8-GB release-floor hardware, concurrent playback/cancellation, energy,
elapsed-time soaks and native accessibility remain separate acceptance work.
