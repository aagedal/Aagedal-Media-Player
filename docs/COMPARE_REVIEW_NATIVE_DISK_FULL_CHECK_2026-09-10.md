# Native APFS review save recovery — 2026-09-10

## Scope

The Release app built from `ad0da1f`, at
`/tmp/aagedal-player-utf32-derived-20260910/Build/Products/Release/Aagedal Media Player.app`,
was exercised on macOS 27.0 (26A428) using a disposable 128 MiB APFS disk image.
This extends the existing production-store APFS/HFS+ XCTest evidence with actual
native review interaction. No user media or host volume was filled.

`scripts/native-review-disk-full.py` creates two five-second, 25 fps, 320×180
H.264 MOV files and one point finding at A/B frame 25. Both sources opened via
the app's native file pickers; the review loaded exactly one original finding.
The UI showed the ordinary MPV comparison path paused at frame zero. Native
interaction used keyboard text/file selection and accessibility actions.

## Observed edit recovery

1. The harness filled only its attested APFS volume until a write returned
   `ENOSPC`. Original sidecar and media SHA-256 hashes remained unchanged.
2. Keyboard traversal selected the existing note. Pasting `Recovered native edit `
   repeated 768 times and pressing Tab committed the draft. The popover showed:
   “Could not save comparison notes” and a system error identifying the sidecar,
   the `AagedalNativeDiskFull` volume, and lack of space. **Retry Save** was exposed
   in the accessibility tree as **Retry saving review notes**.
3. Escape dismissed the popover. Reopening retained both the pending edit and
   out-of-space error. A native window zoom from 540 to 1728 points allowed a
   screenshot to show the complete wrapped error and Retry Save action. The
   narrow-window screenshot cropped the popover at the parent-window boundary;
   this is not a narrow-layout acceptance claim.
4. Retry while the volume remained full retained the error. Independent reads
   still matched the complete original sidecar and both original media hashes.
5. After the harness truncated and synchronized its owned filler, Retry Save
   cleared the error. Independent verification found exactly the intended edit
   after the app's surrounding-whitespace trimming. The note's identity, frame
   anchors, rational rates, classifications, creation date, source identities,
   and all other document fields were preserved. Only text and update time were
   allowed to change; UUID letter case was normalized for comparison.

## Observed deletion recovery

The harness retained the recovered sidecar outside the volume and pinned its
complete SHA-256 hash, then refilled the same APFS image to actual ENOSPC.
Deleting the finding changed the displayed count to zero. Reopening Review
showed **No Review Notes**, the same out-of-space error, and Retry Save; a native
screenshot confirmed the complete error and action. The saved sidecar still
matched the recovered checkpoint byte for byte, and the two movies were unchanged.

After releasing the filler, Retry Save cleared the error and persisted the empty
note list. Verification required unchanged source identities/schema and media
hashes, no extra files in the media directory, and exactly the intended deletion.
The app's test window closed, and the harness successfully detached and removed
the disk image. Original, recovered, and deleted sidecar copies plus the state
and phase log remain outside the image for inspection.

## Reproduction and safeguards

Run the harness help for the full sequence:

```bash
python3 scripts/native-review-disk-full.py --help
python3 scripts/native-review-disk-full.py setup
```

Use the exact canonical root printed by setup for later commands. Open
`ROOT/mount/media/source-a.mov`, compare `source-b.mov`, then run `fill ROOT`.
Paste `ROOT/pending-edit.txt` into the existing note and leave the field to save.
Observe the native failure, run `verify ROOT`, release space with `release ROOT`,
and invoke Retry Save in the app. `verify ROOT --recovered` requires the intended
edit and preserved original fields. To repeat deletion, run `checkpoint ROOT`,
then `fill ROOT --recovered`. Delete the note in the app and observe the failure.
`verify ROOT --recovered` must still match the exact checkpoint bytes. Run
`release ROOT`, invoke Retry Save, then `verify ROOT --deleted`. Close the test
media before `cleanup ROOT`.

Every volume operation checks the owned canonical `/private/tmp` root, image
association, APFS mount, device/volume UUID, capacity, and ownership token. The
filler descriptor additionally checks its retained filesystem device, owner,
regular-file type, link count, and bounded filesystem capacity before writing
or truncating. The writer stops at a fixed cap if actual ENOSPC is not reached.
No symlink filler is followed. The script refuses optimized Python execution,
which would disable its safety assertions. Native failure observation is still
required; filler ENOSPC alone does not prove a failed app save.

The native fixture root was `/private/tmp/aagedal-native-disk-full.et_jfe0a`.
Host-side state, original sidecar, pending text and phase log retain reproducible
byte evidence outside the exhausted volume. Temporary evidence may be removed;
the committed harness and this procedure allow a fresh run. No screenshot or
accessibility-tree observation substitutes for spoken VoiceOver or complete
Full Keyboard Access acceptance. Other filesystems, hardware and broader save,
copy/relink/migration interaction remain separate checks.

## Verification

All 17 focused harness tests pass, covering rejected host/different-device
descriptors, capacity/owner/type/link/root guards, and recovery/deletion proof
that rejects unintended document changes. Two agents reviewed the safeguards
and proof; their findings were corrected before native acceptance. These tests
do not mount/fill a filesystem; the observed native run supplies that evidence.
Release preflight passes all 61 checks. Signature inspection required execution
outside the sandbox; the sandboxed check could not verify the signing identity.
No app implementation changed, so the existing 528-test integrated Release
baseline remains applicable and was not rerun for these scripts/docs.

Preflight log: `/tmp/aagedal-native-acceptance-preflight-20260910.log`.
