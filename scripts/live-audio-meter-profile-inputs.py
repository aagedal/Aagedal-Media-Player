#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Capture explicit file/FFmpeg audio-order requests for the production profile."""

import hashlib
import json
from pathlib import Path
import re
import sys


def capture(arguments):
    manifest = []
    identities = set()
    index = 0
    while index < len(arguments):
        ordinal = 0
        explicit = arguments[index] == "--audio-stream-order"
        if explicit:
            if index + 2 >= len(arguments) or not re.fullmatch(r"[0-9]+", arguments[index + 1]):
                raise ValueError("--audio-stream-order requires a non-negative integer and a media file")
            ordinal = int(arguments[index + 1])
            index += 2
        path = Path(arguments[index]).expanduser().resolve()
        if not path.is_file():
            raise ValueError(f"Media file does not exist: {path}")
        identity = (path, ordinal)
        if identity in identities:
            raise ValueError(f"Duplicate file/audio-stream request: {path}, audio stream {ordinal}")
        identities.add(identity)
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
        manifest.append({
            "path": str(path),
            "sha256": digest.hexdigest(),
            "audioStreamOrderIndex": ordinal,
            "audioTrackSelectionExplicit": explicit,
        })
        index += 1
    if not manifest:
        raise ValueError("At least one media file is required")
    return manifest


if __name__ == "__main__":
    try:
        print(json.dumps(capture(sys.argv[1:]), indent=2))
    except (ValueError, OSError) as error:
        raise SystemExit(f"Invalid live audio meter inputs: {error}") from error
