# FX6 MXF bounded-reader investigation — 2026-09-30

The current dependency maps the complete 8.64 GB Sony FX6 file, then touches
KLV headers and value prefixes throughout that mapping. This supplies a concrete
mechanism consistent with the retained 368.516 MiB transient lifetime-peak
increase. It is not evidence of an 8.64 GB heap copy, a proven allocation trace,
or a completed correction. **The bounded file-backed reader remains open.**

This investigation reads the exact SwiftMediaMetadata 3.0.1 source at
`8662054299a3e13c49c65f74c564360559d1bf7f`; the local development checkout has
the same revision. Source hashes and existing validated media identity are in
[bounded-reader-source-identities.json](bounded-reader-source-identities.json).
No dependency/app source or source media was edited, and no additional native
metadata performance profile was run.

## Concrete current path

`MetadataService.loadMetadata` calls the library's `readVideoMetadata(from:)`.
`Sources/SwiftMediaMetadata/SwiftMediaMetadata.swift:57–60` runs
`VideoMetadata.read(from:)` on a detached task. These are the relevant library
locations at the pinned revision:

| Source | Existing behavior | Implication |
| --- | --- | --- |
| `API/VideoMetadata.swift:151–153, 304–330` | Peeks 16 bytes; Matroska gets a bounded prefix, every other container gets `Data(contentsOf:options:.alwaysMapped)` | MXF maps the full source before parsing. |
| `Video/MXFReader.swift:78–111` | Walks every KLV to EOF; reads its 16-byte key and BER length, then peeks up to **512 bytes** before classification; advances the Data cursor over skipped values | Skipping essence avoids copying its complete value, but dispersed header/peek accesses fault pages across the mapping. The introductory comment says 64-byte peeks; the actual constant is 512 at line 50. |
| `Binary/BinaryReader.swift:165–177, 240–250` | Builds `Data` values from bounded slices; `seek(to:)` only changes the offset | There is no file-backed seek/read in this MXF walk. |
| `Video/MXFReader.swift:105–111` | Only qualifying metadata KLVs of at most 32 MiB are materialized | The existing cap protects individual values, not the lifetime of all mapped pages visited. |
| `Video/MXFReader.swift:218–229, 412–437`; `Video/ARRIJSONParser.swift:53, 72–119` | NRT fallback searches the first 16 MiB when camera metadata is absent; ARRI JSON discovery always scans that same prefix | Header-prefix scanning adds a bounded region to the dispersed KLV accesses, including on this Sony input. |
| `API/VideoMetadata.swift:201–209` | Drops `originalData` for MXF/ARRIRAW/X-OCN and other read-only formats | Releasing the map after parse is consistent with RSS returning near baseline. It does not prevent the peak while the map is live. |

The parser derives fallback duration from the maximum duration-bearing set,
collects Material/File Package timecodes in encounter order, processes the
Primer/MCA subdescriptors and audio strong references, and sniffs NRT XML/C2PA
under unknown keys. A safe change must retain these semantics, including sets
and manifests after essence. A fixed prefix-only MXF read or stopping at first
essence would be a separate compatibility regression.

## Bounded structural inventory and inference

[count-klv-touched-pages.py](count-klv-touched-pages.py) opens the source
read-only and performs a capped structural walk using 25-byte `pread` header
requests. A request covers the key and maximum BER field and can include up
to eight leading value bytes; it never loads complete essence/metadata values
or retains their bytes. Its output contains only offsets, key-frequency counts
and projected page numbers. The complete source walk
finishes inside the 250,000-KLV cap in approximately 1.85 seconds; its output
is [klv-page-inventory.json](klv-page-inventory.json).

| Structural observation | Result |
| --- | ---: |
| Source size / parsed-through offset | 8,643,449,904 bytes |
| Complete KLVs | 160,944 |
| Header bytes actually requested by the inventory | 4,023,600 bytes |
| Value-prefix bytes the existing parser would peek | 52,723,414 bytes |
| Header/peek projected distinct 16 KiB pages | 22,523 |
| Header/peek projected mapped bytes | 369,016,832 bytes / 351.922 MiB |
| Union with the unconditional first-16-MiB ARRI scan | 23,500 pages / 385,024,000 bytes / **367.188 MiB** |

The independently retained earlier
[mxf-header-page-diagnostic.json](mxf-header-page-diagnostic.json) agrees exactly
on the KLV count, header/peek page count and peek bytes. This new inventory uses
bounded `pread` instead of a full mapping and adds the deduplicated ARRI-prefix
page union.

**The page union is an inference about source pages the code can touch, not a
measured RSS value.** OS residency, readahead, reclamation, metadata copies and
runtime allocations can change the actual peak. Its 367.188 MiB estimate is
close to the production host's measured 368.516 MiB increase, strengthening the
mapped-page explanation without proving complete causal attribution. Neither
inventory assigns the measured peak to a particular allocation stack. The
source hash comes from the existing validated production profile; this bounded
walk does not reread the full payload to hash it again.

## Smallest safe upstream patch scope

The proposed correction belongs in SwiftMediaMetadata, initially limited to
`API/VideoMetadata.swift`, `Video/MXFReader.swift` and a small private MXF
file-cursor helper, plus focused URL-path tests. Avoid changing the shared
`BinaryReader` behavior for every other format.

1. Add a file-backed MXF entry point, with the existing `parse(_ data: Data)`
   retained. Detect MXF from the same magic prefix before calling the generic
   whole-container loader in `VideoMetadata.read(from:)`. Feed both entries
   through one common KLV classification/extraction loop so ordering and
   tolerance behavior cannot drift.
2. Give the file cursor a fixed extent, checked absolute offset, exact bounded
   reads and seek-over-value behavior. Read the 16-byte key and 1–9 BER bytes,
   then at most the existing 512-byte peek. Read the complete value only if
   the **same** classification passes and the existing 32 MiB cap permits it.
   Preserve unknown-key XML/JUMBF sniffing; skipping known essence peeks is not
   necessary for this correction and should not be bundled into it.
3. Read at most the existing 16 MiB prefix into one scratch Data buffer for
   unchanged NRT/ARRI fallbacks, releasing it after those scans. Release each
   temporary metadata/peek buffer promptly; on Darwin, prevent bridged
   FileHandle/NSData temporaries accumulating through an enclosing
   autorelease pool. A small bounded read cache may reduce syscall overhead,
   but must never prefetch full essence values.
4. Keep URL postprocessing intact: ARRIRAW/X-OCN promotion, full file size,
   default format name, NRT sidecar discovery, timecode merging and nil
   `originalData` for read-only formats. Returning early from a new MXF branch
   must not bypass these behaviors. The original Data API must continue to
   accept caller-owned data and nonzero-start-index slices.

This bounds parser scratch to the prefix, one capped metadata value and a
small cursor/cache, independent of essence length. Parsed results can still
scale with metadata count; no claim of a fixed total-memory ceiling is proposed.
The full KLV walk remains linear in KLV count and may cost additional I/O calls,
so wall time must be compared alongside RSS.

The cursor must reject BER indefinite/invalid byte counts and lengths above
`Int.max`, use subtraction-based bounds checks before offset arithmetic, handle
short reads and concurrent truncation safely, and close its handle on every
exit. Keep the existing tolerant break-on-truncated-KLV result behavior; genuine
I/O failures need explicit error handling rather than silently returning a
complete-looking result. A checked file extent is not a content-immutability
proof; same-size concurrent replacement needs to be qualified or detected.

## Required patch verification

Before proposing a dependency release, compare Data and file-backed outputs on
existing `MXFReaderTests`, `VideoContainerTests` and `MXFMCALabelsTests`, plus
ARRI JSON tests. Include a footer metadata/C2PA record after a large skipped
value, a late duration update, Material/File timecode encounter order,
Primer/MCA references, dark-key JUMBF, embedded RP2057 NRT, sidecar fallback,
ARRIRAW/X-OCN promotion, metadata above the 32 MiB cap, truncated/overflowing
BER and short reads. Instrument requested byte counts/offsets in small cursor
tests so they prove essence values are skipped rather than merely hiding a copy.

An isolated dependency candidate should then compare complete exporter output
and app cache parity on the three retained Sony originals and existing ARRI/
X-OCN/MCA samples. Reuse the production metadata memory runner to retain uncached
lifetime peaks and current RSS before/after conversion; require unchanged input
hashes and review timings. Only after those comparisons pass should an immutable
library release/repin be considered. Multi-hour scaling, external-volume I/O,
concurrent file changes and base-M1 acceptance remain separate checks. No such
candidate implementation, profile comparison or repin is claimed here.
