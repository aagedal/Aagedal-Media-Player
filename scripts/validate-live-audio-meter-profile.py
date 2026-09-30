#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate representative production live-audio-meter acceptance evidence."""

import json
import hashlib
import math
from pathlib import Path
import re
import sys


SHA256 = re.compile(r"[0-9a-f]{64}")
BACKENDS = {"mpv", "avFoundation"}
TIMESTAMP_SOURCE = "ffmpeg-framecrc-v1"
NATIVE_LOGGING_MARKER = "LIVE_AUDIO_METER_NATIVE_OUTPUT_LOGGING enabled"
NATIVE_OUTPUT_ERROR = re.compile(r"\[ao(?:/[^\]]+)?\]\s+(?:error|fatal):", re.IGNORECASE)


def number(value, label, *, minimum=None, maximum=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label} must be a finite number")
    if minimum is not None and value < minimum:
        raise ValueError(f"{label} is below {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{label} exceeds {maximum}")
    return value


def integer(value, label, *, minimum=None):
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    if minimum is not None and value < minimum:
        raise ValueError(f"{label} is below {minimum}")
    return value


def text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be non-empty text")
    return value


def validate_observation(observation, sample_rate):
    if observation.get("monitorRoutingInvariant") is not True:
        raise ValueError("monitor routing was not invariant")
    integer(observation["startSourceFrame"], "observation start frame", minimum=0)
    end = integer(observation["endSourceFrame"], "observation end frame", minimum=1)
    if end <= observation["startSourceFrame"]:
        raise ValueError("observation did not advance source frames")
    integer(observation["publishedSnapshotCount"], "published snapshot count", minimum=2)
    duration = number(observation["observationSeconds"], "observation duration", minimum=5, maximum=30)
    wall = number(observation["wallSeconds"], "observation wall duration", minimum=duration)
    if end - observation["startSourceFrame"] < sample_rate * min(3, duration - 1):
        raise ValueError("observation did not retain enough paced source frames")
    latency = number(observation["firstSnapshotLatencySeconds"], "first snapshot latency", minimum=0, maximum=wall)
    interval = number(observation["maximumSnapshotIntervalSeconds"], "maximum snapshot interval", minimum=0, maximum=wall - latency)
    if interval == 0:
        raise ValueError("multiple published snapshots require a positive snapshot interval")
    number(observation["maximumAbsoluteClockDriftSeconds"], "maximum clock drift", minimum=0)
    integer(observation["clockDriftSampleCount"], "clock drift sample count", minimum=1)
    # The production worker's hard admission limit is 250 ms. Allow one source
    # sample of reporting tolerance while still failing evidence that does not
    # demonstrate the bound.
    number(
        observation["maximumDecodedAheadSeconds"], "maximum decoded-ahead interval",
        minimum=0, maximum=0.25 + 1 / sample_rate,
    )
    initial = integer(observation["initialAppResidentBytes"], "initial app RSS", minimum=1)
    peak = integer(observation["peakAppResidentBytes"], "peak app RSS", minimum=initial)
    integer(observation["peakChildResidentBytes"], "peak child RSS", minimum=1)
    if observation.get("cancellationObserved") is not True:
        raise ValueError("cancellation was not observed")
    number(observation["cancellationLatencySeconds"], "cancellation latency", minimum=0, maximum=5)
    integer(observation["childResidentBytesAfterCancellation"], "post-cancellation child RSS", minimum=0)
    if observation["childResidentBytesAfterCancellation"] != 0:
        raise ValueError("meter child remained resident after cancellation")


def validate_eof(eof, sample_rate):
    if eof.get("observed") is not True or eof.get("finalSnapshot") is not True:
        raise ValueError("complete EOF/final-snapshot evidence is required")
    start = integer(eof["startSourceFrame"], "EOF start frame", minimum=0)
    end = integer(eof["endSourceFrame"], "EOF end frame", minimum=1)
    if end <= start:
        raise ValueError("EOF segment did not advance source frames")
    integer(eof["publishedSnapshotCount"], "EOF snapshot count", minimum=1)
    number(eof["wallSeconds"], "EOF wall duration", minimum=0)
    text(eof["decoderVersion"], "decoder version")
    if eof.get("timestampSource") != TIMESTAMP_SOURCE:
        raise ValueError("unexpected timestamp provenance")
    if eof.get("timestampTimeBase") != f"1/{sample_rate}":
        raise ValueError("timestamp time base does not match the selected sample rate")
    count = integer(eof["timestampFrameCount"], "timestamp frame count", minimum=1)
    silence = integer(
        eof["syntheticInitialSilenceFrameCount"],
        "synthetic initial silence frame count",
        minimum=0,
    )
    if silence > count:
        raise ValueError("synthetic initial silence exceeds the decoded source interval")
    if count != end - start:
        raise ValueError("timestamp frame count does not match decoded source interval")
    if eof.get("dynamicRangeCompressionDisabled") is not True:
        raise ValueError("decoder dynamic-range processing was not disabled")
    if eof.get("codecNormalizationDisabled") is not True:
        raise ValueError("decoder codec normalization was not disabled")
    number(eof["maximumAbsoluteClockDriftSeconds"], "EOF maximum clock drift", minimum=0)
    integer(eof["clockDriftSampleCount"], "EOF clock drift sample count", minimum=1)
    number(
        eof["maximumDecodedAheadSeconds"], "EOF maximum decoded-ahead interval",
        minimum=0, maximum=0.25 + 1 / sample_rate,
    )
    integer(eof["peakAppResidentBytes"], "EOF peak app RSS", minimum=1)
    integer(eof["peakChildResidentBytes"], "EOF peak child RSS", minimum=1)


def validate(rows, manifest):
    if not isinstance(rows, list) or not isinstance(manifest, list) or not manifest:
        raise ValueError("profile rows and a non-empty input manifest are required")
    if len(rows) != len(manifest):
        raise ValueError(f"expected {len(manifest)} records, found {len(rows)}")
    indices = [integer(row.get("inputIndex"), "profile input index", minimum=0) for row in rows]
    if sorted(indices) != list(range(len(manifest))) or len(set(indices)) != len(indices):
        raise ValueError("profile input indexes are missing or duplicated")
    ordered = sorted(rows, key=lambda row: row["inputIndex"])
    identities = set()
    for row, expected in zip(ordered, manifest):
        if integer(row.get("schemaVersion"), "evidence schema version") != 2:
            raise ValueError("unknown evidence schema version")
        expected_path = Path(text(expected["path"], "manifest input path"))
        expected_order = integer(
            expected["audioStreamOrderIndex"], "manifest audio stream order", minimum=0
        )
        explicit = expected["audioTrackSelectionExplicit"]
        if not isinstance(explicit, bool):
            raise ValueError("manifest audio selection must be a boolean")
        identity = (expected_path.resolve(), expected_order)
        if identity in identities:
            raise ValueError("duplicate profile file/audio-stream request")
        identities.add(identity)
        expected_hash = expected["sha256"]
        if not isinstance(expected_hash, str) or not SHA256.fullmatch(expected_hash):
            raise ValueError("manifest SHA-256 is invalid")
        if not expected_path.is_file():
            raise ValueError(f"profile input is no longer a file: {expected_path}")
        digest = hashlib.sha256()
        with expected_path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != expected_hash:
            raise ValueError(f"profile input changed after manifest capture: {expected_path}")
        if row.get("file") != expected_path.name or row.get("inputSHA256") != expected_hash:
            raise ValueError("profile input identity does not match the retained manifest")
        duration = number(row["durationSeconds"], "input duration", minimum=20)
        text(row["codec"], "codec")
        layout = row["declaredChannelLayout"]
        if layout is not None and (not isinstance(layout, str) or not layout.strip()):
            raise ValueError("declared channel layout must be text or null")
        integer(row["channels"], "channels", minimum=1)
        if row["channels"] > 8:
            raise ValueError("more than eight channels are unsupported")
        rate = integer(row["sampleRate"], "sample rate", minimum=1)
        if rate not in (44_100, 48_000, 96_000):
            raise ValueError("unsupported sample rate")
        stream_index = integer(row["metadataStreamIndex"], "metadata stream index", minimum=0)
        order = integer(row["audioStreamOrderIndex"], "audio stream order", minimum=0)
        requested = integer(row["requestedAudioStreamOrderIndex"], "requested audio stream order", minimum=0)
        if requested != expected_order or order != requested:
            raise ValueError("selected audio stream does not match the retained request")
        if not isinstance(row["audioTrackSelectionExplicit"], bool) or row["audioTrackSelectionExplicit"] != explicit:
            raise ValueError("explicit audio selection does not match the retained request")
        if not explicit and requested != 0:
            raise ValueError("non-default audio stream requires deliberate selection")
        track_count = integer(row["availableAudioTrackCount"], "available audio track count", minimum=1)
        if order >= track_count:
            raise ValueError("selected audio stream exceeds available audio tracks")
        text(row["audioTrackLabel"], "selected audio track label")
        for section in ("observation", "eof"):
            section_order = integer(row[section]["audioStreamOrderIndex"], f"{section} audio stream order", minimum=0)
            section_stream = integer(row[section]["metadataStreamIndex"], f"{section} metadata stream index", minimum=0)
            if section_order != order or section_stream != stream_index:
                raise ValueError(f"{section} selected-track identity changed")
        if row.get("backend") not in BACKENDS:
            raise ValueError("unknown playback backend")
        validate_observation(row["observation"], rate)
        if duration < row["observation"]["observationSeconds"] + 10:
            raise ValueError("input duration does not preserve transport-check headroom")
        validate_eof(row["eof"], rate)
    return ordered


def attachment_rows(root):
    rows = []
    attachments = root / "attachments"
    if not attachments.is_dir():
        raise ValueError("attachments directory is missing")
    for path in attachments.rglob("*"):
        if not path.is_file():
            continue
        for line in path.read_text(errors="replace").splitlines():
            if line.startswith("LIVE_AUDIO_METER_PROFILE "):
                rows.append(json.loads(line.removeprefix("LIVE_AUDIO_METER_PROFILE ")))
    return rows


def validate_native_output_log(log, rows):
    """Reject native AO failures even when source PCM and video clocks pass.

    Driver fallback does not waive a failed initialization: this profile is an
    output regression gate, and it does not establish audible-output acceptance.
    """
    if any(row.get("backend") == "mpv" for row in rows) and NATIVE_LOGGING_MARKER not in log:
        raise ValueError("native MPV audio-output logging was not enabled; rerun with the current app")
    failures = [line.strip() for line in log.splitlines() if
                NATIVE_OUTPUT_ERROR.search(line)
                or "Audio output initialization failed" in line
                or ("[AudioConverter]" in line and "channel mapping input channel" in line
                    and "is out of range" in line)]
    if failures:
        raise ValueError("native audio output reported a failure: " + failures[0])


def main():
    root = Path(sys.argv[1])
    # Never leave a previous passing summary beside rejected evidence.
    (root / "summary.json").unlink(missing_ok=True)
    manifest = json.loads((root / "inputs.json").read_text())
    rows = validate(attachment_rows(root), manifest)
    validate_native_output_log((root / "profile.log").read_text(errors="replace"), rows)
    (root / "summary.json").write_text(json.dumps(rows, indent=2, allow_nan=False) + "\n")
    for row in rows:
        print(json.dumps(row, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, ValueError, OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Invalid live audio meter profile: {error}") from error
