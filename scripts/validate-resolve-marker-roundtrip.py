#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare an app marker EDL with Resolve's native marker re-export.

This verifies the supplied files, not the editor workflow or source-media identity.
Keep those records alongside the generated report. Never filter unwanted events
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("returned", type=Path)
    parser.add_argument("--rate", required=True, help="Exact rational rate, e.g. 30000/1001")
    parser.add_argument("--editor-version", required=True)
    parser.add_argument("--output", type=Path, required=True, help="New JSON evidence file")
    args = parser.parse_args()
    try:
        rate = Fraction(args.rate)
        original, returned = args.original.read_bytes(), args.returned.read_bytes()
        result = compare(original.decode("utf-8-sig"), returned.decode("utf-8-sig"), rate)
        result.update(rate=str(rate), editorVersion=args.editor_version,
                      originalSHA256=hashlib.sha256(original).hexdigest(),
                      returnedSHA256=hashlib.sha256(returned).hexdigest(),
                      scope="Supplied EDL comparison only; native import and media identity require separate evidence")
        with args.output.open("x") as output:
            json.dump(result, output, ensure_ascii=False, indent=2)
            output.write("\n")
        print(f"{result['status']}: {result['expectedCount']} expected, {result['actualCount']} returned; {args.output}")
        return 0 if result["status"] == "passed" else 1
    except (ValueError, OSError, ZeroDivisionError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
