#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("release.sh")
VERIFY_SCRIPT = Path(__file__).with_name("verify-release-candidate.sh")


class ReleaseScriptValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = SCRIPT.read_text()

    def test_dirty_guard_precedes_toolchain_preflight_and_build_removal(self) -> None:
        guard = self.source.index('git status --porcelain')
        self.assertLess(guard, self.source.index("# Toolchain resolution"))
        self.assertLess(guard, self.source.index("python3 scripts/release-preflight.py"))
        self.assertLess(guard, self.source.index('rm -rf "$BUILD_DIR"'))

    def test_dirty_checkout_stops_before_toolchain_execution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary_directory = root / "bin"
            binary_directory.mkdir()
            trace = root / "trace.log"
            self.make_executable(
                binary_directory / "git",
                """#!/bin/sh
printf 'git %s\\n' "$*" >> "$RELEASE_TEST_TRACE"
if [ "$*" = "status --porcelain" ]; then
    printf ' M deliberately-dirty\\n'
    exit 0
fi
exit 90
""",
            )
            self.make_executable(
                binary_directory / "xcrun",
                """#!/bin/sh
printf 'xcrun %s\\n' "$*" >> "$RELEASE_TEST_TRACE"
exit 91
""",
            )
            environment = os.environ.copy()
            environment["PATH"] = f"{binary_directory}:/usr/bin:/bin"
            environment["RELEASE_TEST_TRACE"] = str(trace)
            result = subprocess.run(
                ["/bin/bash", str(SCRIPT)],
                cwd=root,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 2)
            self.assertIn("release requires a clean checkout", result.stderr)
            self.assertEqual(trace.read_text(), "git status --porcelain\n")

    def test_git_status_failure_stops_release_and_candidate_verification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary_directory = root / "bin"
            binary_directory.mkdir()
            trace = root / "trace.log"
            self.make_executable(
                binary_directory / "git",
                """#!/bin/sh
printf 'git %s\\n' "$*" >> "$RELEASE_TEST_TRACE"
exit 88
""",
            )
            self.make_executable(
                binary_directory / "xcrun",
                """#!/bin/sh
printf 'xcrun %s\\n' "$*" >> "$RELEASE_TEST_TRACE"
exit 91
""",
            )
            environment = os.environ.copy()
            environment["PATH"] = f"{binary_directory}:/usr/bin:/bin"
            environment["RELEASE_TEST_TRACE"] = str(trace)

            cases = [
                (SCRIPT, []),
                (VERIFY_SCRIPT, [str(root / "candidate-evidence")]),
            ]
            for script, arguments in cases:
                trace.write_text("")
                result = subprocess.run(
                    ["/bin/bash", str(script), *arguments],
                    cwd=root,
                    env=environment,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2, script.name)
                self.assertIn("could not inspect", result.stderr, script.name)
                self.assertEqual(trace.read_text(), "git status --porcelain\n", script.name)

    def test_source_commit_is_full_validated_and_reported(self) -> None:
        capture = self.source.index('SOURCE_COMMIT="$(git rev-parse --verify HEAD)"')
        validation = self.source.index('"$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$')
        report = self.source.index('echo "==> Source commit: $SOURCE_COMMIT"')
        self.assertLess(capture, validation)
        self.assertLess(validation, report)
        self.assertLess(report, self.source.index("# Toolchain resolution"))

    def test_new_github_release_targets_captured_commit(self) -> None:
        self.assertIn('--target "$SOURCE_COMMIT"', self.source)
        self.assertNotIn("--target main", self.source)

    @staticmethod
    def make_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)


if __name__ == "__main__":
    unittest.main()
