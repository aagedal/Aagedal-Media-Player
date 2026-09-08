# Bounded WAVE metadata

`WaveMetadataReader` supplies technical audio metadata for local little-endian
RIFF, RF64, and BW64 files containing PCM integer or IEEE floating-point audio.
It supports the corresponding WAVEFORMATEXTENSIBLE subformats and reports
explicit, recognized speaker masks without inferring surround placement from
channel count. Duration comes from complete sample frames in the data chunk.

RF64 and BW64 require a first `ds64` chunk. The reader resolves sentinel
`0xffffffff` lengths through its 64-bit container/data sizes and optional chunk
table. Ordinary 32-bit lengths remain authoritative. Repeated table IDs resolve
in occurrence order, including when ordinary chunks with that ID intervene.
Each payload and its alignment padding must fit the declared container and the
physical file; malformed, duplicate format/data/ds64 headers are rejected.

The reader seeks past audio and unrecognized ancillary payloads, reads at most 40 bytes of
the format header, and reads each 12-byte table entry separately. A maximum of
4,096 table entries bounds retained metadata; larger valid tables report an
unsupported format. Chunk and table loops check task cancellation. Header size
arithmetic is checked before addition, including 64-bit sentinel replacements.

RF64 sample counts must agree with the data's sample-frame count when nonzero;
zero means unspecified. An ordinary `fact` count takes precedence over `ds64`;
a sentinel `fact` count, or an omitted `fact` chunk, uses `ds64`. The reader
retains only the four-byte `fact` prefix and rejects truncated or duplicate
RF64 `fact` chunks. BW64 reserves the corresponding eight `ds64` bytes, so they
are ignored. This distinction follows [EBU Tech 3306 (RF64)](https://tech.ebu.ch/files/live/sites/tech/files/shared/tech/tech3306v1_0.pdf)
and [ITU-R BS.2088 (BW64)](https://www.itu.int/rec/R-REC-BS.2088).

## Broadcast WAVE tags

An optional `broadcastWave` object now carries `bext` metadata into the inspector
and its JSON export. Versions 0–2 expose description, originator/reference,
origination date/time, the exact unsigned 64-bit sample reference, and coding
history. Dates and times remain producer-supplied text without timezone or
calendar interpretation; the sample reference is not converted into a video
frame timecode. Versions 1–2 additionally expose nonzero UMID bytes as uppercase
hexadecimal, without validating or interpreting the identifier. Version 2
includes embedded loudness values, with signed hundredths converted to the
appropriate units. Unspecified and out-of-range loudness fields are omitted.
The inspector labels these as producer-supplied values, separately from its
own audio analysis. These fields follow [EBU Tech 3285 v2, sections 2.3–2.4](https://tech.ebu.ch/docs/tech/tech3285.pdf).

Only 602 fixed bytes and at most 16 KiB of coding history are read per file;
excess history is skipped and explicitly marked truncated in the model, JSON,
and inspector. Text ends at the first NUL; invalid ASCII/control bytes omit
that field. Unknown versions retain only common fields. Truncated fixed
headers and duplicate `bext` chunks are rejected. No BWF conformance claim is
made. Tests cover version gates, text and loudness validity, JSON round trips,
64-bit references, RF64/BW64 table resolution, chunk ordering, malformed chunks,
and sparse 1 GiB coding history. Focused native acceptance is recorded below.

Focused tests cover ordinary RIFF regressions, bundled-FFmpeg RF64 output through
`MetadataService`, both extended containers and integer/float formats, explicit
speaker masks, inconsistent RF64 sample counts and `fact` precedence, the BW64 reserved field,
repeated table IDs, malformed/truncated/overflowing lengths, and the table cap.
Sparse fixtures exercise 8 GiB audio and an odd ancillary chunk exceeding
4 GiB without allocating or reading their payloads.

Remaining exclusions: compressed WAVE encodings, big-endian RIFX, multiple data
chunks and `wavl` playlists, INFO/XML/ADM tag extraction or interpretation,
and tables above the documented cap. Container recognition does not validate
ADM semantics or guarantee that every decoder can play a file.

## Native acceptance

The ordinary RIFF inspector path and the RF64/BW64 extension require a rebuilt
app. Synthetic rear-speaker fixtures use eight seconds of Float32 conventional
7.1 at 48 kHz, with a 0.1-amplitude 1 kHz sine on Back Left. Expected metadata
is eight channels, 32 bits, 48 kHz, 7.1, and eight seconds. Whole-file analysis
should report approximately −23.0 LUFS, 0.0 LU, and −20.0 dBTP with the rear
weighting correction. These fixtures test container integration; independent
numerical-reference coverage is described in `AUDIO_LOUDNESS.md`.

On 2026-09-08 the rebuilt Release app passed this check for ordinary RIFF,
FFmpeg-generated RF64, and a BW64 copy with its reserved ds64 field zeroed.
Each opened through the native file picker, showed eight seconds, PCM_F32LE,
eight channels (7.1), 48 kHz and 32 bits, then measured −23.0 LUFS / 0.0 LU /
−20.0 dBTP. The pre/post-measurement rear-correction explanation remained in
the accessibility tree. This closes the prior ordinary-WAVE inspector check.
Playback was paused; audible monitoring, Full Keyboard Access and spoken
VoiceOver are separate. Sparse >4 GiB files are covered by automated header
checks, not native playback of multi-gigabyte recordings.

The Broadcast WAVE continuation opened a synthetic version-2 `bext` fixture
through the rebuilt Release app's file picker and Command-I inspector. The
native tree retained the expected description, recorder identity, date/time,
exact `2174400000` sample reference, UMID and coding history. Scrolling showed
separate **Broadcast WAVE** and **Embedded BWF Loudness** sections with
−23.45 LUFS, 4.56 LU, −1.23 dBTP, −20.00 and −21.00 LUFS and the producer-value
explanation. The recording still reported eight seconds, 7.1, 48 kHz and 32 bits.
Long tag values use the inspector's existing single-line display; complete
values remain in the accessibility tree and JSON. This check used native
accessibility actions and screenshots, not spoken VoiceOver or live meters.
Fixture: `/tmp/aagedal-native-bwf-20260908.wav`. All 453 Release tests,
static analysis and 61 release-preflight checks pass for this continuation.
