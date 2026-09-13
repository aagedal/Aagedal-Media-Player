#!/usr/bin/env python3
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

"""Fail-closed validation for a release-candidate XCTest result bundle export."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterator


ALLOWED_SKIPPED_TESTS = {
    "CompareReviewDiskFullTests/testRealVolumeExhaustionPreservesSidecarAndAllowsRetry()",
    "ITUProgrammeLoudnessTests/testOfficialProgrammeReferencesWhenRequested()",
    "ITUSevenPointOneLoudnessTests/testOfficialEightChannelReferenceWhenRequested()",
    "LoudnessPerformanceTests/testProductionLoudnessProfileWhenRequested()",
    "ProductionMetadataMemoryPerformanceTests/testProductionMetadataMemoryProfileWhenRequested()",
    "ProgrammeLoudnessPerformanceTests/testProductionProgrammeLoudnessProfileWhenRequested()",
    "TimelineThumbnailLoaderTests/testProductionThumbnailProfileWhenRequested()",
}


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read valid JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return value


def exact_nonnegative_integer(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{field} must be a non-negative integer")
    return value


def child_objects(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from child_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from child_objects(child)


def validate(
    summary: dict[str, Any],
    tests: dict[str, Any],
    minimum_tests: int,
    required_tests: set[str] | frozenset[str] = frozenset(),
    exact_tests: int | None = None,
) -> tuple[int, int]:
    if summary.get("result") != "Passed":
        raise ValueError(f"test result is {summary.get('result')!r}, not 'Passed'")

    total = exact_nonnegative_integer(summary.get("totalTestCount"), "totalTestCount")
    passed = exact_nonnegative_integer(summary.get("passedTests"), "passedTests")
    failed = exact_nonnegative_integer(summary.get("failedTests"), "failedTests")
    skipped = exact_nonnegative_integer(summary.get("skippedTests"), "skippedTests")
    expected_failures = exact_nonnegative_integer(
        summary.get("expectedFailures"), "expectedFailures"
    )
    if failed != 0 or expected_failures != 0:
        raise ValueError(
            f"release tests include {failed} failures and {expected_failures} expected failures"
        )
    if total != passed + failed + skipped + expected_failures:
        raise ValueError("test summary counts do not add up")
    if total < minimum_tests:
        raise ValueError(
            f"only {total} tests ran; the release floor requires at least {minimum_tests}"
        )
    if exact_tests is not None and total != exact_tests:
        raise ValueError(f"expected exactly {exact_tests} tests, but {total} ran")

    warnings = summary.get("runtimeWarnings")
    if not isinstance(warnings, list):
        raise ValueError("runtimeWarnings must be present as an array")
    if warnings:
        raise ValueError(f"release tests reported {len(warnings)} runtime warning(s)")

    configurations = summary.get("devicesAndConfigurations")
    if not isinstance(configurations, list) or not configurations:
        raise ValueError("test summary contains no device/configuration result")
    for index, configuration in enumerate(configurations):
        if not isinstance(configuration, dict):
            raise ValueError(f"device/configuration result {index} is malformed")
        if exact_nonnegative_integer(
            configuration.get("failedTests"), f"configuration {index} failedTests"
        ) != 0:
            raise ValueError(f"device/configuration result {index} contains failures")
        if exact_nonnegative_integer(
            configuration.get("expectedFailures"),
            f"configuration {index} expectedFailures",
        ) != 0:
            raise ValueError(f"device/configuration result {index} contains expected failures")

    allowed_results = {"Passed", "Failed", "Skipped", "Expected Failure"}
    test_case_results: dict[str, str] = {}
    skipped_cases: dict[str, dict[str, Any]] = {}
    for node in child_objects(tests):
        if node.get("nodeType") != "Test Case":
            continue
        identifier = node.get("nodeIdentifier")
        if not isinstance(identifier, str) or not identifier:
            raise ValueError("a test case has no nodeIdentifier")
        result = node.get("result")
        if not isinstance(result, str) or not result:
            raise ValueError(f"test case has no result: {identifier}")
        if result not in allowed_results:
            raise ValueError(f"test case has unknown result {result!r}: {identifier}")
        if identifier in test_case_results:
            raise ValueError(f"test case appears more than once: {identifier}")
        test_case_results[identifier] = result
        if result != "Skipped":
            continue
        skipped_cases[identifier] = node

    missing_required = sorted(required_tests - set(test_case_results))
    if missing_required:
        raise ValueError("required tests did not run: " + ", ".join(missing_required))
    nonpassing_required = sorted(
        identifier for identifier in required_tests
        if test_case_results.get(identifier) != "Passed"
    )
    if nonpassing_required:
        raise ValueError("required tests did not pass: " + ", ".join(nonpassing_required))

    detailed_counts = {
        result: sum(case_result == result for case_result in test_case_results.values())
        for result in allowed_results
    }
    if len(test_case_results) != total:
        raise ValueError(
            f"summary reports {total} total tests, but details contain "
            f"{len(test_case_results)} test cases"
        )
    expected_detail_counts = {
        "Passed": passed,
        "Failed": failed,
        "Skipped": skipped,
        "Expected Failure": expected_failures,
    }
    for result, expected_count in expected_detail_counts.items():
        if detailed_counts[result] != expected_count:
            raise ValueError(
                f"summary reports {expected_count} {result.lower()} tests, but details "
                f"contain {detailed_counts[result]}"
            )

    if len(skipped_cases) != skipped:
        raise ValueError(
            f"summary reports {skipped} skipped tests, but details contain {len(skipped_cases)}"
        )
    unexpected = sorted(set(skipped_cases) - ALLOWED_SKIPPED_TESTS)
    if unexpected:
        raise ValueError("unexpected skipped tests: " + ", ".join(unexpected))

    for identifier, node in skipped_cases.items():
        children = node.get("children")
        messages = [
            child.get("name")
            for child in children if isinstance(child, dict)
            and child.get("nodeType") == "Skip Message"
        ] if isinstance(children, list) else []
        if not any(
            isinstance(message, str) and message.startswith("Test skipped - ")
            and len(message) > len("Test skipped - ")
            for message in messages
        ):
            raise ValueError(f"skipped test has no descriptive skip reason: {identifier}")

    return total, skipped


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("summary", type=Path)
    parser.add_argument("tests", type=Path)
    parser.add_argument("--minimum-tests", type=int, required=True)
    parser.add_argument("--exact-tests", type=int)
    parser.add_argument("--require-test", action="append", default=[])
    arguments = parser.parse_args()
    if arguments.minimum_tests < 1:
        parser.error("--minimum-tests must be positive")
    if arguments.exact_tests is not None:
        if arguments.exact_tests < 1:
            parser.error("--exact-tests must be positive")
        if arguments.exact_tests < arguments.minimum_tests:
            parser.error("--exact-tests cannot be below --minimum-tests")
    return arguments


def main() -> None:
    arguments = parse_arguments()
    try:
        total, skipped = validate(
            load_object(arguments.summary),
            load_object(arguments.tests),
            arguments.minimum_tests,
            set(arguments.require_test),
            arguments.exact_tests,
        )
    except ValueError as error:
        raise SystemExit(f"ERROR: {error}") from error
    print(
        f"PASS: release XCTest evidence contains {total} tests, "
        f"{skipped} allowlisted explicit skip(s), and no runtime warnings"
    )


if __name__ == "__main__":
    main()
