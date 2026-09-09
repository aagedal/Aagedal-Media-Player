#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression checks for complete, honest upstream fixture acceptance."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("fixture_validation", Path(__file__).with_name("validate-metadata-library-fixtures.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def fixture_log(missing=frozenset()):
    lines = [f"Test Case '-[SwiftMediaMetadataTests.{name.replace('/', ' ')}]' {'skipped' if name in missing else 'passed'} (0.001 seconds)."
             for name in sorted(validation.EXPECTED_CASES)]
    for suite, count in [("CRMReaderTests", 1), ("MXFMCALabelsTests", 1), ("RealFileTests", 18),
                         ("MetadataFixtureValidationPackageTests.xctest", 20), ("Selected tests", 20)]:
        skipped = len(missing) if count == 20 else sum(name.startswith(suite + "/") for name in missing)
        lines += [f"Test Suite '{suite}' passed at 2026-09-09 01:00:00.000.",
                  f"\t Executed {count} tests, with {skipped} tests skipped and 0 failures (0 unexpected) in 0.1 (0.1) seconds"]
    return "\n".join(lines) + "\n"


class FixtureAcceptanceTests(unittest.TestCase):
    def test_complete_coverage(self):
        result = validation.validate_result(fixture_log(), 0, set())
        self.assertTrue(result["passed"])
        self.assertTrue(result["allFixturesCovered"])
        self.assertEqual(result["passedCases"], 20)

    def test_declared_absence_remains_partial(self):
        missing = {"RealFileTests/" + name for file in ["TRA03164.ARW", "TRA03164.xmp"] for name in validation.IMAGE_TESTS[file]}
        result = validation.validate_result(fixture_log(missing), 0, missing)
        self.assertTrue(result["passed"])
        self.assertFalse(result["allFixturesCovered"])
        self.assertEqual(result["passedCases"], 15)
        self.assertEqual(result["skippedCases"], sorted(missing))

    def test_missing_duplicate_unexpected_or_failed_case_rejected(self):
        lines = fixture_log().splitlines(keepends=True)
        for bad in ["".join(lines[1:]), "".join(lines + lines[:1]),
                    fixture_log() + "Test Case '-[SwiftMediaMetadataTests.ExtraTests testExtra]' passed (0.001 seconds).\n",
                    fixture_log().replace("passed (0.001", "failed (0.001", 1)]:
            with self.subTest(log=bad[:110]):
                self.assertFalse(validation.validate_result(bad, 0, set())["passed"])

    def test_unexpected_or_unfulfilled_skip_rejected(self):
        missing = {"RealFileTests/testReadARW"}
        self.assertFalse(validation.validate_result(fixture_log(missing), 0, set())["passed"])
        self.assertFalse(validation.validate_result(fixture_log(), 0, missing)["passed"])
        self.assertFalse(validation.validate_result(fixture_log(), 0, {"Unknown/testUnknown"})["passed"])

    def test_missing_duplicate_failed_or_wrong_summary_rejected(self):
        lines = fixture_log().splitlines(keepends=True)
        for bad in ["".join(lines[:-2]), "".join(lines + lines[-2:]),
                    fixture_log().replace("'Selected tests' passed", "'Selected tests' failed"),
                    fixture_log().replace("Executed 20", "Executed 19", 1),
                    fixture_log().replace("0 failures", "1 failures", 1),
                    fixture_log().replace("0 tests skipped", "1 tests skipped", 1)]:
            with self.subTest(log=bad[-220:]):
                self.assertFalse(validation.validate_result(bad, 0, set())["passed"])

    def test_process_failure_and_timeout_rejected(self):
        self.assertFalse(validation.validate_result(fixture_log(), 1, set())["passed"])
        self.assertFalse(validation.validate_result(fixture_log(), 0, set(), timed_out=True)["passed"])

    def test_empty_alternate_runner_cannot_replace_xctest(self):
        self.assertFalse(validation.validate_result("Test run with 0 tests passed after 0.001 seconds.\n", 0, set())["passed"])


if __name__ == "__main__":
    unittest.main()
