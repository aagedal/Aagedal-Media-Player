#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


SHA256_PATTERN = re.compile(r"sha256:([0-9a-f]{64})")


def validate_asset(
    payload: object,
    *,
    expected_name: str,
    expected_size: int,
    expected_sha256: str,
) -> None:
    if not isinstance(payload, dict) or not isinstance(payload.get("assets"), list):
        raise ValueError("release response does not contain an assets array")

    matches = [
        asset
        for asset in payload["assets"]
        if isinstance(asset, dict) and asset.get("name") == expected_name
    ]
    if len(matches) != 1:
        raise ValueError(
            f"expected exactly one release asset named {expected_name!r}, found {len(matches)}"
        )

    asset = matches[0]
    if asset.get("state") != "uploaded":
        raise ValueError(f"release asset {expected_name!r} is not in the uploaded state")
    size = asset.get("size")
    if isinstance(size, bool) or not isinstance(size, int) or size != expected_size:
        raise ValueError(
            f"release asset {expected_name!r} has size {size!r}, expected {expected_size}"
        )

    digest = asset.get("digest")
    match = SHA256_PATTERN.fullmatch(digest) if isinstance(digest, str) else None
    if match is None:
        raise ValueError(f"release asset {expected_name!r} has no valid SHA-256 digest")
    if match.group(1) != expected_sha256:
        raise ValueError(
            f"release asset {expected_name!r} has SHA-256 {match.group(1)}, "
            f"expected {expected_sha256}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate the identity of one uploaded GitHub release asset."
    )
    parser.add_argument("release_json", type=Path)
    parser.add_argument("expected_name")
    parser.add_argument("expected_size", type=int)
    parser.add_argument("expected_sha256")
    arguments = parser.parse_args()

    if arguments.expected_size < 0:
        parser.error("expected_size must be non-negative")
    if re.fullmatch(r"[0-9a-f]{64}", arguments.expected_sha256) is None:
        parser.error("expected_sha256 must be 64 lowercase hexadecimal characters")

    try:
        payload = json.loads(arguments.release_json.read_text())
        validate_asset(
            payload,
            expected_name=arguments.expected_name,
            expected_size=arguments.expected_size,
            expected_sha256=arguments.expected_sha256,
        )
    except (OSError, json.JSONDecodeError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
