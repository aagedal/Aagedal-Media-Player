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
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from metadata_candidate import (add_candidate_arguments, resolve_candidate,
                                validate_candidate_provenance)

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
# Identities from the 2026-09-09 run in METADATA_LIBRARY_FIXTURE_VALIDATION.md.
# The two unavailable Sony originals have no reviewed hashes yet.
KNOWN_FIXTURE_SHA256 = {
    "Nepobaby sesong 2 01.jpg": "79177d554a27f15183c8bd0861a0c4fc3c92be7c8cbaba1829bfeca88818b757",
    "TRA03167_edit.jpg": "e425f11497a948acd14158941b8f7c12b28d96d308dce7877f346126f6150be9",
    "S01E13 The Parting of Ways-0003.jpg": "67a6631a76e6ab226da4f9367d63c6373c6a160b5dcc670016e9dbbd0db6b3fb",
    "S01E13 The Parting of Ways-0006.jpg": "ea07a8985925092731d91ffa100c61e87eff820e7ce9b64430ba7f2b49dc51d7",
    "Vixen 2026 05.jpg": "eb0d79c52deb04b0e67ca7f8c091d9ec0aa4b585e95134638622154c23544f7b",
    "ShortPlantHDR_seq_000001.jxl": "92ae631a48e89f3ef73a355d79df1f4be2c5f7c2fa54572dce3c053dc1963e57",
    "TRA03168_edit_002.jxl": "75c772fac47508798e3ef96618dc405676a53f2a0e74186eb965b61379923a89",
    "Nepobaby sesong 2 06.xmp": "64802bc1bc6735e6d6b34138120c71f68cce190da0dfbe4f4031045db145d6c7",
    "DEI_8158_edit.jpg": "4f97e1d1239d804fadaadd84f466f0b415a6eb02db5842dc250a07bf956dd039",
    "CRM.CRM": "b869a48d567d39a01d525cc532d88b5c720fbc5ac5c7c84f43b3734fa2bbdaf6",
    "MCA.mxf": "e6b67949b33cad33126b675dbf8bf74eb0e1a6b119ccd392eb00a393fccf3abf",
}


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def validate_known_fixture_identity(name, actual_sha256):
    expected = KNOWN_FIXTURE_SHA256.get(name)
    if expected is not None and actual_sha256 != expected:
        raise ValueError(f"Fixture SHA-256 mismatch for {name}: expected {expected}, got {actual_sha256}")


def validate_result(output, code, missing_cases, timed_out=False, candidate_provenance=None):
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
    if candidate_provenance is not None:
        try:
            validate_candidate_provenance(candidate_provenance)
        except (TypeError, ValueError) as error:
            errors.append(f"Invalid candidate provenance: {error}")
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
    add_candidate_arguments(parser)
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    patch = ROOT / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
    candidate_source = resolve_candidate(args, parser, checkout, patch)
    if args.baseline_control and candidate_source.mode == "exactCheckout":
        parser.error("--baseline-control cannot be combined with exact candidate checkout mode")
    images = args.images.resolve(strict=True)
    if not images.is_dir():
        parser.error("Image fixtures must be a directory")
    missing = [name for name in IMAGE_TESTS if not (images / name).is_file()]
    if missing and not args.allow_missing_images:
        parser.error("Missing image fixtures: " + ", ".join(missing))
    media = {"CRM.CRM": args.crm.resolve(strict=True), "MCA.mxf": args.mca.resolve(strict=True)}
    if any(not path.is_file() for path in media.values()):
        parser.error("CRM and MCA inputs must be regular files")
    sources = {name: images / name for name in IMAGE_TESTS if name not in missing} | media
    source_hashes = {name: digest(path) for name, path in sources.items()}
    for name, source_hash in source_hashes.items():
        validate_known_fixture_identity(name, source_hash)
    artifacts = args.artifacts.resolve()
    if any(artifacts == source or source in artifacts.parents
           for source in [candidate_source.baseline, candidate_source.candidate, images, *media.values()]):
        parser.error("Artifacts must be outside input source paths")
    artifacts.mkdir(parents=True, exist_ok=False)
    variant = "baseline" if args.baseline_control else "candidate"
    package = artifacts / variant
    source_variant = "baseline" if args.baseline_control else "fixed"
    source_checkout = candidate_source.checkout_for(source_variant)
    archive = candidate_source.archive_for(source_variant)
    package.mkdir()
    subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archive, check=True)
    if not args.baseline_control:
        candidate_source.apply_patch(package, artifacts / "patch.log")
    staged = [(name, images / name, package / "TestImages" / name) for name in IMAGE_TESTS if name not in missing]
    staged += [(name, source, package / "VideoFixtures" / name) for name, source in media.items()]
    inputs = []
    for name, source, destination in staged:
        destination.parent.mkdir(exist_ok=True)
        source_hash = source_hashes[name]
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
    environment = {"dependencyRevision": REVISION, "candidateProvenance": candidate_source.provenance,
                   "variant": variant, "sourceArchiveSHA256": hashlib.sha256(archive).hexdigest(),
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
    summary = validate_result(log.read_text(), code, missing_cases, timed_out,
                              candidate_source.provenance)
    summary["logSHA256"] = digest(log)
    unchanged = all(digest(Path(item["path"])) == item["sha256"] and digest(Path(item["copy"])) == item["sha256"] for item in inputs)
    unchanged = unchanged and all(not (images / name).exists() for name in missing)
    unchanged = unchanged and candidate_source.verify_unchanged()
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
