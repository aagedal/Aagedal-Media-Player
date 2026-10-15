# Native MPV scope acceptance — 2026-10-15

The arm64 candidate computes waveform, RGBY parade and vectorscope from the
current VO input frame inside libmpv, returning only diagnostic images to Swift.
It bypasses the renderer screenshot pipeline and preserves source HDR transfer
values. See [the implementation and restore guide](../../MPV_NATIVE_SCOPES.md).

This run used macOS 27.0.1 on Apple Silicon. The app and new libmpv archive are
arm64 only. Shipping dependency pins and the native-raster default-off gate are
unchanged. This is a local candidate; there is no new public MPVKit release.

## Results

- 38 hosted scope/consumer tests pass, zero failures and zero skips. They include
  malformed/duplicate/oversized native payload rejection, SDR/PQ/HLG native
  capture, both waveform modes, vectorscope publication, display-space capture
  fallback and return to native analysis, and stop/in-flight completion handling.
- The retained native-raster hosted XCTest separately passes all 20 fixture cases
  with `MPV_EXTENDED_NATIVE_APP_ACCEPTANCE: 20 cases`. This uses the new libmpv
  binary, with actual VideoToolbox hardware cases, seek freshness, cached-image
  reuse and resume revocation. It does not reuse an old prelinked client as proof
  of the new dependency.
- Five independent lossless RGB16 signal cases pass: SDR color bars, PQ neutral
  ramp, HLG neutral ramp, PQ color bars, HLG color bars. A Python reference computes
  expected waveform, parade and vectorscope positions without calling the C
  implementation. All expected and actual occupied bins must match within one
  pixel for float/conversion boundary rounding; missing/extra traces fail.
- The portable C math passes 120 transfer/orientation/resolution combinations
  under AddressSanitizer and UndefinedBehaviorSanitizer. Known ST 2084 100/1000/
  10000-nit anchors and HLG peak are asserted. This instruments the new math,
  not all of mpv, FFmpeg, Metal or the provider command lifecycle.
- Six UHD 60 fps native runs pass: SDR, PQ and HLG with software and actual
  VideoToolbox decode. Each validates result sizes, frame metadata, fresh PTS
  during play, accurate seek, stop rejection and invalid-width rejection. First
  paused-frame diagnostic images are byte-identical between hardware and
  software for all nine plot comparisons in these three workloads.
- Nine portable-builder tests pass, including source retention and rejection of
  repeated scope-patch application. The newly packaged delta restores with both
  baseline and delta inventory verification. The restored native client runs
  successfully at a new path. The copied app passes codesign verification and
  contains an arm64 main executable.

## Performance

At analysis width 720, output waveform/parade are 720×405 and vector is 405×405.
The six native GPU-client runs interleave 30 native analysis calls with ordinary
`screenshot-raw video` calls on moving 3840×2160, 60 fps sources. Means in ms:

- SDR software: native all-three-plots **4.90**, screenshot-only **33.17**.
- SDR VideoToolbox: native **6.35**, screenshot-only **33.51**.
- PQ software: native **10.27**, screenshot-only **30.80**.
- PQ VideoToolbox: native **11.70**, screenshot-only **29.74**.
- HLG software: native **9.72**, screenshot-only **31.25**.
- HLG VideoToolbox: native **11.17**, screenshot-only **29.32**.

Screenshot-only timing excludes the app's later downsampling and CPU scope
computation. These numbers are not an end-to-end speedup ratio. Calls alternate
native first, screenshot second; no long-duration or concurrent-viewer claim is
made. The renderer and VideoToolbox were real, not software fallbacks.

The separate hosted app comparison measures capture plus waveform/vectorscope
publication on the UHD HLG workload, with scope update target 30 fps. Over each
three-second measured interval after warmup:

- Screenshot backend: **60** renders / 3.0034 s = **19.98 fps**, 60 distinct PTS.
- Native backend: **88** renders / 3.0000 s = **29.33 fps**, 88 distinct PTS.

No backend substitution occurs during either measurement. The native test
requires >20 fps and at least 90% of baseline throughput. These are scope update
rates; they do not certify 60 fps playback presentation cadence or frame lock.
The provider releases mpv's core lock for hardware download/analysis and uses a
spawned command; the app allows one request per capture generation.

## Evidence and limits

`candidate-receipt.json` binds the libmpv archive, provider source hashes,
baseline build receipt and exact retained compiler commands.
`source-identities.json` binds the app and provider source used in this run.
`hosted-summary.json`, `raster-regression-summary.json`, compressed build/test
logs, signal/GPU JSON results, sanitizer log, and builder-test log are retained
beside this document. The development delta descriptor is
[mpv-scopes-handoff.json](../../mpv-scopes-handoff.json).

The candidate uses native CPU scope computation with shared sampling and an
EOTF table. It still downloads VideoToolbox frames; GPU histograms are future
work. Analysis is sampled to the configured resolution. HLG assumes 1000-nit
peak and fixed 1.2 system gamma. A/B difference and AVPlayer scopes retain their
previous capture/color contracts. Unsupported colors fall back to capture.
Long-duration memory/thermal load, multiple simultaneous UHD viewers, physical
HDR calibration, general interlaced/filter workloads and 8K performance remain
unqualified. The reusable baseline's older acceptance receipts do not establish
these new scope results; the new evidence above does.
