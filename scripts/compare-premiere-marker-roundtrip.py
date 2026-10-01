#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Strict comparison of source-A review sequence markers in FCP7 XML (xmeml).

XML comparison is file evidence, not proof of native Premiere acceptance.
The scope is one untrimmed source-A video clip and its sequence markers.
"""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET


def text(element, path):
    items = element.findall(path)
    if len(items) != 1 or items[0].text is None:
        raise ValueError(f"Expected exactly one populated {path}")
    return items[0].text


def integer(element, path):
    value = text(element, path)
    if not re.fullmatch(r"-?\d+", value):
        raise ValueError(f"Invalid integer {path}: {value!r}")
    return int(value)


def rate(element):
    base = integer(element, "rate/timebase")
    ntsc = text(element, "rate/ntsc")
    if base <= 0 or ntsc not in ("TRUE", "FALSE"):
        raise ValueError("Invalid xmeml rate")
    return Fraction(base * 1000, 1001) if ntsc == "TRUE" else Fraction(base)


def timecode(element, expected_rate):
    nodes = element.findall("timecode")
    if len(nodes) != 1 or rate(nodes[0]) != expected_rate:
        raise ValueError("Missing or mismatched timecode rate")
    frame = integer(nodes[0], "frame")
    display = text(nodes[0], "displayformat")
    if frame < 0 or display not in ("DF", "NDF"):
        raise ValueError("Invalid source timecode")
    if display == "DF" and expected_rate not in (Fraction(30000, 1001), Fraction(60000, 1001)):
        raise ValueError("DF requires 30000/1001 or 60000/1001")
    labels = nodes[0].findall("string")
    if len(labels) > 1:
        raise ValueError("Ambiguous timecode string")
    if labels:
        label = labels[0].text or ""
        match = re.fullmatch(r"(\d{2})([:;])(\d{2})([:;])(\d{2})([:;])(\d{2,3})", label)
        if not match:
            raise ValueError(f"Invalid timecode string: {label!r}")
        hour, hour_delimiter, minute, minute_delimiter, second, frame_delimiter, subframe = match.groups()
        hour, minute, second, subframe = map(int, (hour, minute, second, subframe))
        nominal = int(expected_rate + Fraction(1, 2))
        delimiters = hour_delimiter + minute_delimiter + frame_delimiter
        # Premiere 26.5.1 writes HH;MM;SS;FF for DF. Preserve the existing
        # colon and HH:MM:SS;FF forms, rejecting every other mixed form.
        permitted_delimiters = (":::", "::;", ";;;") if display == "DF" else (":::",)
        if (hour >= 24 or minute >= 60 or second >= 60 or subframe >= nominal
                or delimiters not in permitted_delimiters):
            raise ValueError("Timecode string fields or delimiter contradict display format")
        label_frame = ((hour * 60 + minute) * 60 + second) * nominal + subframe
        if display == "DF":
            dropped = 2 if nominal == 30 else 4
            if minute % 10 and second == 0 and subframe < dropped:
                raise ValueError("Timecode string names a skipped drop-frame label")
            total_minutes = hour * 60 + minute
            label_frame -= dropped * (total_minutes - total_minutes // 10)
        if label_frame != frame:
            raise ValueError("Timecode string contradicts encoded frame")
    return dict(frame=frame, displayFormat=display)


def media_path(url):
    parsed = urlsplit(url)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost") or parsed.query or parsed.fragment:
        raise ValueError("Expected an absolute local source file URL")
    path = Path(unquote(parsed.path))
    if not path.is_absolute():
        raise ValueError("Source path must be absolute")
    return path.resolve()


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def geometry(element, expected_rate):
    if rate(element) != expected_rate:
        raise ValueError("Video sample rate differs from sequence")
    width, height = integer(element, "width"), integer(element, "height")
    par = pixel_aspect(element, required=True)
    if min(width, height) <= 0:
        raise ValueError("Invalid raster or pixel aspect")
    return dict(raster=[width, height], pixelAspect=par, fieldDominance=field_dominance(element))


def pixel_aspect(element, required=False):
    values = element.findall("pixelaspectratio")
    if (len(values) > 1 or (required and not values)
            or (values and not (values[0].text or "").strip())):
        raise ValueError("Invalid or ambiguous pixel aspect")
    return values[0].text if values else None


def field_dominance(element):
    values = element.findall("fielddominance")
    if len(values) > 1 or (values and values[0].text not in ("none", "lower", "upper", "odd", "even")):
        raise ValueError("Invalid or ambiguous field dominance")
    return values[0].text if values else None


def require_enabled(element):
    # XMEML defaults omitted enabled elements to TRUE. A muted track or clip
    # cannot establish the unchanged source-A review sequence described here.
    values = element.findall("enabled")
    if len(values) > 1 or (values and values[0].text != "TRUE"):
        raise ValueError(f"Review {element.tag} must be enabled with an unambiguous TRUE value")


def read_export(path, sequence_name=None):
    data = path.read_bytes()
    # XML may be UTF-16 or UTF-32. Strip NUL padding only for this ASCII
    # declaration scan; the parser still receives the untouched document.
    declarations = data.replace(b"\x00", b"")
    if re.search(br"<!ENTITY|<!DOCTYPE\s+[^>]*(?:SYSTEM|PUBLIC|\[)", declarations, re.I):
        raise ValueError("External DTDs and entity declarations are unsupported")
    root = ET.fromstring(data)
    if root.tag != "xmeml" or root.get("version") not in ("4", "5"):
        raise ValueError("Expected FCP7 XML xmeml version 4 or 5, not FCPXML")
    sequences = root.findall(".//sequence")
    if sequence_name is not None:
        sequences = [s for s in sequences if s.findtext("name") == sequence_name]
    if len(sequences) != 1:
        raise ValueError("Expected one unique review sequence; select its exact name if necessary")
    sequence = sequences[0]
    require_enabled(sequence)
    fps = rate(sequence)
    duration = integer(sequence, "duration")
    if duration <= 0:
        raise ValueError("Sequence duration must be positive")
    tracks = sequence.findall("media/video/track")
    clips = sequence.findall("media/video/track/clipitem")
    if (len(tracks) != 1 or len(clips) != 1
            or tracks[0].find("transitionitem") is not None or tracks[0].find("generatoritem") is not None):
        raise ValueError("Expected exactly one video track and one untrimmed source-A clip")
    require_enabled(tracks[0])
    clip = clips[0]
    require_enabled(clip)
    placement = {p: integer(clip, p) for p in ("start", "end", "in", "out", "duration")}
    media_duration = placement["duration"]
    if media_duration <= 0 or media_duration > duration or placement != dict(
            start=0, end=media_duration, **{"in": 0, "out": media_duration}, duration=media_duration):
        raise ValueError("Review source-A clip must be full, untrimmed and start at sequence frame zero")
    if rate(clip) != fps or clip.find("sequence") is not None or clip.find("filter") is not None:
        raise ValueError("Unsupported nested, filtered or retimed source-A clip")
    file_nodes = clip.findall("file")
    if len(file_nodes) != 1:
        raise ValueError("Expected one source-A file reference")
    media = file_nodes[0]
    if len(media) == 0:
        definitions = [f for f in root.findall(".//file") if f.get("id") == media.get("id") and len(f)]
        if media.get("id") is None or len(definitions) != 1:
            raise ValueError("Unresolved or ambiguous media file ID")
        media = definitions[0]
    if rate(media) != fps or integer(media, "duration") != media_duration:
        raise ValueError("Source-A media rate/duration differs from its untrimmed clip")
    seq_format = sequence.findall("media/video/format/samplecharacteristics")
    file_format = media.findall("media/video/samplecharacteristics")
    if len(seq_format) > 1 or len(file_format) > 1:
        raise ValueError("Ambiguous sequence/source video geometry")
    source_geometry = geometry(file_format[0], fps) if file_format else None
    # A native clip override can change displayed field order despite an
    # unchanged file and sequence format. Compare its effective interpretation.
    clip_field_dominance = field_dominance(clip)
    if clip_field_dominance is None and source_geometry:
        clip_field_dominance = source_geometry["fieldDominance"]
    # XMEML permits pixelaspectratio directly on clipitem. An unchanged file
    # and sequence raster/PAR cannot prove an unchanged clip interpretation.
    clip_pixel_aspect = pixel_aspect(clip)
    if clip_pixel_aspect is None and source_geometry:
        clip_pixel_aspect = source_geometry["pixelAspect"]
    markers = []
    encoded_outs = []
    for marker in sequence.findall("marker"):
        start, end = integer(marker, "in"), integer(marker, "out")
        # Premiere can serialize a point's undefined out as -1. Preserve its
        # encoding in the report while comparing its one-frame meaning.
        stop = start + 1 if end == -1 else end
        if start < 0 or stop <= start or stop > duration or marker.find("marker") is not None:
            raise ValueError("Invalid or nested sequence marker interval")
        comments = marker.findall("comment")
        if len(comments) != 1:
            raise ValueError("Expected exactly one marker comment")
        markers.append((start, stop - start, text(marker, "name"), comments[0].text or ""))
        encoded_outs.append(end)
    if not markers or len(sequence.findall(".//marker")) != len(markers):
        raise ValueError("Expected nonempty markers belonging only to the sequence")
    source_url = text(media, "pathurl")
    return dict(sha256=hashlib.sha256(data).hexdigest(), xmlVersion=root.get("version"),
                sequenceName=text(sequence, "name"), rate=str(fps), durationFrames=duration,
                sourceDurationFrames=media_duration, clipPlacement=placement,
                sequenceTimecode=timecode(sequence, fps), sourceTimecode=timecode(media, fps),
                sequenceGeometry=geometry(seq_format[0], fps) if seq_format else None,
                sourceGeometry=source_geometry, clipFieldDominance=clip_field_dominance,
                clipPixelAspect=clip_pixel_aspect,
                sourceURL=source_url, sourcePath=str(media_path(source_url)),
                markers=markers, encodedMarkerOutFrames=encoded_outs)


def compare(original, returned, verify_media=False, returned_sequence_name=None):
    before = read_export(original)
    after = read_export(returned, returned_sequence_name)
    checks = {key: before[key] == after[key] for key in
              ("rate", "durationFrames", "sourceDurationFrames", "clipPlacement", "sequenceTimecode", "sourceTimecode",
               "sequenceGeometry", "sourceGeometry", "clipFieldDominance", "clipPixelAspect", "sourcePath")}
    checks["markerTimingAndTitles"] = Counter(m[:3] for m in before["markers"]) == Counter(m[:3] for m in after["markers"])
    checks["exactMarkerContent"] = Counter(before["markers"]) == Counter(after["markers"])
    if verify_media:
        before["mediaSHA256"] = digest(Path(before["sourcePath"]))
        after["mediaSHA256"] = digest(Path(after["sourcePath"]))
        checks["sourceMediaBytes"] = before["mediaSHA256"] == after["mediaSHA256"]
    return dict(status="exact-match" if all(checks.values()) else "differences",
                scope="Single source-A review sequence XML comparison; not native editor acceptance",
                returnedSequenceName=returned_sequence_name, checks=checks,
                mediaBytesCompared=verify_media, original=before, returned=after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("returned", type=Path)
    parser.add_argument("--verify-media", action="store_true")
    parser.add_argument("--returned-sequence-name", help="Select one unique exact sequence name in a returned project XML")
    parser.add_argument("--output", type=Path, help="Write a new JSON report; existing files are refused")
    args = parser.parse_args()
    try:
        report = compare(args.original, args.returned, args.verify_media, args.returned_sequence_name)
    except (ValueError, KeyError, OSError, ET.ParseError, ZeroDivisionError) as error:
        report = dict(status="invalid", error=str(error))
    output = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        try:
            with args.output.open("x") as target:
                target.write(output)
        except OSError as error:
            print(json.dumps(dict(status="invalid", error=str(error))))
            return 2
    print(output, end="")
    return {"exact-match": 0, "differences": 1, "invalid": 2}[report["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
