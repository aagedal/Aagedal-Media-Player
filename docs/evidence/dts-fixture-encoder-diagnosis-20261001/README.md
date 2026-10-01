# DTS fixture encoder crash diagnosis — 2026-10-01

The canonical Release suite's
`LiveAudioMeterDecoderTests/testBundledDecoderPreservesContiguousDTSInMillisecondMatroskaContainer`
failed during synthetic fixture creation, before production live decoding.
The xcresult reports `FFmpegService.swift:131`, `processFailed("")`.
The matching crash report identifies child PID 83308, parent XCTest runner
PID 83265, `enc0:0:dca`, SIGBUS 10, EXC_BAD_ACCESS, and binary image offset
7,051,916. The original full crash report is retained locally under
`/private/tmp/aagedal-dts-encoder-crash-diagnosis-20261001`; the checked-in
`crash-summary.json` retains diagnostic identity without the full system report.

Direct, sequential fixture encoding reproduces the same SIGBUS, empty stderr,
DCA encoder thread, and image offset. `trials.json` retains all 500 bounded
trials: ordinary CPU flags passed 247/250, while `-cpuflags 0` passed 249/250.
Disabling SIMD does **not** resolve the defect and was not applied to either
the fixture or production decoder. No automatic retry or skip is added.

The test now uses pinned successfully generated DTS/Matroska bytes. Its
production decoder call and all existing source-frame, timestamp, channel,
synthetic-silence and EOF assertions remain unchanged. Missing or altered
fixture data fails; the test also checks the whole-file SHA-256.
`fixture-generation-command.json` records the exact successful generation
arguments and exit status; `fixture-receipt.json` pins FFmpeg, signal source
and output hashes. The wholly synthetic signal contains no external media.

The bundled experimental DCA encoder defect remains open. This is a
decoder-regression setup correction, not an encoder fix, authentic DTS-HD MA
qualification, numerical accuracy result or native/hardware acceptance.
The root agent records subsequent XCTest validation in the continuation receipt.
