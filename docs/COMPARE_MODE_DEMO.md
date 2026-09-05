# Compare Mode release demo

The release demo should show one credible source-to-encode inspection in under
one minute. Use generated media for a repeatable rehearsal and replace it with
permission-cleared production footage for final marketing imagery when
available.

## Prepare the pair

Generate both files locally; no media is uploaded:

```bash
scripts/generate-compare-demo-fixtures.sh
```

By default the files are written below `build/Compare Mode Demo/`. Source A is
a high-detail AVC reference beginning at `01:00:00:00`. Source B is an HEVC
delivery encode made from A after trimming its first second; it begins at
`01:00:01:00`, has a shorter duration and a different audio codec, and retains
enough fine moving detail to make compression changes visible in wipe and
display-difference views. The script validates both codecs and embedded
timecodes and writes content hashes to `MANIFEST.txt`.

Pass a directory to keep a specifically named take:

```bash
scripts/generate-compare-demo-fixtures.sh "$PWD/build/Compare Mode Demo Take 1"
```

The script refuses to overwrite an existing pair. Set `FFMPEG` and `FFPROBE`
when the full installations are not first on `PATH`.

## Recording setup

- Use a clean Release build and a 16:9 window large enough that the toolbar,
  A/B labels, alignment label, mismatch summary, timeline offset, and overlap
  interval are legible.
- Disable notifications, hide unrelated desktop content and filenames, and
  preselect a disposable export directory.
- Keep scopes and the review popover closed at the start so the comparison is
  the visual focus. Keep Source A as the only audible source.
- Rehearse cursor positions and menu choices. Record at native display scale
  and avoid zooming or editing that could suggest frame lock the app did not
  provide.
- Clear the first-run callout before the final take unless the callout itself
  is the subject of a separate onboarding clip.

## 45–60 second shot list

1. **Source (0–5 s):** Open `Source A - reference.mov`, play briefly, then
   pause after its first second. Establish the reference image and source
   timecode.
2. **Automatic alignment (5–12 s):** Add
   `Source B - delivery encode.mov`. Hold on the A/B filenames, Source Timecode
   alignment, signed offset, partial overlap, and codec/audio/duration mismatch
   summary. Do not manually seek B.
3. **Shared transport and A/B (12–20 s):** Play both sources, pause on fine
   detail, and press `B` twice to show instant A/B switching on the aligned
   frame.
4. **Wipe (20–32 s):** Select Vertical Wipe and drag through the detailed
   region. Briefly select Horizontal Wipe or move it with `[` and `]` so both
   interactions are represented without rebuilding a decoder.
5. **Difference (32–44 s):** Select Display Difference and raise gain until
   compression differences are clear. Keep the `display-space` label visible;
   do not describe this view as PSNR, SSIM, VMAF, or objective pixel analysis.
6. **Evidence export (44–55 s):** Return to a useful comparison view and press
   Command-S. End on the exported annotated side-by-side still with filenames,
   source timecode, alignment, inspection view, and technical context visible.
   The inspection-view annotation records the selected mode; the exported
   picture layout remains A | B, including when inspecting a wipe or difference.

The implemented display-space loupe has separate acceptance gates and is not
part of this Compare Mode release-demo gate. Its A/B captures are independent,
not frame-locked.

## Take acceptance

- The content visible in A and B represents the same source frame after the
  automatic one-second source-timecode mapping.
- Only A is audible, playback controls both sources, and neither decoder shows
  a loading transition while switching visual modes.
- Wipe movement is continuous and display difference is visibly useful without
  clipping the whole frame.
- The capture shows the display-space qualification and never implies an
  objective image-quality score.
- The exported still is readable at the final delivery resolution and contains
  no private file paths or unrelated user data.
- Final captions use the release promise from
  `COMPARE_MODE_IMPLEMENTATION_PLAN.md` and identify the files as a reference
  and delivery encode rather than two unrelated masters.
