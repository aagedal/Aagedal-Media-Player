# Bounded WAVE metadata

## Native iXML check — 2026-09-09

The rebuilt Release app opened the disposable two-second PCM16 stereo 48 kHz
fixture `/tmp/aagedal-native-ixml-20260909.wav`. Command-I exposed separate
Broadcast WAVE and iXML Recording sections. Native scrolling and screenshots
confirmed `Fjell & sjø`, scene `021A`, take `0003`, sound roll `Roll 7`, the note
`Location dialogue; quiet take.`, circled take `Yes`, and UID `recorder-0003`.
The BWF description stayed `Field recording` and its time reference remained
`2174400000 samples since midnight`. The accessibility tree retained all
labels/values. Playback stayed paused and the waveform/technical metadata
identified stereo PCM16 at 48 kHz. This is focused synthetic native acceptance;
producer-authentic recorder fixtures, Full Keyboard Access and spoken VoiceOver
remain separate. The complete Release suite passes all 479 tests with no
failures or skips, including all 41 WAVE reader tests.

## Supported containers

`WaveMetadataReader` supplies technical audio metadata for local little-endian
RIFF, RF64, and BW64 files, plus big-endian RIFX, containing PCM integer or
IEEE floating-point audio. For the little-endian containers it also supports
the corresponding WAVEFORMATEXTENSIBLE subformats and reports
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

## Big-endian RIFX

RIFX uses big-endian container lengths, chunk lengths and base format fields,
while keeping chunk identifiers in their original character order, as defined
by [Microsoft/IBM Multimedia Programming Interface and Data Specifications 1.0,
chapter 2](https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/Docs/riffmci.pdf).
Classic PCM integer (8/16/24/32/64-bit) and IEEE float (32/64-bit) metadata use
the same frame-alignment and byte-rate validation as RIFF. Multibyte codecs
report `be`; unsigned 8-bit PCM remains `pcm_u8`. Mono and stereo are identified
from channel count; surround placement remains unknown without a supported
explicit mask.

RIFX WAVEFORMATEXTENSIBLE, Broadcast WAVE and iXML tag interpretation remain outside
this implementation: extensible format tags report unsupported encoding, and
`bext` and `iXML` payloads are skipped without populating their metadata objects. Chunk bounds
are still validated. RIFX uses ordinary 32-bit lengths and never applies RF64
`ds64` sentinel rules. Tests cover the metadata-service path, PCM/float widths,
data before format, odd payload padding, mixed-endian/malformed fields,
duplicate chunks and a sparse 1 GiB audio payload followed by an ancillary
chunk. All 30 `WaveMetadataReaderTests` passed in the Release test host on
2026-09-08, including six RIFX cases. Native playback and producer-authentic
RIFX fixtures remain separate acceptance work.

A decoder spot check on 2026-09-08 found that the bundled FFmpeg labels a
classic RIFX 16-bit stereo fixture `pcm_s16le` and emits its big-endian sample
bytes unchanged when asked for `s16le` output. Input bytes `12 34 FE DC` should
become `34 12 DC FE`, but remained `12 34 FE DC`. Fixture:
`/tmp/aagedal-rifx-s16be-20260908.wav`. `RIFXAudioDecoding` now detects the
container signature, validates the metadata, and inserts the matching
`-c:a pcm_*be` input decoder before `-i` for production loudness analysis and
waveforms. Unsigned 8-bit uses `pcm_u8`. Invalid/unsupported RIFX headers fail
instead of falling back to FFmpeg's incorrect codec guess. Regression tests
decode known positive/negative samples at every supported PCM/float width,
measure independently generated −23 dBFS stereo tones, and inspect actual
waveform amplitudes.

Playback and trim export currently report an actionable unsupported-format
error directing users to convert to little-endian WAVE with a RIFX-capable
converter. The guard checks the header even when metadata is unavailable.
FFmpeg stream copy otherwise writes big-endian sample bytes under a
little-endian codec tag. [mpv's audio decoder preference](https://mpv.io/manual/stable/#options-ad)
selects a decoder matching the demuxed codec; it does not provide the same
input-codec override. An upstream demuxer fix or a separately verified playback
conversion path is still required before removing this guard.

## Broadcast WAVE tags

For RIFF/RF64/BW64, an optional `broadcastWave` object carries `bext` metadata
into the inspector and its JSON export. Versions 0–2 expose description, originator/reference,
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

## iXML recording labels

RIFF/RF64/BW64 files can also expose an optional `ixmlRecording` object in the
model and inspector JSON, with a separate **iXML Recording** inspector section.
The reader accepts UTF-8 XML, including a UTF-8 BOM and an optional XML
declaration, with one unnamespaced `BWFXML` root. It reads only direct scalar
children `IXML_VERSION`, `PROJECT`, `SCENE`, `TAKE`, `TAPE`, `NOTE`, `CIRCLED`
and `FILE_UID`. These fields follow the [iXML object descriptions](https://www.gallery.co.uk/ixml/object_Details.html)
and [published examples](https://www.gallery.co.uk/ixml/iXML_Example.html).
Take and scene labels remain strings, preserving leading zeroes. `CIRCLED`
is populated only for explicit `TRUE` or `FALSE`; absence or unrecognized text
does not invent a default. XML escapes and CDATA are decoded, surrounding
whitespace is trimmed, and blank or control-bearing fields are omitted.

The entire chunk must fit within 256 KiB before any payload is read. A larger
payload is skipped by seeking, with no partial XML parsing. Parsing is limited
to 16 element levels and 4,096 elements, including ignored vendor objects.
Each scalar field is limited to 4 KiB of decoded UTF-8, except `NOTE`, which
allows 16 KiB; an oversized field is omitted whole. A field containing nested
markup is also omitted. Each callback that consumes text or starts an element
checks cancellation; the caller propagates cancellation after parsing.

DTD/entity declarations are rejected before parsing; external-entity resolution
is disabled and its policy is `never`. This conservative preflight also rejects
declaration markers inside comments or CDATA. NUL bytes, non-UTF-8 data,
conflicting encoding declarations, malformed XML, duplicate recognized scalar
tags, excessive depth/element counts and duplicate `iXML` chunks omit the
recording object while retaining valid technical audio and `bext` metadata.
Duplicate chunks never cause another XML parse. Invalid RIFF chunk lengths
and padding still reject the file. Ordinary XML whitespace after the root is
accepted, including the space padding described by the [iXML chunk specification](https://www.gallery.co.uk/ixml/iXML_chunk.html).

Nested `BEXT`, `SPEED`, `TRACK_LIST` and vendor-specific objects are ignored.
iXML never overrides `bext` values, channel layout, sample rate, duration,
timecode or measured loudness. No track routing, timing, ADM or conformance
interpretation is attempted. RIFX iXML and other Unicode encodings remain
unsupported. Tests cover recording values and Unicode, model/JSON/service
integration, RF64/BW64 sizes, chunks after audio, namespace and nesting scope,
malformed/hostile XML, duplicate chunks, field/depth/element/payload bounds,
and a sparse 1 GiB skipped XML payload. Producer-authentic recorder fixtures
and native inspector acceptance remain follow-up work.

Focused tests cover ordinary RIFF regressions, bundled-FFmpeg RF64 output through
`MetadataService`, both extended containers and integer/float formats, explicit
speaker masks, inconsistent RF64 sample counts and `fact` precedence, the BW64 reserved field,
repeated table IDs, malformed/truncated/overflowing lengths, and the table cap.
Sparse fixtures exercise 8 GiB audio and an odd ancillary chunk exceeding
4 GiB without allocating or reading their payloads.

Remaining exclusions: compressed WAVE encodings, RIFX extensible formats and
RIFX Broadcast WAVE tags, multiple data chunks and `wavl` playlists,
INFO/other XML/ADM tag extraction or interpretation, iXML fields beyond the
recording labels documented above,
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
