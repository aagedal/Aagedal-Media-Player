#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run unchanged upstream CLI tests against the isolated RTMD candidate, offline."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REVISION = "c2d77c2dcefcb997623e52beca57bc61ce302cb9"


# Exact inventory at REVISION: 28 black-box tests and 22 CLI helper tests.
EXPECTED_SUITES = {
    "ArgfileTests": 3, "CopyTests": 2, "DiffTests": 3,
    "Phase26DateFormatTests": 10, "Phase26GroupPrefixTests": 6,
    "Phase26TagsFromFileEndToEndTests": 2, "Phase26TagsFromFileTests": 6,
    "ReadTests": 4, "SmokeTests": 4, "StayOpenTests": 2, "StripTests": 3,
    "WriteTests": 5, "SwiftMediaMetadataPackageTests.xctest": 50,
    "Selected tests": 50,
}
HELPER_SUITES = {"Phase26DateFormatTests", "Phase26GroupPrefixTests", "Phase26TagsFromFileTests"}


def validate_result(output, code, timed_out=False, unchanged=True):
    """Require every pinned XCTest suite and both completed aggregate summaries."""
    pattern = (r"^Test Suite '([^']+)' (passed|failed) at [^\n]+\n"
               r"[ \t]*Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?[^\n]*$")
    suites = {}
    errors = []
    for name, status, executed, skipped, failed in re.findall(pattern, output, re.MULTILINE):
        if name in suites:
            errors.append(f"Duplicate suite summary: {name}")
        suites[name] = {"executed": int(executed), "skipped": int(skipped or 0), "failed": int(failed)}
        if status != "passed":
            errors.append(f"Suite did not pass: {name}")
    if set(suites) != set(EXPECTED_SUITES):
        errors.append("Missing or unexpected completed XCTest suites")
    for name, expected in EXPECTED_SUITES.items():
        if suites.get(name) != {"executed": expected, "skipped": 0, "failed": 0}:
            errors.append(f"Incomplete or unsuccessful suite: {name}")
    if code != 0:
        errors.append("Test process did not exit successfully")
    if timed_out:
        errors.append("Test process timed out")
    if not unchanged:
        errors.append("Source checkouts changed")
    helpers = sum(suites.get(name, {}).get("executed", 0) for name in HELPER_SUITES)
    black_box = sum(suites.get(name, {}).get("executed", 0) for name in EXPECTED_SUITES
                    if name not in HELPER_SUITES | {"SwiftMediaMetadataPackageTests.xctest", "Selected tests"})
    return {"passed": not errors, "exitCode": code, "timedOut": timed_out,
            "counts": suites.get("Selected tests"), "suites": suites,
            "coverage": {"blackBox": black_box, "helpers": helpers}, "errors": errors,
            "sourceCheckoutsUnchanged": unchanged}


def git(checkout, *arguments):
    return subprocess.check_output(["git", "-C", str(checkout), *arguments])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path, help="clean pinned SwiftMediaMetadata checkout")
    parser.add_argument("argument_parser", type=Path, help="clean local checkout at Package.resolved revision")
    parser.add_argument("artifacts", type=Path, help="new isolated output directory")
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    dependency = args.argument_parser.resolve(strict=True)
    pins = json.loads((checkout / "Package.resolved").read_text())["pins"]
    pin = next(item for item in pins if item["identity"] == "swift-argument-parser")
    for path, expected in [(checkout, REVISION), (dependency, pin["state"]["revision"])]:
        if git(path, "rev-parse", "HEAD").decode().strip() != expected or git(path, "status", "--porcelain").strip():
            parser.error(f"Expected clean checkout at {expected}: {path}")
    artifacts = args.artifacts.resolve()
    if any(artifacts == source or source in artifacts.parents for source in (checkout, dependency)):
        parser.error("Output must be outside both source checkouts")
    artifacts.mkdir(parents=True, exist_ok=False)
    package = artifacts / "candidate"
    environment = {"dependencyRevision": REVISION, "argumentParser": pin["state"],
                   "toolchain": subprocess.check_output(["swift", "--version"], text=True),
                   "scriptSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   "sourceArchiveSHA256": {}}
    # Archive only tracked committed bytes; no upstream build state or manifests are modified.
    for source, destination in [(checkout, package), (dependency, artifacts / "swift-argument-parser")]:
        archive = git(source, "archive", "HEAD")
        environment["sourceArchiveSHA256"][str(source)] = hashlib.sha256(archive).hexdigest()
        destination.mkdir()
        subprocess.run(["tar", "-xf", "-", "-C", str(destination)], input=archive, check=True)
    patch = ROOT / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
    environment["patchSHA256"] = hashlib.sha256(patch.read_bytes()).hexdigest()
    with (artifacts / "patch.log").open("w") as output:
        subprocess.run(["patch", "-p1", "-i", str(patch)], cwd=package,
                       stdout=output, stderr=subprocess.STDOUT, check=True, timeout=60)
    manifest = package / "Package.swift"
    text = manifest.read_text()
    original = '.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")'
    if text.count(original) != 1:
        raise ValueError("Unexpected upstream ArgumentParser declaration")
    manifest.write_text(text.replace(original, '.package(path: "../swift-argument-parser")'))
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(artifacts / "module-cache"),
               SWIFT_EXIF_RUN_CLI_TESTS="1", SWIFT_EXIF_CLI_BINARY=str(package / ".build/release/swift-exif"))
    environment["cliBinary"] = env["SWIFT_EXIF_CLI_BINARY"]
    (artifacts / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    log = artifacts / "candidate-cli-tests.log"
    print("Building candidate and running upstream Release CLI tests…", flush=True)
    timed_out = False
    with log.open("w") as output:
        try:
            code = subprocess.run(["swift", "test", "--package-path", str(package), "-c", "release",
                                   "--disable-sandbox", "--filter", "SwiftMediaMetadataCLITests"],
                                  env=env, stdout=output, stderr=subprocess.STDOUT, timeout=1800).returncode
        except subprocess.TimeoutExpired:
            code, timed_out = None, True
    unchanged = all(not git(source, "status", "--porcelain").strip() and
                    hashlib.sha256(git(source, "archive", "HEAD")).hexdigest() == expected
                    for source, expected in environment["sourceArchiveSHA256"].items())
    summary = validate_result(log.read_text(), code, timed_out, unchanged)
    summary["logSHA256"] = hashlib.sha256(log.read_bytes()).hexdigest()
    (artifacts / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    raise SystemExit(0 if summary["passed"] else 1)


if __name__ == "__main__":
    main()
