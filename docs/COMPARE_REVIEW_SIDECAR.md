# Comparison review sidecar format

Schema version 1 stores single-frame text findings for an ordered source A/B
pair in local JSON. Source media is never written. PDF images are generated at
export time; this format contains no image attachments, severity, category,
status, ranges, or alignment setting. CSV/PDF and editor-marker exports are
separate representations, not sidecars. Editor acceptance is tracked in
[marker interchange validation](COMPARE_MODE_INTERCHANGE.md).

## Finding and navigating notes

Use **Filter review notes** in the Review popover to search note text without
changing the saved review. Matching ignores case and diacritics and trims
surrounding search whitespace. The note count shows matches out of the total,
and orange timeline markers show the same matches. Clear the filter to restore
the complete list. Changing the source pair or closing the comparison clears
the filter; reopening the popover in the same session retains it.

The previous/next buttons seek both sources to the nearest matching marked
frame before/after the current position using the current comparison alignment.
These actions are also in the timeline context menu. They skip duplicate notes
on the current frame and stop at either end rather than wrapping. Each row's
timecode remains a direct seek action. Exports always include **all notes**,
including those hidden by the filter.

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
| `schemaVersion` | Integer | Required; currently exactly `1` on load. |
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
| `createdAt`, `updatedAt` | Date numbers | Creation and last text-edit timestamps. |

Frame indices are authoritative. The sidecar does not store embedded source
start timecode or DF/NDF display flags. Reports derive those from the loaded
media. The app trims new note text and rejects blank text in the UI; the store
itself does not impose that text restriction or require the seconds fields to
equal frame/rate. Loading also does not check positions against media duration;
playback navigation bounds the destination using the loaded media.

## Example

This minimal one-note document uses 24 fps, A frame 42 and B frame 48. The
identity objects omit optional file attributes for readability. The absolute
paths must match the actual selected sources; copying this example does not
relink a real review. The JSON below has been decoded and loaded through the
production model and sidecar store with matching example URLs.

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
rate components. It also rejects rates/positions that overflow its reserved
64-bit report arithmetic. That reserve includes 24 hours of source timecode,
one marker-end frame, and a timebase of at least 1,000,000; a positive integer
alone is therefore not sufficient for a valid frame position.

Version 1 is the only supported load version; there is no automatic migration.
Unknown object keys are ignored by decoding and are not preserved on rewrite.
Do not use extra keys for data that must survive an app edit. New interchange
tools should preserve all required fields and avoid assuming future versions
will remain compatible.

Invalid or unsupported existing sidecars remain untouched. A load failure
leaves note editing disabled and offers Retry. Restore a valid backup or move
the problematic sidecar aside before starting a new review. Keep a backup
before any manual JSON edits.

## Writes, conflicts, and lifecycle

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
session cancels pending work; there is no guarantee that an edit still awaiting
its write has reached disk. Atomic replacement protects file integrity, not
cross-process conflict resolution or unsaved edits.

## Alignment and portability

Creating a note pauses playback, snaps A to a frame, and records B using the
current alignment mapping, bounded to B's media duration. A manual offset uses
`B time = A time + offset` and affects new notes. Existing notes keep their
original A/B positions when the offset changes. The override is session-local
and is not restored from the sidecar. See
[comparison alignment](COMPARE_MODE_ALIGNMENT.md).

There is **no relinking workflow yet**. Moving/renaming media, copying it to
another filesystem, swapping sources, or replacing a master can change naming
or identity checks. Copying the JSON beside relocated media alone does not make
it portable. The document includes absolute paths, filenames through those
paths, file attributes, and review text: consider that when sharing it. Retain
the original media pair and sidecar together as a backup; use exported reports
for a review record that can be read independently of the app.
