# MPV decoder-raster candidate

The source-pixel gate has an opt-in native provider candidate at
[mpv-0.41.0-decoder-raster-candidate.patch](dependency-patches/mpv-0.41.0-decoder-raster-candidate.patch).
It is not included in the shipping MPVKit package. The app must remain unavailable
for MPV source-pixel inspection until a tested provider is linked and enabled.

The current development candidate uses protocol 2. The application enables it
only with `AAGEDAL_MPV_DECODER_RASTER_CANDIDATE=1`; ordinary package resolution
still links the shipping dependency. The remaining build and acceptance target
is **Apple Silicon (arm64)**. [Restore the reusable development bundle](MPV_NATIVE_RASTER_HANDOFF.md)
to continue app work and rerun retained validation without rebuilding MPVKit.

## Current protocol 2 candidate

The decoder wrapper retains the corrected-PTS source grid before user filters
or display rendering. Capture requires paused playback, an exact unambiguous
presented-frame PTS, the active video track, and no pending seek or replacement.
Duplicate, backward, or nonfinite decoder timestamps revoke the entire epoch
until reset. The scalar freshness property applies the same geometry and color
eligibility checks without copying a large image. The app reuses a verified
paused image and revokes its proof on resume or seek.

Supported geometry is square-pixel, full-raster video up to 4096 pixels on either
axis and 8,847,360 pixels total, covering UHD and DCI 4K. Exact orthogonal
container rotations and reflections are applied as byte permutations. Scale,
shear, perspective, and fractional translation in display matrices fail closed.
User rotation/aspect/FPS overrides, crop, nonempty `vf`, deinterlacing, reverse
playback, and disabled PTS correction remain unavailable.

Four cache entries have a 72 MiB per-image estimated payload ceiling and a
192 MiB aggregate estimated payload budget. Hardware references remain on the
GPU until an explicit capture downloads the matching frame. Their software
allocation estimate is checked before retention; the actual download must have
matching visible dimensions and fit the payload bound. Allocation overhead,
decoder pools, output buffers, and temporary conversion images are additional
to this cache budget. NV12 capture is deinterleaved without resampling before
RGB conversion so hardware and software use the same planar conversion path.

Protocol 2 adds `source-bit-depth`, `hardware-transfer`, `primaries`, and
`transfer`. Eight-bit SDR returns BGRA8; high-depth SDR and HDR return RGBA16.
The app accepts BT.709 with sRGB, BT.1886, gamma 2.2 or gamma 2.4 transfer, and
BT.2020 with PQ or HLG transfer. Source transfer code values remain encoded;
there is no capture tone mapping. CGImage uses the corresponding color space,
and the loupe requests high dynamic range. ICC profiles, Dolby Vision metadata,
premultiplied alpha, unsupported color combinations, and unsupported source
representations fail closed. RGB conversion and chroma reconstruction still
occur: `pixel-preserving` proves grid geometry, not byte-identical source colors.

`aagedal-decoder-raster-version=2` exposes the capability. The command returns
`protocol=2`, oriented `w`/`h`, decoder `coded-w`/`coded-h`, `stride`,
`format="bgra"` or `"rgba64"`, byte-array `data`, normalized clockwise
`rotation`, `mirrored`, finite nonnegative `pts`, `track-id`,
`pixel-preserving=true`, `presented-frame=true`, and the four color/hardware
fields above. The consumer validates every field and exact `stride × h` payload
size before copying, with a 72 MiB result ceiling. Protocol 1 remains readable
under its original smaller bounds.

Candidate hardware decoding defaults to VideoToolbox. The development-only
`AAGEDAL_MPV_DECODER_RASTER_HWDEC` accepts `no`, `videotoolbox`, or
`videotoolbox-copy` to make validation explicit. Hardware acceptance requires
both an actual hardware transfer and `hwdec-current=videotoolbox` in the native
harness; software fallback does not count.

Rebuild with `scripts/build-mpv-coreaudio-from-stage.py` and
`--decoder-raster-candidate --apple-silicon-only`. The receipt declares arm64,
checks all eight rebuilt framework slices, source identities, fresh provider
objects, and shipping feature parity. Validate against independent fixtures
with `scripts/generate-mpv-decoder-raster-extended-fixtures.py` and
`scripts/validate-mpv-decoder-raster-runtime.py --extended-fixtures ...`.
The final arm64 run passes 31 native cases, 20 hosted fixture cases inside one
XCTest, and 70 consumer/loupe tests without skips. See
[expanded Apple Silicon evidence](evidence/mpv-native-raster-expanded-20261014/README.md).
The original universal build evidence below is historical. Publication and
shipping package repinning remain separate work. Sustained memory/sanitizer
coverage and physical HDR display calibration are not established by these
bounded fixture checks.

## Historical protocol 1 implementation

The earlier October 14 integration rebuilt both macOS slices and passed nine
native cases per architecture, with x86_64 running through Rosetta. The hosted
loupe verified 512 independently numbered pixels across an accurate seek.
See [initial integration evidence](evidence/mpv-native-raster-integration-20261014/README.md).
The following sections describe that restricted implementation and its original
acceptance gates; hardware, transform and HDR restrictions there apply to
protocol 1.

### Original implementation

Apply the patch to retained mpv 0.41.0 sources (upstream revision
`41f6a645068483470267271e1d09966ca3b9f413`). Enable
`aagedal-decoder-raster=yes` before loading a fixture; the default is off, with
no retained raster references. The command `aagedal-decoder-raster` has no
arguments. It returns a node map only for paused playback with an exact,
unambiguous decoder-frame PTS match to `MPContext.video_pts`.

The decoder wrapper retains the decoder grid after PTS correction and before
image parameter assignment, user filters, output conversion, or display rendering.
When decoder PAR is unspecified, the captured copy accepts square-pixel geometry
only when this same frame's resolved default/container parameters establish a
positive 1:1 ratio. Parameter overrides are rejected at both retention and
retrieval, so an overridden frame cannot supply this geometry proof. Resolved
container rotation, pixel aspect, and crop must also be unrotated, square, and
full-raster at both boundaries.
Four slots hold software images of at most 16 MiB according to mpv's approximate
image byte-size estimator. This bounds the estimated retained image payload to
64 MiB; referenced buffer allocation overhead and pooling can add memory beyond
that estimate. Images above 4,194,304 pixels or either axis above 4096 are also
rejected. The ring may miss the presented frame when decoding runs ahead. That
case fails; the newest frame never substitutes for the presented frame.
Duplicate, backward, or nonfinite corrected decoder timestamps invalidate and
clear the entire cache until decoder reset. This remembers ambiguity after a
duplicate leaves the ring. Queued stop/replacement also revokes capture before
the old decoder is torn down.

The provider rejects active or queued seeking, incomplete restart, nonempty
`vf`, deinterlacing, video crop, hardware images, rotation, nonsquare pixel aspect,
nondefault rotation/aspect overrides, FPS override, disabled PTS correction,
and reverse playback. RGB conversion keeps both raster axes at decoder sizes;
color conversion and chroma reconstruction are still performed. The protocol's
`pixel-preserving` claim concerns source-grid geometry, not byte-exact colors.
This version handles neither orientation nor reflection. The consumer must
reject reflected container metadata, including its QuickTime correction filter.

The node fields are `protocol=1`, `w`, `h`, `coded-w`, `coded-h`, `stride`,
`format="bgra"`, `data` (byte array), `rotation=0`, `mirrored=false`, finite
nonnegative `pts`, `track-id`, `pixel-preserving=true`, and
`presented-frame=true`. Buffer ownership transfers to the result node using
mpv's normal screenshot node convention. Consumer validation must check the
whole payload and active track before/after capture.

The read-only double property `aagedal-decoder-raster-pts` reuses every capture
eligibility guard and checks the cache without RGB conversion. It is unavailable
when eligibility fails. The app checks it together with paused state and track
identity before displaying cached source-pixel proof. Seek/reset invalidates the
decoder cache. No stock screenshot command provides this protocol.

The October 3 consumer continuation enforces strict BGRA and this candidate’s
axis/pixel bounds before copying. It requires an exact `stride × h` buffer size
and bounds the copied payload to 64 MiB to allow aligned rows; this consumer
ceiling does not enlarge the provider’s 16 MiB retained-image estimator limit.
Malformed payload rejection and valid padded-row checks pass. See
[consumer receipts](evidence/clock-raster-candidate-20261003/README.md). This
validation does not establish the provider’s frame provenance or activate it.

### Original verification and engineering gates

On 2026-10-02, the patch applied successfully to the clean retained CoreAudio
candidate revision `2fdb5b54ec99fa3861b5e2bc9181724e659b5882`. Clang syntax checks
passed for `f_decoder_wrapper.c`, `command.c`, and `screenshot.c` on arm64 and
x86_64 using that build's actual compile commands and dependency headers.
The repeatable verifier is:

```sh
python3 scripts/verify-mpv-decoder-raster-candidate.py \
  /path/to/MPVKit/dist/libmpv-v0.41.0 \
  /path/to/MPVKit/dist/libmpv/macos/scratch \
  --report /tmp/decoder-raster-verification.json
```

The updated patch also compiled and linked in an isolated arm64 native libmpv
client using copies of the retained build objects. A generated lossless FFV1
fixture contains ten independently defined RGB grids, each with a unique frame
color offset. The client verified all 256 BGRA pixels exactly at PTS 0, after an
accurate seek to PTS 1, and after frame-step to PTS 1.2. It verified immediate
freshness revocation on resume and queued seek; crop, aspect override,
deinterlace, rotation override, and user filter rejection; and unavailable
responses with the option omitted or explicitly disabled. Genuine generated
container rotation (90 degrees on a square frame) and 2:1 sample-aspect fixtures
also return unavailable; the generator independently verifies their metadata.
The harness fails on any protocol, expected PTS, pixel, or freshness mismatch
and checks every API mutation. Both default decoder
queue configuration and disabled decoder queue passed this bounded fixture run.
The small ring can still evict a presented frame under other readahead workloads;
this remains an unavailable response rather than a substitute frame.

Evidence, source harness, fixture generator, source/patch/compiler/link identities,
and results are retained in
[evidence/mpv-decoder-raster-candidate-20261002](evidence/mpv-decoder-raster-candidate-20261002).
No binaries were published or added to the app package. These checks establish
this bounded arm64 native case; they do not establish x86_64 runtime behavior,
app integration, arbitrary media presentation correlation, high-depth/HDR color,
hardware transfer, transform support, or memory ownership under sustained load.
Before enabling it in an app package:

1. Rebuild the required architecture slices through the retained reconstruction workflow;
   retain source, patch, commands, linked binary identities, and corresponding
   source archives. Preserve the existing CoreAudio and shipping feature fixes.
   The October 14 local build passes this gate; publication and ordinary remote
   package resolution for the new provider remain open.
2. Run a native libmpv client against generated numbered RGB-grid frames with
   software decode. Pause and compare the returned source grid and PTS to an
   independent decoded reference. Repeat immediately after accurate and keyframe
   seeks, frame steps, track changes, and EOF.
3. Assert unavailable responses during play/seeking, for changed or duplicate
   PTS, ring eviction, hardware decode, transforms/PAR/crop, all `vf` entries,
   deinterlacing, and overrides. Check the freshness property revokes previous
   proof before a replacement is captured.
4. Profile cache opt-in versus default off, including large/high-depth inputs,
   decoder stalls, repeated load/unload and seeks. Validate retained references
   and node buffer cleanup under sanitizer instrumentation where supported.
5. Add decoder-native lossless rotation/reflection and reliable presented-frame
   association before claiming the general MPV source-pixel gate complete.

These are implementation and runtime acceptance gates, not hands-on checks that
can be marked passed merely by building the application.
