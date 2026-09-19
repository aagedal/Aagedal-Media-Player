#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare single-browser-clip review exports; differences exit nonzero.

This is a diagnostic, not a claim of complete editor acceptance. Media bytes
are checked only with --verify-media; XML alone cannot prove source identity.
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


def seconds(value):
    if not re.fullmatch(r"-?\d+(?:/[1-9]\d*)?s", value):
        raise ValueError(f"Invalid rational time: {value!r}")
    return Fraction(value[:-1])


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def read_format(resources, reference):
    fmt = resources[reference]
    if fmt.tag != "format":
        raise ValueError("Invalid format reference")
    rate = seconds(fmt.attrib["frameDuration"])
    if rate <= 0:
        raise ValueError("Frame duration must be positive")
    width, height = int(fmt.attrib["width"]), int(fmt.attrib["height"])
    par = Fraction(int(fmt.get("paspH", "1")), int(fmt.get("paspV", "1")))
    if min(width, height, par) <= 0:
        raise ValueError("Raster and pixel aspect ratio must be positive")
    return dict(raster=[width, height], pixelAspect=str(par), frameDuration=str(rate))


def read_export(path, clip_name=None):
    data = path.read_bytes()
    # Accept the bare FCPXML doctype, never entity declarations or external DTDs.
    if re.search(br"<!ENTITY|<!DOCTYPE\s+[^>]*(?:SYSTEM|PUBLIC|\[)", data, re.I):
        raise ValueError("External DTDs and entity declarations are unsupported")
    root = ET.fromstring(data)
    if root.tag != "fcpxml":
        raise ValueError("Expected FCPXML")
    clips = root.findall(".//asset-clip")
    browser_clips = root.findall(".//event/asset-clip")
    if clip_name is not None:
        clips = [clip for clip in browser_clips if clip.get("name") == clip_name]
    if len(clips) != 1 or clips[0] not in browser_clips:
        raise ValueError("Expected exactly one event browser asset-clip")
    clip = clips[0]
    resources = {}
    for resource in root.findall("./resources/*"):
        key = resource.attrib["id"]
        if key in resources:
            raise ValueError("Duplicate resource ID")
        resources[key] = resource
    asset = resources[clip.attrib["ref"]]
    if asset.tag != "asset":
        raise ValueError("Invalid asset reference")
    clip_format = read_format(resources, clip.attrib["format"])
    # Final Cut can split the original shared format into distinct asset and
    # browser-clip formats (observed with rotated anamorphic media). Checking
    # only the clip hides changes to the underlying source interpretation.
    asset_format = read_format(resources, asset.attrib["format"])
    rate = Fraction(clip_format["frameDuration"])
    start = seconds(clip.get("start", "0s"))
    markers = []
    for marker in clip.findall("marker"):
        frame = (seconds(marker.attrib["start"]) - start) / rate
        duration = seconds(marker.attrib["duration"]) / rate
        if frame.denominator != 1 or duration.denominator != 1 or frame < 0 or duration <= 0:
            raise ValueError("Markers must have integral nonnegative positions and positive frame durations")
        markers.append((int(frame), int(duration), marker.attrib["value"], marker.get("note", "")))
    marker_scope = root if clip_name is None else clip
    if not markers or len(markers) != len(marker_scope.findall(".//marker")):
        raise ValueError("Expected nonempty markers belonging only to the browser clip")
    media = asset.findall("media-rep[@kind='original-media']")
    if len(media) != 1:
        raise ValueError("Expected one original-media reference")
    durations = [seconds(clip.attrib["duration"]), seconds(asset.attrib["duration"])]
    if min(durations) <= 0:
        raise ValueError("Clip and asset durations must be positive")
    return dict(sha256=hashlib.sha256(data).hexdigest(), version=root.get("version"),
                **clip_format, assetRaster=asset_format["raster"],
                assetPixelAspect=asset_format["pixelAspect"],
                assetFrameDuration=asset_format["frameDuration"],
                start=str(start), assetStart=str(seconds(asset.get("start", "0s"))),
                durations=list(map(str, durations)), timecodeFormat=clip.attrib["tcFormat"],
                sourceURL=media[0].attrib["src"], markers=markers)


def media_path(url):
    parsed = urlsplit(url)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost") or parsed.query or parsed.fragment:
        raise ValueError("Media verification requires local file URLs")
    path = Path(unquote(parsed.path))
    if not path.is_absolute():
        raise ValueError("Media path must be absolute")
    return path


def compare(original, returned, verify_media=False, returned_clip_name=None):
    before, after = read_export(original), read_export(returned, returned_clip_name)
    checks = {key: before[key] == after[key] for key in
              ("raster", "pixelAspect", "frameDuration", "assetRaster", "assetPixelAspect",
               "assetFrameDuration", "start", "assetStart", "durations", "timecodeFormat")}
    checks["markerTimingAndTitles"] = Counter(m[:3] for m in before["markers"]) == Counter(m[:3] for m in after["markers"])
    checks["exactMarkerContent"] = Counter(before["markers"]) == Counter(after["markers"])
    def normalized(markers):
        return Counter((*m[:3], m[3].translate(str.maketrans("\t\r\n", "   "))) for m in markers)
    normalized_match = normalized(before["markers"]) == normalized(after["markers"])
    if verify_media:
        before["mediaSHA256"] = digest(media_path(before["sourceURL"]))
        after["mediaSHA256"] = digest(media_path(after["sourceURL"]))
        checks["sourceMediaBytes"] = before["mediaSHA256"] == after["mediaSHA256"]
    return dict(status="exact-match" if all(checks.values()) else "differences",
                scope="Single browser clip XML comparison; not complete editor acceptance",
                returnedClipName=returned_clip_name,
                mediaIdentityVerified=verify_media and checks["sourceMediaBytes"],
                checks=checks, contentMatchesAfterAttributeWhitespaceNormalization=normalized_match,
                original=before, returned=after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("returned", type=Path)
    parser.add_argument("--verify-media", action="store_true")
    parser.add_argument("--returned-clip-name",
                        help="Select one exact, unique event browser clip in the returned XML; "
                             "other browser clips and project timelines are outside comparison scope")
    args = parser.parse_args()
    try:
        report = compare(args.original, args.returned, args.verify_media, args.returned_clip_name)
    except (ValueError, KeyError, OSError, ET.ParseError, ZeroDivisionError) as error:
        print(json.dumps({"status": "invalid", "error": str(error)}))
        return 2
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report["status"] == "exact-match" else 1


if __name__ == "__main__":
    raise SystemExit(main())
