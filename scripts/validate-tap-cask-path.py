#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

"""Resolve a Homebrew cask path without allowing writes outside its tap."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def validate(tap: Path, cask_name: str) -> Path:
    tap = tap.resolve(strict=True)
    if not tap.is_dir():
        raise ValueError(f"Homebrew tap is not a directory: {tap}")

    name = Path(cask_name)
    if name.is_absolute() or not cask_name or ".." in name.parts:
        raise ValueError("TAP_CASK_FILE must be a relative path inside the tap")

    git_root = subprocess.run(
        ["git", "-C", str(tap), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    if Path(git_root).resolve() != tap:
        raise ValueError("TAP_LOCAL_PATH must be the root of the Homebrew tap checkout")

    cask = (tap / name).resolve(strict=True)
    if not cask.is_file() or os.path.commonpath((tap, cask)) != str(tap):
        raise ValueError("TAP_CASK_FILE must resolve to a file inside the tap")
    if cask != tap / name:
        raise ValueError("TAP_CASK_FILE must not traverse a symlink")

    tracked = subprocess.run(
        ["git", "-C", str(tap), "ls-files", "--cached", "--full-name", "-z", "--", name.as_posix()],
        capture_output=True, check=True,
    ).stdout.split(b"\0")
    if os.fsencode(name.as_posix()) not in tracked:
        raise ValueError("TAP_CASK_FILE must name a tracked file in the tap")
    return cask


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: validate-tap-cask-path.py TAP_LOCAL_PATH TAP_CASK_FILE")
    try:
        print(validate(Path(sys.argv[1]), sys.argv[2]))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"ERROR: invalid Homebrew tap cask path: {error}") from error
