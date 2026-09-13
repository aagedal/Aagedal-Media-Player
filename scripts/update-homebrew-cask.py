#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import argparse
from pathlib import Path
import re


def updated_cask(source: str, version: str, sha256: str) -> str:
    patterns = (
        (re.compile(r'(?m)^([ \t]*version[ \t]+)"[^"\n]*"([ \t]*(?:#.*)?)$'), version, "version"),
        (re.compile(r'(?m)^([ \t]*sha256[ \t]+)"[^"\n]*"([ \t]*(?:#.*)?)$'), sha256, "sha256"),
    )
    result = source
    for pattern, value, label in patterns:
        result, count = pattern.subn(
            lambda match: f'{match.group(1)}"{value}"{match.group(2)}', result
        )
        if count != 1:
            raise ValueError(f"expected exactly one {label} declaration, found {count}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Update one Homebrew cask version and SHA-256.")
    parser.add_argument("cask", type=Path)
    parser.add_argument("version")
    parser.add_argument("sha256")
    arguments = parser.parse_args()
    if re.fullmatch(r"[0-9a-f]{64}", arguments.sha256) is None:
        parser.error("sha256 must be 64 lowercase hexadecimal characters")
    try:
        source = arguments.cask.read_text()
        result = updated_cask(source, arguments.version, arguments.sha256)
        arguments.cask.write_text(result)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
