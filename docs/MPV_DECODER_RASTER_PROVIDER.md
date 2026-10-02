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

The decoder wrapper retains references after PTS correction and before image
parameter overrides, user filters, output conversion, or display rendering.
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

This establishes patch applicability and C syntax only. It does not establish
linked command availability, raster accuracy, presentation correlation, memory
ownership under load, or runtime safety. Before enabling it in an app package:

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
