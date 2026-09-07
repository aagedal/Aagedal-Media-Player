#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression tests for accepting only complete pinned upstream CLI coverage."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cli_validation", Path(__file__).with_name("validate-metadata-cli.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def log_with(suites=None):
    suites = validation.EXPECTED_SUITES if suites is None else suites
    return "\n".join(f"Test Suite '{name}' passed at 2026-09-07 23:02:01.983.\n"
                     f"\t Executed {count} tests, with 0 failures (0 unexpected) in 0.1 seconds"
                     for name, count in suites.items()) + "\n"


class AcceptanceTests(unittest.TestCase):
    def test_complete_pinned_coverage(self):
        result = validation.validate_result(log_with(), 0)
        self.assertTrue(result["passed"])
        self.assertEqual(result["coverage"], {"blackBox": 28, "helpers": 22})

    def test_missing_black_box_suite_even_with_claimed_total(self):
        suites = dict(validation.EXPECTED_SUITES)
        del suites["WriteTests"]
        self.assertFalse(validation.validate_result(log_with(suites), 0)["passed"])

    def test_helpers_only(self):
        suites = {name: count for name, count in validation.EXPECTED_SUITES.items()
                  if name in validation.HELPER_SUITES}
        self.assertFalse(validation.validate_result(log_with(suites), 0)["passed"])

    def test_truncated_aggregate_summary(self):
        output = log_with().rsplit("Executed", 1)[0]
        self.assertFalse(validation.validate_result(output, 0)["passed"])

    def test_partial_suite(self):
        suites = dict(validation.EXPECTED_SUITES, WriteTests=4)
        self.assertFalse(validation.validate_result(log_with(suites), 0)["passed"])

    def test_skipped_or_failed_tests(self):
        for counts in ("1 test skipped and 0 failures", "1 failure"):
            with self.subTest(counts=counts):
                output = log_with().replace("0 failures", counts, 1)
                self.assertFalse(validation.validate_result(output, 0)["passed"])

    def test_duplicate_summary(self):
        self.assertFalse(validation.validate_result(log_with() + log_with({"WriteTests": 5}), 0)["passed"])

    def test_nonzero_exit_timeout_or_changed_sources(self):
        for arguments in ((1, False, True), (None, True, True), (0, True, True), (0, False, False)):
            with self.subTest(arguments=arguments):
                self.assertFalse(validation.validate_result(log_with(), *arguments)["passed"])

    def test_missing_or_empty_runner_output(self):
        for output in ("", "✔ Test run with 0 tests in 0 suites passed after 0.001 seconds."):
            self.assertFalse(validation.validate_result(output, 0)["passed"])


if __name__ == "__main__":
    unittest.main()
