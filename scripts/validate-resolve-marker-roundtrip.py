#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare an app marker EDL with Resolve's native marker re-export.

Optional native snapshots also verify captured timeline/source-A placement.
Keep the editor workflow record alongside the report. Never filter unwanted events
out of the re-export: extra, negative, and duplicate events must remain visible.
"""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


TIMECODE = r"-?\d{2}:\d{2}:\d{2}[:;]\d{2}"
EVENT = re.compile(rf"\d{{3}}\s+\S+\s+V\s+C\s+({TIMECODE})\s+({TIMECODE})\s+({TIMECODE})\s+({TIMECODE})\s*")
COMMENT = re.compile(r"\s*\|C:([^|]+) \|M:(.*) \|D:([1-9]\d*)\s*")


def frame_number(label, rate, drop):
    nominal = round(rate)
    if nominal < 1 or nominal > 60:
        raise ValueError("Unsupported nominal frame rate")
    dropped = 0
    if drop:
        if rate not in (Fraction(30000, 1001), Fraction(60000, 1001)):
            raise ValueError("Drop-frame requires 30000/1001 or 60000/1001")
        dropped = 2 if nominal == 30 else 4
    negative = label.startswith("-")
    hours, minutes, seconds, frames = map(int, re.split(r"[:;]", label.lstrip("-")))
    if hours > 23 or minutes > 59 or seconds > 59 or frames >= nominal:
        raise ValueError(f"Invalid timecode: {label}")
    if not drop and ";" in label:
        raise ValueError("Semicolon timecode conflicts with NON-DROP FRAME header")
    if dropped and minutes % 10 and seconds == 0 and frames < dropped:
        raise ValueError(f"Skipped drop-frame label: {label}")
    total_minutes = hours * 60 + minutes
    value = ((hours * 3600 + minutes * 60 + seconds) * nominal + frames
             - dropped * (total_minutes - total_minutes // 10))
    return -value if negative else value


def parse_edl(text, rate):
    mode = None
    pending = None
    markers = []
    for line in text.splitlines():
        if not line.strip():
            continue
        if line.startswith("TITLE:") and mode is None:
            continue
        if line in ("FCM: DROP FRAME", "FCM: NON-DROP FRAME") and mode is None:
            mode = line == "FCM: DROP FRAME"
            continue
        event = EVENT.fullmatch(line)
        if event and mode is not None and pending is None:
            values = [frame_number(label, rate, mode) for label in event.groups()]
            if values[0:2] != values[2:4] or values[1] <= values[0]:
                raise ValueError("Expected matching, forward source/record marker spans")
            pending = values[2]
            continue
        comment = COMMENT.fullmatch(line)
        if comment and pending is not None:
            color, note, duration = comment.groups()
            markers.append((pending, int(duration), color, note))
            pending = None
            continue
        raise ValueError(f"Unrecognized or misplaced EDL line: {line[:120]}")
    if mode is None or pending is not None or not markers:
        raise ValueError("EDL is empty, incomplete, or missing its frame-count mode")
    return mode, markers


def compare(original, returned, rate):
    expected_mode, expected = parse_edl(original, rate)
    actual_mode, actual = parse_edl(returned, rate)
    missing = Counter(expected) - Counter(actual)
    unexpected = Counter(actual) - Counter(expected)

    def entries(counter):
        return [dict(frame=frame, duration=duration, color=color, note=note, count=count)
                for (frame, duration, color, note), count in sorted(counter.items())]

    return dict(status="passed" if expected_mode == actual_mode and not missing and not unexpected else "failed",
                expectedCount=len(expected), actualCount=len(actual),
                frameCountModeMatches=expected_mode == actual_mode,
                missing=entries(missing), unexpected=entries(unexpected))


def verify_fixture(manifest_path, original, returned, rate):
    """Bind a generated-fixture comparison to unchanged current media and review.

    This is file provenance, not evidence that the editor loaded these files.
    """
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    if rate != Fraction(manifest["rateNumerator"], manifest["rateDenominator"]):
        raise ValueError("Comparison rate differs from fixture media rate")
    hashes = manifest["sha256"]
    if not isinstance(hashes, dict) or not hashes:
        raise ValueError("Fixture manifest has no input hashes")
    paths = {}
    for name, expected in hashes.items():
        if not isinstance(name, str) or Path(name).name != name or name in (".", ".."):
            raise ValueError("Fixture hashes must identify files directly beside the manifest")
        path = manifest_path.parent / name
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            raise ValueError(f"Fixture input changed: {name}")
        paths[name] = path
    review_name = manifest["reviewFile"]
    if review_name not in paths or not {"source-a.mov", "source-b.mov"} <= paths.keys():
        raise ValueError("Fixture manifest must hash both sources and the selected review")
    document = json.loads(paths[review_name].read_bytes())
    source_paths = [paths["source-a.mov"].resolve(), paths["source-b.mov"].resolve()]
    for key, path in zip(("primarySource", "secondarySource"), source_paths):
        if Path(document[key]["canonicalPath"]).resolve() != path:
            raise ValueError("Review source identity differs from current fixture location")
    count = manifest["reviewMarkerCount"]
    if type(count) is not int or count <= 0 or count != len(document["notes"]):
        raise ValueError("Fixture review count differs from manifest")
    # Exporter appends these fields last; splitting from the right keeps a
    # finding's own text from impersonating the appended provenance fields.
    for text in (original, returned):
        _, markers = parse_edl(text, rate)
        if len(markers) != count:
            raise ValueError("EDL marker count differs from selected fixture review")
        for _, _, _, note in markers:
            prefix, b_url = note.rsplit(" / Source B URL: ", 1)
            _, a_url = prefix.rsplit(" / Source A URL: ", 1)
            for url, path in zip((a_url, b_url), source_paths):
                parsed = urlsplit(url)
                if (parsed.scheme != "file" or parsed.netloc not in ("", "localhost")
                        or parsed.query or parsed.fragment or not parsed.path.startswith("/")
                        or Path(unquote(parsed.path)).resolve() != path):
                    raise ValueError("EDL source URL differs from current fixture source")
    return dict(status="passed", manifestSHA256=hashlib.sha256(manifest_bytes).hexdigest(),
                inputSHA256=hashes, reviewFile=review_name, markerCount=count,
                sourcePaths=[str(path) for path in source_paths],
                scope="Unchanged fixture files and exported source URLs; editor media loading requires native evidence")


def verify_native_snapshot(snapshot_path, manifest_path, original, rate, editor_version):
    """Validate the read-only Resolve capture for one complete, untrimmed fixture clip."""
    snapshot_bytes = snapshot_path.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    manifest = json.loads(manifest_path.read_bytes())
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("metadata"), dict):
        raise ValueError("Invalid native snapshot metadata")
    metadata = snapshot["metadata"]

    def string(record, key):
        if not isinstance(record, dict) or not isinstance(record.get(key), str):
            raise ValueError(f"Native snapshot requires string field: {key}")
        return record[key]

    def integer(record, key):
        value = Fraction(string(record, key))
        if value.denominator != 1:
            raise ValueError(f"Native snapshot has fractional frame: {key}")
        return value.numerator

    mode, expected = parse_edl(original, rate)
    # Resolve reports these exact broadcast rates as rounded decimal strings.
    display_rate = {Fraction(24000, 1001): "23.976", Fraction(30000, 1001): "29.97",
                    Fraction(60000, 1001): "59.94"}.get(rate, str(rate))
    if (string(metadata, "schemaVersion") != "1"
            or string(metadata, "editorVersion") != editor_version
            or string(metadata, "rate") != display_rate
            or string(metadata, "dropFrame") != str(int(mode))):
        raise ValueError("Native snapshot schema, editor version, rate or DF mode differs")
    if not string(metadata, "project").strip() or not string(metadata, "timeline").strip():
        raise ValueError("Native snapshot lacks project/timeline identity")
    start_label = manifest["sourceStartTimecode"] or "00:00:00:00"
    start = frame_number(start_label, rate, mode)
    frames = manifest["durationFrames"]
    if (string(metadata, "startTimecode") != start_label
            or integer(metadata, "startFrame") != start
            or integer(metadata, "endFrame") != start + frames
            or integer(metadata, "videoTracks") != 1):
        raise ValueError("Native timeline start, duration or video track count differs")
    clips = snapshot.get("clips")
    if not isinstance(clips, list) or len(clips) != 1:
        raise ValueError("Expected exactly one native V1 fixture clip")
    clip = clips[0]
    source = (manifest_path.parent / "source-a.mov").resolve()
    if (not Path(string(clip, "path")).is_absolute()
            or Path(clip["path"]).resolve() != source
            or string(clip, "fps") != display_rate
            or string(clip, "sourceStart") != start_label
            or integer(clip, "sourceFrames") != frames
            or integer(clip, "startFrame") != start
            or integer(clip, "endFrame") != start + frames
            or integer(clip, "leftOffset") != 0):
        raise ValueError("Native media identity, rate or untrimmed placement differs")
    markers = snapshot.get("markers")
    if not isinstance(markers, list):
        raise ValueError("Native snapshot lacks marker records")
    actual = []
    for marker in markers:
        if string(marker, "note") != "":
            raise ValueError("Unexpected native marker note content")
        actual.append((start + integer(marker, "frame"), integer(marker, "duration"),
                       "ResolveColor" + string(marker, "color"), string(marker, "name")))
    if Counter(expected) != Counter(actual):
        raise ValueError("Native marker anchors, durations, colors or exact texts differ")
    return dict(status="passed", snapshotSHA256=hashlib.sha256(snapshot_bytes).hexdigest(),
                project=metadata["project"], timeline=metadata["timeline"], markerCount=len(actual),
                sourcePath=str(source), startTimecode=start_label,
                scope="Captured Resolve timeline records and source A placement; source B is note provenance only")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("returned", type=Path)
    parser.add_argument("--rate", required=True, help="Exact rational rate, e.g. 30000/1001")
    parser.add_argument("--editor-version", required=True)
    parser.add_argument("--fixture-manifest", type=Path,
                        help="Verify current source URLs and unchanged inputs from the fixture generator")
    parser.add_argument("--native-snapshot", type=Path,
                        help="Read-only Resolve JSON capture; requires --fixture-manifest")
    parser.add_argument("--output", type=Path, required=True, help="New JSON evidence file")
    args = parser.parse_args()
    try:
        if args.native_snapshot and not args.fixture_manifest:
            raise ValueError("--native-snapshot requires --fixture-manifest")
        rate = Fraction(args.rate)
        original, returned = args.original.read_bytes(), args.returned.read_bytes()
        result = compare(original.decode("utf-8-sig"), returned.decode("utf-8-sig"), rate)
        if args.fixture_manifest:
            result["fixtureProvenance"] = verify_fixture(
                args.fixture_manifest, original.decode("utf-8-sig"), returned.decode("utf-8-sig"), rate)
        if args.native_snapshot:
            result["nativeTimeline"] = verify_native_snapshot(
                args.native_snapshot, args.fixture_manifest, original.decode("utf-8-sig"), rate, args.editor_version)
        result.update(rate=str(rate), editorVersion=args.editor_version,
                      originalSHA256=hashlib.sha256(original).hexdigest(),
                      returnedSHA256=hashlib.sha256(returned).hexdigest(),
                      scope=("EDL comparison, unchanged fixtures and captured native timeline/source-A identity"
                             if args.native_snapshot else
                             "Supplied EDL comparison only; native import and media identity require separate evidence"))
        with args.output.open("x") as output:
            json.dump(result, output, ensure_ascii=False, indent=2)
            output.write("\n")
        print(f"{result['status']}: {result['expectedCount']} expected, {result['actualCount']} returned; {args.output}")
        return 0 if result["status"] == "passed" else 1
    except (ValueError, OSError, ZeroDivisionError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
