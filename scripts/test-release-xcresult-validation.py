#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("validate-release-xcresult.py")
SPEC = importlib.util.spec_from_file_location("validate_release_xcresult", SCRIPT)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class ReleaseXCResultValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.allowed = sorted(VALIDATOR.ALLOWED_SKIPPED_TESTS)[0]
        self.summary = {
            "result": "Passed",
            "totalTestCount": 662,
            "passedTests": 661,
            "failedTests": 0,
            "skippedTests": 1,
            "expectedFailures": 0,
            "runtimeWarnings": [],
            "devicesAndConfigurations": [
                {"failedTests": 0, "expectedFailures": 0}
            ],
        }
        self.tests = {
            "children": [
                {
                    "nodeType": "Test Case",
                    "result": "Skipped",
                    "nodeIdentifier": self.allowed,
                    "children": [
                        {
                            "nodeType": "Skip Message",
                            "name": "Test skipped - Requires an explicit external input",
                        }
                    ],
                }
            ]
        }

    def validate(self) -> tuple[int, int]:
        return VALIDATOR.validate(self.summary, self.tests, minimum_tests=662)

    def test_accepts_allowlisted_descriptive_skip(self) -> None:
        self.assertEqual(self.validate(), (662, 1))

    def test_accepts_no_skips_when_optional_inputs_are_supplied(self) -> None:
        self.summary["passedTests"] = 662
        self.summary["skippedTests"] = 0
        self.tests["children"] = []
        self.assertEqual(self.validate(), (662, 0))

    def test_rejects_unexpected_skip(self) -> None:
        self.tests["children"][0]["nodeIdentifier"] = "UnexpectedTests/testSilentSkip()"
        with self.assertRaisesRegex(ValueError, "unexpected skipped tests"):
            self.validate()

    def test_rejects_missing_skip_reason(self) -> None:
        self.tests["children"][0]["children"] = []
        with self.assertRaisesRegex(ValueError, "no descriptive skip reason"):
            self.validate()

    def test_rejects_skip_count_mismatch(self) -> None:
        self.summary["skippedTests"] = 0
        self.summary["passedTests"] = 662
        with self.assertRaisesRegex(ValueError, "details contain 1"):
            self.validate()

    def test_rejects_test_count_below_release_floor(self) -> None:
        self.summary["totalTestCount"] = 661
        self.summary["passedTests"] = 660
        with self.assertRaisesRegex(ValueError, "at least 662"):
            self.validate()

    def test_rejects_runtime_warning(self) -> None:
        self.summary["runtimeWarnings"] = [{"message": "Thread warning"}]
        with self.assertRaisesRegex(ValueError, "runtime warning"):
            self.validate()

    def test_rejects_expected_failure(self) -> None:
        self.summary["expectedFailures"] = 1
        self.summary["passedTests"] = 660
        self.summary["devicesAndConfigurations"][0]["expectedFailures"] = 1
        with self.assertRaisesRegex(ValueError, "expected failures"):
            self.validate()

    def test_requires_named_test_to_run_and_pass(self) -> None:
        required = "TransportTests/testMixedBackends()"
        with self.assertRaisesRegex(ValueError, "required tests did not run"):
            VALIDATOR.validate(self.summary, self.tests, 662, {required})

        self.tests["children"].append({
            "nodeType": "Test Case",
            "result": "Passed",
            "nodeIdentifier": required,
        })
        self.summary["totalTestCount"] = 663
        self.summary["passedTests"] = 662
        self.assertEqual(
            VALIDATOR.validate(self.summary, self.tests, 662, {required}),
            (663, 1),
        )

        self.tests["children"][-1]["result"] = "Failed"
        with self.assertRaisesRegex(ValueError, "required tests did not pass"):
            VALIDATOR.validate(self.summary, self.tests, 662, {required})


if __name__ == "__main__":
    unittest.main()
