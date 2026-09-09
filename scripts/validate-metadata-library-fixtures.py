#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the 20 previously skipped upstream fixture tests against the isolated RTMD candidate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REVISION = "c2d77c2dcefcb997623e52beca57bc61ce302cb9"
IMAGE_TESTS = {
    "Nepobaby sesong 2 01.jpg": ["testReadJPEGWithIPTC"],
    "TRA03167_edit.jpg": ["testReadJPEGWithRichMetadata"],
    "S01E13 The Parting of Ways-0003.jpg": ["testJPEGRoundTripPreservesImageData", "testMultipleJPEGModifications"],
    "S01E13 The Parting of Ways-0006.jpg": ["testJPEGWriteReadIPTC"],
    "Vixen 2026 05.jpg": ["testJPEGIPTCXMPSyncRoundTrip"],
    "TRA03164.ARW": ["testReadARW", "testARWWriteIPTCAndXMP", "testWriteSidecarForARW"],
    "ShortPlantHDR_seq_000001.jxl": ["testReadJXLBareCodestream"],
    "TRA03168_edit_002.jxl": ["testReadJXLContainer", "testJXLContainerWriteXMP", "testJXLRoundTripPreservesCodestream", "testJXLWithExistingMetadata"],
    "TRA03164.xmp": ["testReadExistingSidecar", "testReadSidecarMatchesManualRead"],
    "Nepobaby sesong 2 06.xmp": ["testReadExistingNepobabySidecar"],
    "DEI_8158_edit.jpg": ["testWriteJPEGToTempFile"],
}
EXPECTED_CASES = {f"RealFileTests/{name}" for names in IMAGE_TESTS.values() for name in names} | {
    "CRMReaderTests/testRealC70CRMSampleIfPresent", "MXFMCALabelsTests/testRealBmxToolsFixture"}


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def validate_result(output, code, missing_cases, timed_out=False):
    """Only explicitly absent image fixtures may skip; every pinned case must finish."""
    errors = []
    cases = {}
    pattern = r"^Test Case '-\[SwiftMediaMetadataTests\.([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \([^\n]+\)\.$"
    for suite, name, status in re.findall(pattern, output, re.MULTILINE):
        key = f"{suite}/{name}"
        if key in cases:
            errors.append(f"Duplicate completed case: {key}")
        cases[key] = status
    if not missing_cases <= EXPECTED_CASES:
        errors.append("Unknown missing-fixture cases")
    if set(cases) != EXPECTED_CASES:
        errors.append("Missing or unexpected completed fixture cases")
    for name in EXPECTED_CASES:
        if cases.get(name) != ("skipped" if name in missing_cases else "passed"):
            errors.append(f"Unexpected fixture result: {name}")
    summaries = {}
    pattern = (r"^Test Suite '([^']+)' (passed|failed) at [^\n]+\n"
               r"[ \t]*Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?[^\n]*$")
    for suite, status, count, skipped, failed in re.findall(pattern, output, re.MULTILINE):
        if suite in summaries:
            errors.append(f"Duplicate completed suite: {suite}")
        summaries[suite] = (status, int(count), int(skipped or 0), int(failed))
    expected_suites = {"RealFileTests": 18, "CRMReaderTests": 1, "MXFMCALabelsTests": 1,
                       "MetadataFixtureValidationPackageTests.xctest": 20, "Selected tests": 20}
    if set(summaries) != set(expected_suites):
        errors.append("Missing or unexpected completed suites")
    for name, count in expected_suites.items():
        skipped = (len(missing_cases) if name in {"MetadataFixtureValidationPackageTests.xctest", "Selected tests"}
                   else sum(case.startswith(name + "/") for case in missing_cases))
        if summaries.get(name) != ("passed", count, skipped, 0):
            errors.append(f"Unexpected suite summary: {name}")
    if code != 0 or timed_out:
        errors.append("Fixture test process failed or timed out")
    return {"passed": not errors, "allFixturesCovered": not errors and not missing_cases,
            "exitCode": code, "timedOut": timed_out, "cases": cases,
            "executed": len(cases), "passedCases": sum(value == "passed" for value in cases.values()),
            "skippedCases": sorted(name for name, value in cases.items() if value == "skipped"), "errors": errors}


def git(checkout, *args):
    return subprocess.check_output(["git", "-C", str(checkout), *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("artifacts", type=Path, help="new isolated output directory")
    parser.add_argument("--images", type=Path, required=True, help="directory containing upstream-named image/sidecar fixtures")
    parser.add_argument("--crm", type=Path, required=True, help="original upstream Canon C70 sample")
    parser.add_argument("--mca", type=Path, required=True, help="original upstream four-track bmxtools MXF sample")
    parser.add_argument("--allow-missing-images", action="store_true", help="validate available fixtures, reporting exact remaining skips")
    parser.add_argument("--baseline-control", action="store_true", help="run unpatched 3.0.0 to diagnose pre-existing fixture failures")
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    if git(checkout, "rev-parse", "HEAD").decode().strip() != REVISION or git(checkout, "status", "--porcelain").strip():
        parser.error("Expected a clean pinned SwiftMediaMetadata 3.0.0 checkout")
    images = args.images.resolve(strict=True)
    if not images.is_dir():
        parser.error("Image fixtures must be a directory")
    missing = [name for name in IMAGE_TESTS if not (images / name).is_file()]
    if missing and not args.allow_missing_images:
        parser.error("Missing image fixtures: " + ", ".join(missing))
    media = {"CRM.CRM": args.crm.resolve(strict=True), "MCA.mxf": args.mca.resolve(strict=True)}
    if any(not path.is_file() for path in media.values()):
        parser.error("CRM and MCA inputs must be regular files")
    artifacts = args.artifacts.resolve()
    if any(artifacts == source or source in artifacts.parents for source in [checkout, images, *media.values()]):
        parser.error("Artifacts must be outside input source paths")
    artifacts.mkdir(parents=True, exist_ok=False)
    variant = "baseline" if args.baseline_control else "candidate"
    package = artifacts / variant
    archive = git(checkout, "archive", "HEAD")
    package.mkdir()
    subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archive, check=True)
    patch = ROOT / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
    if not args.baseline_control:
        with (artifacts / "patch.log").open("w") as output:
            subprocess.run(["patch", "-p1", "-i", str(patch)], cwd=package, stdout=output,
                           stderr=subprocess.STDOUT, check=True, timeout=60)
    staged = [(images / name, package / "TestImages" / name) for name in IMAGE_TESTS if name not in missing]
    staged += [(source, package / "VideoFixtures" / name) for name, source in media.items()]
    inputs = []
    for source, destination in staged:
        destination.parent.mkdir(exist_ok=True)
        source_hash = digest(source)
        shutil.copyfile(source, destination)
        if digest(destination) != source_hash:
            raise ValueError("Fixture copy differs from original")
        inputs.append({"path": str(source), "copy": str(destination), "bytes": source.stat().st_size, "sha256": source_hash})
    relocations = {}
    for relative, old, name in [
        ("Video/CRMReaderTests.swift", "/Users/traag222/Movies/TestVideo/Canon Cinema RAW Light/A001C004_22032472_CANON.CRM", "CRM.CRM"),
        ("Video/MXFMCALabelsTests.swift", "/Users/traag222/Movies/TestVideo/MCA_Test/n-intervju_with-MCA-labels.mxf", "MCA.mxf"),
    ]:
        target = package / "Tests/SwiftMediaMetadataTests" / relative
        original = target.read_text()
        # Compute from #filePath so arbitrary output names need no Swift string escaping.
        replacement = 'URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("VideoFixtures/' + name + '").path'
        if original.count('"' + old + '"') != 1:
            raise ValueError("Unexpected upstream fixture path")
        target.write_text(original.replace('"' + old + '"', replacement))
        relocations[relative] = {"originalSHA256": hashlib.sha256(original.encode()).hexdigest(), "relocatedSHA256": digest(target)}
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MetadataFixtureValidation", platforms: [.macOS(.v13)], targets: [.systemLibrary(name: "CZlib"), .target(name: "SwiftMediaMetadata", dependencies: ["CZlib"], resources: [.copy("Resources/GeoLocationDatabase.bin")], linkerSettings: [.linkedLibrary("z")]), .testTarget(name: "SwiftMediaMetadataTests", dependencies: ["SwiftMediaMetadata"], resources: [.copy("Fixtures/Resources")])])
''')
    environment = {"dependencyRevision": REVISION, "variant": variant, "sourceArchiveSHA256": hashlib.sha256(archive).hexdigest(),
                   "scriptSHA256": digest(Path(__file__)), "patchSHA256": digest(patch),
                   "toolchain": subprocess.check_output(["swift", "--version"], text=True),
                   "inputs": inputs, "missingImages": missing, "testPathRelocations": relocations,
                   "selectedCases": sorted(EXPECTED_CASES)}
    (artifacts / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    command = ["swift", "test", "--package-path", str(package), "-c", "release", "--disable-sandbox", "--filter",
               "|".join(sorted(EXPECTED_CASES))]
    log = artifacts / "fixture-tests.log"
    print(f"Building {variant} and running the 20 formerly skipped fixture tests…", flush=True)
    timed_out = False
    with log.open("w") as output:
        try:
            code = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                  env=dict(os.environ, CLANG_MODULE_CACHE_PATH=str(artifacts / "module-cache")), timeout=1800).returncode
        except subprocess.TimeoutExpired:
            code, timed_out = None, True
    missing_cases = {f"RealFileTests/{name}" for image in missing for name in IMAGE_TESTS[image]}
    summary = validate_result(log.read_text(), code, missing_cases, timed_out)
    summary["logSHA256"] = digest(log)
    unchanged = all(digest(Path(item["path"])) == item["sha256"] and digest(Path(item["copy"])) == item["sha256"] for item in inputs)
    unchanged = unchanged and all(not (images / name).exists() for name in missing)
    unchanged = unchanged and git(checkout, "rev-parse", "HEAD").decode().strip() == REVISION and not git(checkout, "status", "--porcelain").strip()
    summary["inputsAndCheckoutUnchanged"] = unchanged
    if not unchanged:
        summary["errors"].append("Input fixtures, staged copies, absence, or checkout changed")
        summary["passed"] = summary["allFixturesCovered"] = False
    (artifacts / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if not summary["passed"]:
        raise SystemExit("\n".join(summary["errors"]))
    print(f"Fixture validation passed: {summary['passedCases']} passed, {len(summary['skippedCases'])} explicitly missing; artifacts: {artifacts}")


if __name__ == "__main__":
    main()
