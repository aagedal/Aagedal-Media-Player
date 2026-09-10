# Comparison review sidecar format

Schema version 2 stores text findings, severity, category, status, and optional
inclusive source-A frame ranges for an ordered source A/B pair in local JSON.
Source media is never written. PDF images are generated at export time; this
format contains no image attachments or alignment setting. CSV/PDF and editor-marker exports are
separate representations, not sidecars. Editor acceptance is tracked in
[marker interchange validation](COMPARE_MODE_INTERCHANGE.md).

## Finding and navigating notes

Use **Filter review notes** in the Review popover to search note text and classification labels without
changing the saved review. Matching ignores case and diacritics and trims
surrounding search whitespace. The note count shows matches out of the total,
and orange timeline markers show the same matches. Range findings also show
an orange band spanning their inclusive A frame range. Clear the filter to restore
the complete list. Changing the source pair or closing the comparison clears
the filter; reopening the popover in the same session retains it.

The previous/next buttons seek both sources to the nearest matching marked
frame before/after the current position using the current comparison alignment.
These actions are also in the timeline context menu. They skip duplicate notes
on the current frame and stop at either end rather than wrapping. Each row's
timecode remains a direct seek action. Exports always include **all notes**,
including those hidden by the filter.

Expand a review row to choose severity, category, or status. To make a range,
enter an inclusive A end frame and choose **Apply**, or set the end to the
current A frame. The end must be at or after the note's start. Row actions can
seek to the end or clear it to restore a single-frame finding. Classification
and range edits are saved with the note and update its edit timestamp.

For an uncluttered timeline, turn off **Show Timeline Details** in Settings →
General → Playback or the timeline context menu. Chapter/review markers and
comparison overlap are hidden; the playhead and active trim points remain.
This preference is saved across launches and does not delete review data or
disable note navigation.

## Location and naming

The app discovers the sidecar beside source A, using:

`<A stem> vs <B stem>-<B path hash>.aagedal-compare.json`

Each filename stem excludes the media extension, replaces `:` with `-`, trims
surrounding whitespace/newlines, falls back to `Untitled` when empty, and keeps
its first 60 characters. The suffix is the lowercase hexadecimal 64-bit FNV-1a
hash of B's standardized, symlink-resolved absolute path encoded as UTF-8
(offset basis `14695981039346656037`, prime `1099511628211`, wrapping arithmetic).
The hash is a naming discriminator, not a content checksum or privacy boundary.
Swapping A/B changes the pair. Naming collisions are guarded by the identities
inside the document rather than silently accepted.

A missing sidecar starts an empty review; the first edit creates the file.
The source A folder must be writable to save notes. The Review popover displays
the sidecar filename and reports load/save errors.

## JSON fields

The document is UTF-8 JSON. The writer pretty-prints and sorts object keys.
Dates are JSON numbers in **milliseconds since the Unix epoch**, not ISO 8601
strings or seconds; fractional milliseconds are supported for note dates.

| Top-level field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | Integer | Required; `1` and `2` load, all new writes use `2`. |
| `primarySource` | Source identity object | Required; source A. |
| `secondarySource` | Source identity object | Required; source B. |
| `notes` | Array of note objects | Required; may be empty. |

Each source identity has these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `canonicalPath` | String | Required standardized, symlink-resolved absolute path. |
| `fileSystemNumber` | Unsigned 64-bit integer, optional | Filesystem device identifier from file attributes. |
| `fileNumber` | Unsigned 64-bit integer, optional | File identifier/inode from file attributes. |
| `fileSize` | Signed 64-bit integer, optional | File length in bytes. |
| `modificationDate` | Date number, optional | File modification time, rounded down to whole milliseconds when captured. |

Optional identity fields may be omitted or null; the app omits unavailable
values when encoding. The path must match exactly. Each other identity field
is compared when both the stored and current values exist. These checks help
reject replacement media at the same path; they are not a media-content hash.

Every note requires all of these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | UUID string | Unique within this document; used to address edits/deletions. |
| `primaryFrame`, `secondaryFrame` | Signed 64-bit integers | Zero-based, nonnegative source-relative frame positions for A/B. |
| `primaryTime`, `secondaryTime` | Finite JSON numbers | Nonnegative source-relative seconds retained as a fallback. |
| `primaryRateNumerator`, `secondaryRateNumerator` | Signed 64-bit integers | Positive frame-rate numerators captured with the note. |
| `primaryRateDenominator`, `secondaryRateDenominator` | Signed 64-bit integers | Positive frame-rate denominators; rate is numerator / denominator. |
| `text` | String | Note text, including Unicode and line breaks. |
| `createdAt`, `updatedAt` | Date numbers | Creation and last note-edit timestamps. |

Version 2 adds these note fields. Missing classification fields decode with
the defaults shown, including when reading a version 1 review. Unknown enum
values are rejected rather than silently discarded.

| Field | Type | Meaning |
| --- | --- | --- |
| `severity` | String | `info` (default), `minor`, `major`, or `critical`. |
| `category` | String | `general` (default), `picture`, `audio`, `sync`, or `metadata`. |
| `status` | String | `open` (default), `inProgress`, or `resolved`. |
| `primaryEndFrame` | Signed 64-bit integer, optional | Inclusive A end frame, at least `primaryFrame`; omitted or null means a single-frame finding. |

An explicit end equal to the start also lasts one frame. A range from frame
42 through 47 lasts six frames. B retains its captured start position; there
is no stored B endpoint. End frames receive the same arithmetic bounds checks
as start frames.

Frame indices are authoritative. The sidecar does not store embedded source
start timecode or DF/NDF display flags. Reports derive source timecode from the
loaded media only when its rate agrees with the finding's stored rate;
relative timecode always uses the stored frame and rate without duration
clamping. A PDF omits its paired still when either frame is unavailable in
the loaded media, while retaining the finding and an explanation.
The app trims new note text and rejects blank text in the UI; the store
itself does not impose that text restriction or require the seconds fields to
equal frame/rate. Loading also does not check positions against media duration;
playback navigation bounds the destination using the loaded media.

## Legacy version 1 example

This minimal legacy one-note document uses 24 fps, A frame 42 and B frame 48. The
identity objects omit optional file attributes for readability. The absolute
paths must match the actual selected sources; copying this example does not
relink a real review. The JSON below has been decoded and loaded through the
production model and sidecar store with matching example URLs. It loads as
Info / General / Open with no range, and its next successful write upgrades
the schema to version 2.

```json
{
  "schemaVersion": 1,
  "primarySource": { "canonicalPath": "/example/reference.mov" },
  "secondarySource": { "canonicalPath": "/example/encode.mov" },
  "notes": [
    {
      "id": "8CA583CA-02C3-40C0-ABDB-0C4A3C936D98",
      "primaryFrame": 42,
      "primaryTime": 1.75,
      "secondaryFrame": 48,
      "secondaryTime": 2,
      "primaryRateNumerator": 24,
      "primaryRateDenominator": 1,
      "secondaryRateNumerator": 24,
      "secondaryRateDenominator": 1,
      "text": "Check blue channel",
      "createdAt": 1700000000000,
      "updatedAt": 1700000010000
    }
  ]
}
```

## Validation and compatibility

The loader rejects malformed JSON, missing required fields, wrong field types,
unrepresentable integers, unsupported schema versions, mismatched source
identities, duplicate note UUIDs, negative/non-finite positions, and nonpositive
rate components, unknown classification values, and end frames before their
start. It also rejects rates/positions that overflow its reserved
64-bit report arithmetic. That reserve includes 24 hours of source timecode,
one marker-end frame, and a timebase of at least 1,000,000; a positive integer
alone is therefore not sufficient for a valid frame position.

Versions 1 and 2 are supported on load. Loading alone leaves the original file
untouched; a successful save or mutation writes version 2. Older apps that
only support version 1 reject version 2 and disable editing rather than
rewrite it and lose classifications or ranges. Keep a backup if an older app
must continue using the review.
Unknown object keys are ignored by decoding and are not preserved on rewrite.
Do not use extra keys for data that must survive an app edit. New interchange
tools should preserve all required fields and avoid assuming future versions
will remain compatible.

Invalid or unsupported existing sidecars remain untouched. A load failure
leaves note editing disabled and offers Retry. Restore a valid backup or move
the problematic sidecar aside before starting a new review. Keep a backup
before any manual JSON edits.

## Deliberate migration of historical rounded timebases

Historical reviews can store `29970/1000` (29.97) while current metadata correctly
reports `30000/1001`. These are different rational rates. Loading, editing a
finding, relinking, and exporting CSV/PDF retain the historical coordinates;
editor-marker exports continue to reject an incompatible A rate.

To produce a corrected review:

1. Open the original A/B media and saved review. In **Comparison Review → Notes**,
   choose **Migrate Rounded Timebases…**. If the historical review is already a
   separate copy, use **Open Notes Copy…** to open it for the same loaded pair first.
2. Review the original and destination paths, source paths, and each changed
   finding. The proposal shows the recorded A/B frames, inclusive A endpoint,
   old/new rational rates, frame-derived seconds, and stored fallback seconds.
3. Choose **Save and Use Migrated Copy** only after reviewing that proposal.
   Cancel leaves both the review and its active path unchanged.
4. Inspect the resulting marked frames and ranges, then export editor markers
   from the active copy. Subsequent note edits also save to this copy.

The operation preserves **frame indices**, not elapsed seconds: A/B starts and
inclusive A range endpoints keep exactly their recorded numbers. Corrected
sources receive the loaded exact rational rate and fallback seconds recomputed
as `frame × denominator / numerator`. It cannot recover a different intended
frame if old rounding affected capture. The migrated file preserves source
identities, UUIDs, text, classifications, ranges, and creation dates; changed
notes receive the proposal's new edit timestamp. Already compatible notes and
the unchanged source of a partially corrected note retain their original fields.
The proposal includes all notes, even when the Review filter hides some.

Migration is limited to the historical three-decimal rates `23.976`, `29.970`,
`47.952`, `59.940`, and `119.880`, including equivalent unreduced fractions,
when the loaded source has the corresponding exact `24000/1001`, `30000/1001`,
`48000/1001`, `60000/1001`, or `120000/1001` rate. Every other stored source rate
must already be equivalent to the loaded rate. Arbitrary rate changes, empty or
already compatible reviews, unknown/invalid durations, unavailable A/B starts,
and an inclusive A end outside the current media are rejected, without clamping
or guessing a new position. Pending saves must finish; a disk review that differs
from the displayed notes must be reconciled before migration.

The original sidecar remains **byte-for-byte unchanged**. The new file has an
`-exact-<identifier>.json` suffix beside it and is published with an exclusive
rename; existing files, media, and dangling symlinks cannot be replaced. The
store rereads and compares the original against the preview and checks the
original A/B identities plus file-stat snapshots at confirmation. Changed media,
changed reviews, canceled work, and a stale comparison session are rejected.
A completed disk write remains durable if its UI completion later becomes stale.
These checks do not lock media or other applications against concurrent changes.

The selected copy is active for the current session. Automatically reopening
A/B still discovers the original pair-specific sidecar; use **Notes → Open
Notes Copy…** to reopen a migrated copy deliberately. Opening a copy validates
its schema, notes, and ordered source identities before replacing the current
review, performs no file writes, and preserves the search filter. The sidecar
label identifies where subsequent edits will be saved. Opening another source
pair requires the separate relinking workflow; migration never relinks.

## Writes, conflicts, and lifecycle

Native migration preview, cancellation, save/adoption, copy reopening and
remaining assistive-technology/editor acceptance are recorded in
[the September 9 native check](COMPARE_REVIEW_MIGRATION_NATIVE_CHECK_2026-09-09.md).

The shared in-process store serializes edits. Each UUID-addressed add/update or
delete reloads the latest disk document, applies that mutation, sorts notes by
A frame, creation time, then UUID, validates, and writes atomically. This
preserves unrelated edits from other windows in the same app process. Updates
to the same UUID use the last applied whole note; there is no field-level merge
or conflict dialog. External writers and separate app processes are not locked
across the read/write cycle, so concurrent external editing can lose changes.

The controller queues its saves in order and ignores stale UI completions after
a pair replacement or newer revision. Save errors are shown in the Review UI;
visible edits must not be assumed durable after an error. Closing/replacing a
session invalidates every queued write, including intermediate saves waiting
behind an earlier operation. A write already inside the store may finish, but
its completion cannot update the closed or replacement session. There is no
guarantee that an edit still awaiting its write has reached disk. Atomic
replacement protects file integrity, not cross-process conflict resolution or
unsaved edits.

Notes/Export actions first commit pending note-text fields and wait for their
saves. Editing is disabled during this transition, including if the popover is
closed and reopened. Failed edits and deletions remain tracked in the current
session even after dismissing the error. **Retry Save** commits current text
drafts and retries outstanding writes without switching reviews. The next
Notes/Export action also retries them and continues only after every outstanding
mutation is saved. Reload is refused while changes remain unsaved. A successful
save to another note cannot hide an earlier failed change. These retained changes
are session-local, not a durable recovery journal; replacing or closing the
session still has the cancellation behavior described above.

The September 10 recovery regressions exercise actual permission-denied writes
in disposable read-only directories for ordinary saves, relinking and timebase
migration. They verify unchanged original sidecar/media bytes, no leftover
temporary files, and successful retry after restoring directory permissions.
Separate injected permission/disk-full errors cover retained edits/deletions,
repeated failures and controller retry. Focused native permission-denied
add/delete recovery, popover reopening and Retry Save layout are recorded in
[the native save-recovery check](COMPARE_REVIEW_SAVE_RECOVERY_NATIVE_CHECK_2026-09-10.md).
Full Keyboard Access and spoken VoiceOver remain separate acceptance gates.

`scripts/test-compare-review-disk-full.sh` runs an opt-in production-store
test on its own disk image: 32 MiB HFS+ by default, or 128 MiB APFS with
`AAGEDAL_DISK_FULL_FILESYSTEM=APFS`. It verifies the mount path, filesystem,
device and capacity before writing at most 40 MiB (HFS+) or 136 MiB (APFS)
of filler. Other filesystem selections are rejected before image creation. Real out-of-space
errors must preserve the existing sidecar and media for both save and delete;
freeing the filler must allow a valid retry without a failed high revision
blocking it. The harness retains test/volume evidence, rejects skipped or
missing coverage, then detaches and removes its image. It never fills the host
volume. Native disk-full alert/interaction acceptance remains separate from
this production-store integration check. The verified APFS and HFS+ runs are
recorded in [the disk-full check](COMPARE_REVIEW_APFS_DISK_FULL_CHECK_2026-09-10.md).

To use an existing test build, pass `--xctestrun /path/to/tests.xctestrun`.
Set `AAGEDAL_DISK_FULL_FULL_SUITE=1` to run all tests while enabling this check;
existing manifest environments, including optional ITU references, are retained.
The supplied manifest stays unchanged. `AAGEDAL_DISK_FULL_OUTPUT` selects a new
evidence directory. Ordinary test runs skip the disk-image test.

## Alignment and portability

Creating a note pauses playback, snaps A to a frame, and records B using the
current alignment mapping, bounded to B's media duration. A manual offset uses
`B time = A time + offset` and affects new notes. Existing notes keep their
original A/B positions when the offset changes. The override is session-local
and is not restored from the sidecar. See
[comparison alignment](COMPARE_MODE_ALIGNMENT.md).

Moving or renaming media can change the sidecar filename or source-identity
checks. Copying the JSON beside relocated media alone does not reconnect it.
Use the deliberate relinking workflow:

1. Open the relocated original source A and add the relocated original source B
   in the same order as the review. Relinking is available for an empty review;
   it does not merge with findings already loaded for the pair.
2. Open **Comparison Review → Notes → Relink Notes…** and select the old JSON sidecar.
3. Check the old and current A/B paths and note count in the confirmation.
   Confirm only when the loaded files are the intended originals.
4. Confirm the mapping to create the new pair-specific sidecar beside A.

Relinking retains note IDs, creation/edit timestamps, text, classifications,
inclusive ranges, frame coordinates, and stored rational rates. It updates
source identities and writes the current schema. It does not retime findings,
swap A/B anchors, restore alignment, or prove that the media content is equal.
Re-encoded or edited replacements may no longer match the stored frames.
Editor-marker exports reject findings whose stored A rate differs from the
loaded A rate, rather than silently placing them at a different time. Equivalent
rational rates are accepted. CSV/PDF remain available; their preview positions
use stored rates and are bounded to the loaded media duration.

The original sidecar is left untouched. An existing destination is never
replaced or merged, including an empty or invalid sidecar. If the old file
already occupies the new pair's destination, move it aside to a backup location
and select that backup for relinking. Resolve a destination conflict before
retrying; retain any existing review rather than deleting it to make room.
Malformed/unsupported sidecars and a sidecar changed after preview are rejected.
Closing or changing the comparison invalidates pending preview/confirmation
work. A completed disk write remains durable if its UI completion becomes stale.

The document includes absolute paths, filenames through those paths, file
attributes, and review text: consider that when sharing it. Retain the original
media pair and sidecar together as a backup; use exported reports for a review
record that can be read independently of the app.
