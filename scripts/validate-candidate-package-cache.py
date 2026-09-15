#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Require clean local SwiftPM checkouts at every committed package revision."""

import json
from pathlib import Path
import subprocess
import sys


def git(checkout: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(checkout), *arguments],
        text=True, capture_output=True, check=False,
    )
    if result.returncode:
        raise ValueError(f"cannot inspect {checkout.name}: {result.stderr.strip()}")
    return result.stdout.strip()


def validate(resolved_file: Path, cache: Path) -> list[tuple[str, str]]:
    checkouts = (cache / "checkouts").resolve(strict=True)
    if not checkouts.is_dir():
        raise ValueError("package cache has no checkouts directory")
    pins = json.loads(resolved_file.read_text())["pins"]
    if not pins:
        raise ValueError("Package.resolved has no package pins")
    result = []
    for pin in pins:
        name = pin["location"].rstrip("/").rsplit("/", 1)[-1]
        revision = pin["state"]["revision"]
        if not name or len(revision) != 40:
            raise ValueError(f"invalid package pin: {pin!r}")
        checkout = (checkouts / name).resolve(strict=True)
        if checkout.parent != checkouts or not checkout.is_dir():
            raise ValueError(f"package checkout escapes cache: {name}")
        actual = git(checkout, "rev-parse", "--verify", "HEAD")
        if actual != revision:
            raise ValueError(f"{name} checkout at {actual}, expected {revision}")
        if git(checkout, "status", "--porcelain", "--untracked-files=all"):
            raise ValueError(f"{name} checkout has local changes")
        result.append((name, revision))
    return result


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: validate-candidate-package-cache.py Package.resolved CACHE_DIR", file=sys.stderr)
        return 2
    try:
        revisions = validate(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: candidate package cache: {error}", file=sys.stderr)
        return 2
    for name, revision in revisions:
        print(f"candidate package cache: {name} {revision}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
