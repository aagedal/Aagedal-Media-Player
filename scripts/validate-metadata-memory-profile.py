#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate the complete paired metadata-memory workload before accepting parity."""
import json
import math
from pathlib import Path
import sys


def integer(value, label, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError(f"Invalid {label}: {value}")
    return value


def finite_json(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("Non-finite metadata value")
    if isinstance(value, dict):
        for item in value.values():
            finite_json(item)
    elif isinstance(value, list):
        for item in value:
            finite_json(item)


def nullable_number(value, label):
    if value is not None and (type(value) not in (int, float) or not math.isfinite(value) or value < 0):
        raise ValueError(f"Invalid {label}: {value}")


def nullable_string(value, label):
    if value is not None and not isinstance(value, str):
        raise ValueError(f"Invalid {label}: {value}")


def same_json(left, right):
    # Python equality treats False as 0 and True as 1; JSON provenance must not.
    return json.dumps(left, sort_keys=True, allow_nan=False) == json.dumps(right, sort_keys=True, allow_nan=False)


def validate(records, inputs):
    if not inputs or any(not isinstance(path, str) or not path for path in inputs) or len(set(inputs)) != len(inputs):
        raise ValueError("Expected distinct input paths")
    expected = {(variant, path, mode) for variant in ("baseline", "fixed")
                for path in inputs for mode in ("read", "rtmd", "skip-mdat")}
    workloads = {}
    for record in records:
        key = (record["variant"], record["input"], record["mode"])
        if key not in expected or key in workloads:
            raise ValueError(f"Unexpected or duplicate workload: {key}")
        workloads[key] = record
        mode = record["mode"]
        phases = record["phases"]
        sequence = ["initial", "retained", "released"] if mode == "read" else ["initial", "mapped", "probed", "released"]
        if [phase["phase"] for phase in phases] != sequence:
            raise ValueError(f"Invalid phase sequence: {key}")
        previous_peak = 0
        for phase in phases:
            resident = integer(phase["residentBytes"], "resident memory", 1)
            peak = integer(phase["lifetimePeakResidentBytes"], "peak memory", 1)
            if peak < resident or peak < previous_peak:
                raise ValueError(f"Inconsistent lifetime peak: {key}")
            previous_peak = peak
        wall = phases[-1]["wallSeconds"]
        if type(wall) not in (int, float) or not math.isfinite(wall) or wall <= 0:
            raise ValueError(f"Invalid wall time: {key}")
        result = phases[1 if mode == "read" else 2]
        if mode == "read":
            snapshot = result["metadata"]
            required = {"format", "duration", "fileSize", "bitRate", "title", "comment",
                        "videoStreamCount", "subtitleStreamCount", "chapterCount", "hasRTMD", "audioStreams"}
            if not isinstance(snapshot, dict) or not required.issubset(snapshot):
                raise ValueError("Incomplete metadata snapshot")
            if not isinstance(snapshot["format"], str) or not snapshot["format"] or type(snapshot["hasRTMD"]) is not bool:
                raise ValueError("Invalid metadata format or RTMD presence")
            for field in ("videoStreamCount", "subtitleStreamCount", "chapterCount"):
                integer(snapshot[field], field)
            for field in ("duration", "bitRate"):
                nullable_number(snapshot[field], field)
            if snapshot["fileSize"] is not None:
                integer(snapshot["fileSize"], "file size")
            for field in ("title", "comment"):
                nullable_string(snapshot[field], field)
            if not isinstance(snapshot["audioStreams"], list):
                raise ValueError("Invalid audio snapshot")
            for stream in snapshot["audioStreams"]:
                if not isinstance(stream, dict) or not {"codec", "sampleRate", "channels", "bitDepth", "duration", "bitRate", "channelLayout"}.issubset(stream):
                    raise ValueError("Incomplete audio snapshot")
                for field in ("codec", "channelLayout"):
                    nullable_string(stream[field], field)
                for field in ("sampleRate", "duration", "bitRate"):
                    nullable_number(stream[field], field)
                for field in ("channels", "bitDepth"):
                    if stream[field] is not None:
                        integer(stream[field], field)
            finite_json(snapshot)
        elif mode == "rtmd":
            if type(result["hasRTMD"]) is not bool:
                raise ValueError("Invalid RTMD presence")
        else:
            if not isinstance(result["boxTypes"], list) or any(not isinstance(box, str) or len(box) != 4 for box in result["boxTypes"]):
                raise ValueError("Invalid box types")
            integer(result["payloadBytes"], "box payload bytes")
    if set(workloads) != expected:
        raise ValueError("Incomplete paired workload matrix")
    for path in inputs:
        for mode, index, fields in (("read", 1, ("metadata",)), ("rtmd", 2, ("hasRTMD",)),
                                    ("skip-mdat", 2, ("boxTypes", "payloadBytes"))):
            left = workloads[("baseline", path, mode)]["phases"][index]
            right = workloads[("fixed", path, mode)]["phases"][index]
            if any(not same_json(left[field], right[field]) for field in fields):
                raise ValueError(f"{mode} parity mismatch: {path}")


def main():
    if len(sys.argv) != 2:
        raise ValueError("Usage: validate-metadata-memory-profile.py ARTIFACT_DIRECTORY")
    root = Path(sys.argv[1])
    environment = json.loads((root / "environment.json").read_text())
    inputs = [item["path"] for item in environment["inputs"]]
    records = []
    for variant in ("baseline", "fixed"):
        for index, path in enumerate(inputs):
            for mode in ("read", "rtmd", "skip-mdat"):
                phases = [json.loads(line) for line in (root / variant / f"input-{index}-{mode}.jsonl").read_text().splitlines()]
                records.append({"variant": variant, "input": path, "mode": mode, "phases": phases})
    validate(records, inputs)
    summary = json.loads((root / "summary.json").read_text())
    if summary.get("snapshotParity") is not True or not same_json(summary.get("records"), records):
        raise ValueError("Summary does not match raw paired records")
    print(f"Validated {len(records)} metadata-memory workloads and paired parity")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as error:
        sys.exit(f"Invalid metadata-memory profile: {error}")
