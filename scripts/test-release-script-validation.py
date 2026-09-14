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

    def test_publication_requires_authenticated_verified_github_release(self) -> None:
        auth_guard = self.source.index('GitHub CLI is unavailable or unauthenticated')
        identity_function = self.source.index('verify_release_identity()')
        commit_guard = self.source.index('"$published_source_commit" == "$SOURCE_COMMIT"')
        draft_guard = self.source.index('"$release_is_draft" == "false"')
        prerelease_guard = self.source.index('"$release_is_prerelease" == "false"')
        pre_upload_guard = self.source.index('    verify_release_identity', identity_function)
        upload = self.source.index('gh release upload')
        asset_guard = self.source.index('python3 scripts/validate-github-release-asset.py')
        appcast_publish = self.source.index('mv "$PENDING_APPCAST" "$APPCAST"')
        self.assertLess(auth_guard, identity_function)
        self.assertLess(identity_function, commit_guard)
        self.assertLess(commit_guard, draft_guard)
        self.assertLess(draft_guard, prerelease_guard)
        self.assertLess(draft_guard, pre_upload_guard)
        self.assertLess(pre_upload_guard, upload)
        self.assertLess(draft_guard, asset_guard)
        self.assertLess(asset_guard, appcast_publish)
        self.assertNotIn('skipping upload', self.source)
        self.assertIn('"$RELEASE_ZIP_NAME" "$ZIP_SIZE" "$ZIP_SHA256"', self.source)

    def test_automated_tap_update_requires_clean_checkout_and_exact_rewrite(self) -> None:
        tap_guard = self.source.index('verify_tap_checkout()')
        early_guard = self.source.index('    verify_tap_checkout', tap_guard)
        upload = self.source.index('gh release upload')
        late_guard = self.source.index('    verify_tap_checkout', early_guard + 1)
        pull = self.source.index('git pull --rebase --quiet')
        rewrite = self.source.index('python3 scripts/update-homebrew-cask.py')
        commit = self.source.index('git commit -m "$TAP_CASK_NAME $MARKETING_VERSION"')
        self.assertLess(tap_guard, early_guard)
        self.assertLess(early_guard, upload)
        self.assertLess(upload, late_guard)
        self.assertLess(late_guard, pull)
        self.assertLess(pull, rewrite)
        self.assertLess(rewrite, commit)

    def test_candidate_verifier_fail_closes_on_test_evidence(self) -> None:
        source = VERIFY_SCRIPT.read_text()
        tests = source.index('xcodebuild test \\')
        summary = source.index('xcresulttool get test-results summary')
        details = source.index('xcresulttool get test-results tests')
        validation = source.index('python3 scripts/validate-release-xcresult.py')
        analysis = source.index('xcodebuild analyze \\')
        self.assertLess(tests, summary)
        self.assertLess(summary, details)
        self.assertLess(details, validation)
        self.assertLess(validation, analysis)
        self.assertIn('--minimum-tests 683', source)
        self.assertIn('-parallel-testing-enabled NO', source)
        self.assertEqual(source.count('-skip-testing:'), 2)
        focused = source.index('echo "==> Focused mixed-backend transport repeat"')
        focused_validation = source.index('mixed-backend-transport-validation.log')
        self.assertLess(validation, focused)
        self.assertLess(focused, focused_validation)
        self.assertLess(focused_validation, analysis)
        self.assertIn('testAVFoundationPrimaryAndMPVSecondaryShareTransport', source)
        self.assertIn('testMPVPrimaryAndAVFoundationSecondaryShareTransport', source)
        self.assertEqual(source.count('--require-test'), 2)
        self.assertIn('os.path.realpath', source)
        self.assertIn('candidate evidence must be written outside the source checkout', source)
        self.assertIn('HEAD changed during candidate verification', source)
        self.assertIn('Package.resolved changed during candidate verification', source)
        self.assertIn('checkout changed during candidate verification', source)

    def test_release_version_is_bound_to_committed_project_metadata(self) -> None:
        settings = self.source.index('BUILD_SETTINGS=$(xcodebuild')
        project_version = self.source.index('PROJECT_MARKETING_VERSION=')
        requested_version = self.source.index('MARKETING_VERSION="${1:-$PROJECT_MARKETING_VERSION}"')
        mismatch_guard = self.source.index('release version/build must match the committed project metadata')
        preflight = self.source.index('python3 scripts/release-preflight.py')
        archive = self.source.index('xcodebuild archive \\')
        self.assertLess(settings, project_version)
        self.assertLess(project_version, requested_version)
        self.assertLess(requested_version, mismatch_guard)
        self.assertLess(mismatch_guard, preflight)
        self.assertLess(mismatch_guard, archive)
        self.assertIn('if [[ $# -gt 2 ]]', self.source)

    def test_release_requires_matching_canonical_candidate_evidence(self) -> None:
        evidence = self.source.index('CANDIDATE_EVIDENCE_DIR="${CANDIDATE_EVIDENCE_DIR:-}"')
        status = self.source.index('EVIDENCE_STATUS=')
        source_match = self.source.index('"$EVIDENCE_SOURCE_COMMIT" != "$SOURCE_COMMIT"')
        package_match = self.source.index('"$EVIDENCE_PACKAGE_SHA256" != "$CURRENT_PACKAGE_SHA256"')
        result_validation = self.source.index('python3 scripts/validate-release-xcresult.py')
        preflight = self.source.index('python3 scripts/release-preflight.py')
        archive = self.source.index('xcodebuild archive \\')
        self.assertLess(evidence, status)
        self.assertLess(status, source_match)
        self.assertLess(source_match, package_match)
        self.assertLess(package_match, result_validation)
        self.assertLess(result_validation, preflight)
        self.assertLess(result_validation, archive)
        self.assertIn('--minimum-tests 683', self.source)
        self.assertEqual(self.source.count('--require-test'), 2)

    @staticmethod
    def make_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)


if __name__ == "__main__":
    unittest.main()
