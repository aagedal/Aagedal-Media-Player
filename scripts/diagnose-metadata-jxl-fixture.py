#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Diagnose the old JXL assertion using an original container and its real codestream.

This is supplementary evidence, never a replacement for fixture acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REVISION = "c2d77c2dcefcb997623e52beca57bc61ce302cb9"
CHECKS = {"containerWriteSucceeds", "containerPreservesCodestream", "bareWriteSucceeds",
          "bareWritePreservesBytes", "editedBareWrapsOnce", "editedBarePreservesCodestream",
          "editedBareOrientationRoundTrips"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_results(results, original_hash, unchanged):
    return (unchanged and set(results) == {"baseline", "candidate"}
            and results["baseline"] == results["candidate"]
            and all(result.get("fixtureSHA256") == original_hash
                    and all(result.get(check) is True for check in CHECKS)
                    for result in results.values()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("artifacts", type=Path, help="new isolated output directory")
    args = parser.parse_args()
    checkout, fixture = args.checkout.resolve(strict=True), args.fixture.resolve(strict=True)
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(checkout), *arguments])
    def clean():
        return git("rev-parse", "HEAD").decode().strip() == REVISION and not git("status", "--porcelain").strip()
    if not clean():
        parser.error("Expected a clean pinned 3.0.0 checkout")
    artifacts = args.artifacts.resolve()
    if artifacts == fixture or checkout == artifacts or checkout in artifacts.parents:
        parser.error("Artifacts must be outside dependency source and fixture paths")
    original_hash = digest(fixture)
    artifacts.mkdir(parents=True, exist_ok=False)
    archive = git("archive", "HEAD")
    patch = ROOT / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
    probe = ROOT / "scripts/MetadataJXLFixtureProbe.swift"
    staged = artifacts / "fixture.jxl"
    staged.write_bytes(fixture.read_bytes())
    if digest(staged) != original_hash:
        raise ValueError("Fixture changed while staging")
    environment = {"dependencyRevision": REVISION, "sourceArchiveSHA256": hashlib.sha256(archive).hexdigest(),
                   "fixture": str(fixture), "fixtureSHA256": original_hash,
                   "hashes": {str(p): digest(p) for p in [Path(__file__), patch, probe]},
                   "toolchain": subprocess.check_output(["swift", "--version"], text=True)}
    (artifacts / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    results = {}
    for variant in ("baseline", "candidate"):
        package = artifacts / variant
        package.mkdir()
        subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archive, check=True)
        if variant == "candidate":
            with (package / "patch.log").open("w") as log:
                subprocess.run(["patch", "-p1", "-i", str(patch)], cwd=package, stdout=log,
                               stderr=subprocess.STDOUT, check=True, timeout=60)
        (package / "Sources/Probe").mkdir()
        (package / "Sources/Probe/main.swift").write_bytes(probe.read_bytes())
        (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "JXLFixtureProbe", platforms: [.macOS(.v13)], targets: [.systemLibrary(name: "CZlib"), .target(name: "SwiftMediaMetadata", dependencies: ["CZlib"], resources: [.copy("Resources/GeoLocationDatabase.bin")], linkerSettings: [.linkedLibrary("z")]), .executableTarget(name: "Probe", dependencies: ["SwiftMediaMetadata"])])
''')
        print(f"Building and probing {variant}…", flush=True)
        with (package / "build.log").open("w") as log:
            subprocess.run(["swift", "build", "--package-path", str(package), "-c", "release", "--disable-sandbox"],
                           env=dict(os.environ, CLANG_MODULE_CACHE_PATH=str(artifacts / "module-cache")),
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1800)
        with (package / "probe.json").open("w") as output:
            subprocess.run([str(package / ".build/release/Probe"), str(staged)], stdout=output,
                           stderr=subprocess.STDOUT, check=True, timeout=60)
        results[variant] = json.loads((package / "probe.json").read_text())
    unchanged = clean() and digest(fixture) == original_hash and digest(staged) == original_hash
    passed = validate_results(results, original_hash, unchanged)
    summary = {"diagnosticPassed": passed, "fixtureGateComplete": False,
               "inputsAndCheckoutUnchanged": unchanged, "results": results}
    (artifacts / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if not passed:
        raise SystemExit("JXL diagnostic failed; inspect summary.json")
    print(f"Both variants pass all {len(CHECKS)} diagnostic checks; fixture acceptance remains open. Artifacts: {artifacts}")


if __name__ == "__main__":
    main()
