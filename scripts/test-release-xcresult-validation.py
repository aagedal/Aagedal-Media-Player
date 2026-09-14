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
        self.skipped_case = {
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
        self.tests = {
            "children": [
                {
                    "nodeType": "Test Case",
                    "result": "Passed",
                    "nodeIdentifier": f"PassingTests/testCase{index}()",
                }
                for index in range(661)
            ] + [self.skipped_case]
        }

    def validate(self) -> tuple[int, int]:
        return VALIDATOR.validate(self.summary, self.tests, minimum_tests=662)

    def test_accepts_allowlisted_descriptive_skip(self) -> None:
        self.assertEqual(self.validate(), (662, 1))

    def test_representative_live_meter_profile_is_an_allowlisted_opt_in(self) -> None:
        self.skipped_case["nodeIdentifier"] = (
            "LiveAudioMeterPerformanceTests/testRepresentativeProductionPathWhenRequested()"
        )
        self.assertEqual(self.validate(), (662, 1))

    def test_accepts_no_skips_when_optional_inputs_are_supplied(self) -> None:
        self.summary["passedTests"] = 662
        self.summary["skippedTests"] = 0
        self.skipped_case["result"] = "Passed"
        self.assertEqual(self.validate(), (662, 0))

    def test_rejects_unexpected_skip(self) -> None:
        self.skipped_case["nodeIdentifier"] = "UnexpectedTests/testSilentSkip()"
        with self.assertRaisesRegex(ValueError, "unexpected skipped tests"):
            self.validate()

    def test_rejects_missing_skip_reason(self) -> None:
        self.skipped_case["children"] = []
        with self.assertRaisesRegex(ValueError, "no descriptive skip reason"):
            self.validate()

    def test_rejects_missing_detailed_pass(self) -> None:
        self.tests["children"].pop(0)
        with self.assertRaisesRegex(ValueError, "details contain 661 test cases"):
            self.validate()

    def test_rejects_unknown_detailed_result(self) -> None:
        self.tests["children"][0]["result"] = "Unknown"
        with self.assertRaisesRegex(ValueError, "unknown result"):
            self.validate()

    def test_rejects_detailed_result_count_mismatch(self) -> None:
        self.tests["children"][0]["result"] = "Skipped"
        with self.assertRaisesRegex(ValueError, "details contain 660"):
            self.validate()

    def test_rejects_skip_count_mismatch(self) -> None:
        self.summary["skippedTests"] = 0
        self.summary["passedTests"] = 662
        with self.assertRaisesRegex(ValueError, "details contain 661"):
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

    def test_focused_evidence_requires_exactly_two_passing_tests(self) -> None:
        required = {
            "TransportTests/testPrimaryA()",
            "TransportTests/testPrimaryB()",
        }
        summary = {
            "result": "Passed",
            "totalTestCount": 2,
            "passedTests": 2,
            "failedTests": 0,
            "skippedTests": 0,
            "expectedFailures": 0,
            "runtimeWarnings": [],
            "devicesAndConfigurations": [
                {"failedTests": 0, "expectedFailures": 0}
            ],
        }
        tests = {
            "children": [
                {
                    "nodeType": "Test Case",
                    "result": "Passed",
                    "nodeIdentifier": identifier,
                }
                for identifier in sorted(required)
            ]
        }
        self.assertEqual(
            VALIDATOR.validate(summary, tests, 2, required, exact_tests=2),
            (2, 0),
        )

        summary["totalTestCount"] = 3
        summary["passedTests"] = 3
        tests["children"].append({
            "nodeType": "Test Case",
            "result": "Passed",
            "nodeIdentifier": "TransportTests/testUnexpected()",
        })
        with self.assertRaisesRegex(ValueError, "expected exactly 2 tests"):
            VALIDATOR.validate(summary, tests, 2, required, exact_tests=2)


if __name__ == "__main__":
    unittest.main()
