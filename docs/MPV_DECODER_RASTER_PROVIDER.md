# MPV decoder-raster candidate

The source-pixel gate has an opt-in native provider candidate at
[mpv-0.41.0-decoder-raster-candidate.patch](dependency-patches/mpv-0.41.0-decoder-raster-candidate.patch).
It is not included in the shipping MPVKit package. The app must remain unavailable
for MPV source-pixel inspection until a tested provider is linked and enabled.

## Supported first implementation

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

## Verification and remaining engineering

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

1. Rebuild both architecture slices through the retained reconstruction workflow;
   retain source, patch, commands, linked binary identities, and corresponding
   source archives. Preserve the existing CoreAudio and shipping feature fixes.
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
