#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Measure native renders of the generated saturated-quadrant geometry fixture.

This is a geometry diagnostic, not a general image/color quality validator.
Exit 1 means measured geometry differs; exit 2 means invalid/incomplete input.
"""
import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def measure(rgb, width, height, aspect, colors, threshold=60):
    if width <= 0 or height <= 0 or len(rgb) != width * height * 3:
        raise ValueError("Expected one complete RGB24 frame")
    if not math.isfinite(aspect) or aspect <= 0:
        raise ValueError("Expected a positive display aspect")
    left, top, right, bottom = width, height, 0, 0
    count = 0
    for offset in range(0, len(rgb), 3):
        pixel = rgb[offset:offset + 3]
        if max(pixel) > 80 and max(pixel) - min(pixel) > threshold:
            y, x = divmod(offset // 3, width)
            left, top = min(left, x), min(top, y)
            right, bottom = max(right, x + 1), max(bottom, y + 1)
            count += 1
    if not count:
        raise ValueError("No saturated quadrant content found")
    w, h = right - left, bottom - top
    samples = []
    for fy, fx in ((.25, .25), (.25, .75), (.75, .25), (.75, .75)):
        x, y = left + int(w * fx), top + int(h * fy)
        r, g, b = rgb[(y * width + x) * 3:(y * width + x) * 3 + 3]
        samples.append("yellow" if min(r, g) > b + 60 else
                       "red" if r > max(g, b) + 60 else
                       "green" if g > max(r, b) + 60 else
                       "blue" if b > max(r, g) + 60 else "unknown")
    fit_w, fit_h = min(width, height * aspect), min(height, width / aspect)
    expected = [(width - fit_w) / 2, (height - fit_h) / 2,
                (width + fit_w) / 2, (height + fit_h) / 2]
    bounds = [left, top, right, bottom]
    # Distance from (w, h) to the expected-aspect line, in pixels. Measuring
    # only w - h * aspect amplifies vertical codec-edge ringing for wide
    # pictures and gives different acceptance after transposing the image.
    norm = math.hypot(1, aspect)
    aspect_error = abs(w / norm - h * (aspect / norm))
    checks = {
        "solidQuadrants": count / (w * h) >= .98,
        "orientation": samples == colors,
        "displayAspect": aspect_error <= 3,
        "fitBounds": all(abs(a - b) <= 3 for a, b in zip(bounds, expected)),
    }
    return dict(bounds=bounds, contentRaster=[w, h], margins=[left, top, width-right, height-bottom],
                expectedFitBounds=expected, aspectErrorPixels=aspect_error,
                quadrantColors=samples, checks=checks,
                rgbSHA256=hashlib.sha256(rgb).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("render", type=Path)
    parser.add_argument("--times", nargs="+", type=float, required=True)
    parser.add_argument("--aspect", type=Fraction, required=True)
    parser.add_argument("--colors", nargs=4, choices=["red", "green", "blue", "yellow"], required=True)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    args = parser.parse_args()
    try:
        before = digest(args.render)
        probe = json.loads(subprocess.check_output([args.ffprobe, "-v", "error", "-show_streams",
                                                   "-of", "json", str(args.render)], timeout=30))
        streams = [s for s in probe["streams"] if s.get("codec_type") == "video"]
        if len(streams) != 1:
            raise ValueError("Expected exactly one video stream")
        stream = streams[0]
        if stream.get("sample_aspect_ratio") != "1:1" or stream.get("side_data_list"):
            raise ValueError("Render must have square pixels and no display side data")
        duration = float(stream["duration"])
        if any(not math.isfinite(t) or t < 0 or t >= duration for t in args.times):
            raise ValueError("Sample times must be finite and inside render duration")
        frames = []
        for t in args.times:
            rgb = subprocess.check_output([args.ffmpeg, "-v", "error", "-noautorotate", "-ss", str(t),
                "-i", str(args.render), "-map", "0:v:0", "-frames:v", "1", "-pix_fmt", "rgb24",
                "-f", "rawvideo", "-"], timeout=60)
            # Check several thresholds so codec edge ringing cannot decide acceptance.
            measurements = {str(k): measure(rgb, stream["width"], stream["height"],
                           float(args.aspect), args.colors, k) for k in (40, 60, 80)}
            frames.append(dict(seconds=t, thresholds=measurements))
        if digest(args.render) != before:
            raise ValueError("Render changed during measurement")
        passed = all(all(m["checks"].values()) for f in frames for m in f["thresholds"].values())
        result = dict(status="passed" if passed else "differences", render=str(args.render.resolve()),
                      renderSHA256=before, stream=stream, expectedAspect=str(args.aspect),
                      frames=frames, decoder=subprocess.check_output([args.ffmpeg, "-version"],
                      text=True, timeout=10).splitlines()[0])
        print(json.dumps(result, indent=2))
        return 0 if passed else 1
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps(dict(status="error", error=str(error))))
        return 2


if __name__ == "__main__":
    sys.exit(main())
