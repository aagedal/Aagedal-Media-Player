#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only real-media parity and optional local upstream library tests in isolated copies."""
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


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("artifacts", type=Path, help="new directory for safe digests, logs and source copies")
    parser.add_argument("--rtmd", type=Path, required=True, help="real Sony clip; full RTMD plus metadata export parity")
    parser.add_argument("--media", "--raw", dest="raw", type=Path, nargs="+", required=True,
                        help="representative camera/container clips for metadata export parity (--raw remains an alias)")
    parser.add_argument("--reuse-packages", type=Path, help="existing baseline/fixed isolated packages; library sources are verified before reuse")
    parser.add_argument("--upstream-tests", action="store_true", help="run candidate upstream library tests; excludes CLI and remote dependencies")
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION or subprocess.check_output(["git", "-C", str(checkout), "status", "--porcelain"], text=True).strip():
        parser.error("Expected a clean SwiftMediaMetadata 3.0.0 c2d77c2 checkout")
    inputs = [args.rtmd.resolve(strict=True)] + [path.resolve(strict=True) for path in args.raw]
    if len(set(inputs)) != len(inputs) or any(not path.is_file() for path in inputs):
        parser.error("Expected distinct regular media files")
    artifacts = args.artifacts.resolve()
    artifacts.mkdir(parents=True, exist_ok=False)
    package_root = args.reuse_packages.resolve(strict=True) if args.reuse_packages else artifacts
    if package_root == checkout or checkout in package_root.parents:
        parser.error("Package copies must be outside the resolved checkout")
    patch = ROOT / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
    probe = ROOT / "scripts/MetadataRealMediaProbe.swift"
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(artifacts / "module-cache"))
    # Mirror NRTXMLParser.sidecarCandidates at the pinned revision, including absence.
    sidecars = [path.with_name(path.stem + suffix) for path in inputs
                for suffix in ("M01.XML", "M01.xml", "m01.XML", "m01.xml", ".XML", ".xml", ".M01", ".m01", ".NFO", ".nfo")]
    environment = {"dependencyRevision": revision, "packageRoot": str(package_root),
                   "toolchain": subprocess.check_output(["swift", "--version"], text=True),
                   "sourceHashes": {str(path): digest(path) for path in [Path(__file__), probe, patch]},
                   "sidecarCandidates": [{"path": str(path), "sha256": digest(path) if path.is_file() else None} for path in sidecars],
                   "inputs": [{"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)} for path in inputs]}
    (artifacts / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    def run(command, log, timeout=1800):
        with log.open("w") as output:
            return subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, env=env, timeout=timeout).returncode
    results = {}
    errors = []
    for variant in ("baseline", "fixed"):
        package = package_root / variant
        if not args.reuse_packages:
            (package / "Sources").mkdir(parents=True)
            for module in ("SwiftMediaMetadata", "CZlib"):
                shutil.copytree(checkout / "Sources" / module, package / "Sources" / module)
            if variant == "fixed":
                source = package / "Sources/SwiftMediaMetadata/Video/RTMDReader.swift"
                source.chmod(source.stat().st_mode | 0o200)
                with (artifacts / "patch.log").open("w") as output:
                    subprocess.run(["patch", "-p1", "-i", str(patch)], cwd=package, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=60)
        # Reject stale or independently edited reused library sources, including extra files.
        for module in ("SwiftMediaMetadata", "CZlib"):
            original = checkout / "Sources" / module
            copied = package / "Sources" / module
            files = {path.relative_to(original) for path in original.rglob("*") if path.is_file()}
            if files != {path.relative_to(copied) for path in copied.rglob("*") if path.is_file()}:
                raise ValueError(f"Unexpected {variant}/{module} source inventory")
            for relative in files:
                expected = (original / relative).read_bytes()
                if variant == "fixed" and str(relative) == "Video/RTMDReader.swift":
                    old = b"let boxes = try ISOBMFFBoxReader.parseBoxes(from: fullData)"
                    if expected.count(old) != 1:
                        raise ValueError("Unexpected RTMD patch location")
                    expected = expected.replace(old, b"let boxes = try ISOBMFFBoxReader.parseTopLevelBoxesSkippingMdat(fullData)")
                if (copied / relative).read_bytes() != expected:
                    raise ValueError(f"Unexpected {variant}/{module}/{relative} source contents")
        target = package / "Sources/RealMediaProbe"
        target.mkdir(exist_ok=True)
        shutil.copyfile(probe, target / "main.swift")
        test_target = ""
        if args.upstream_tests and variant == "fixed":
            tests = package / "Tests/SwiftMediaMetadataTests"
            original_tests = checkout / "Tests/SwiftMediaMetadataTests"
            if tests.exists():
                original_files = {path.relative_to(original_tests) for path in original_tests.rglob("*") if path.is_file()}
                if (original_files != {path.relative_to(tests) for path in tests.rglob("*") if path.is_file()}
                        or any((original_tests / relative).read_bytes() != (tests / relative).read_bytes() for relative in original_files)):
                    raise ValueError("Existing copied tests differ from the pinned checkout")
            else:
                shutil.copytree(original_tests, tests)
            test_target = ', .testTarget(name: "SwiftMediaMetadataTests", dependencies: ["SwiftMediaMetadata"], resources: [.copy("Fixtures/Resources")])'
        (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RealMediaValidation", platforms: [.macOS(.v13)], targets: [.systemLibrary(name: "CZlib"), .target(name: "SwiftMediaMetadata", dependencies: ["CZlib"], resources: [.copy("Resources/GeoLocationDatabase.bin")], linkerSettings: [.linkedLibrary("z")]), .executableTarget(name: "RealMediaProbe", dependencies: ["SwiftMediaMetadata"])''' + test_target + '])\n')
        print(f"Building {variant} real-media probe…", flush=True)
        if run(["swift", "build", "--package-path", str(package), "-c", "release", "--disable-sandbox"], artifacts / f"{variant}-build.log"):
            raise ValueError(f"{variant} build failed; inspect build log")
        results[variant] = {}
        for index, path in enumerate(inputs):
            for mode in (["metadata", "rtmd"] if index == 0 else ["metadata"]):
                name = f"input-{index}-{mode}"
                log = artifacts / f"{variant}-{name}.json"
                code = run([str(package / ".build/release/RealMediaProbe"), mode, str(path)], log)
                if code:
                    errors.append(f"{variant}/{name}: process exited {code}")
                try:
                    result = json.loads(log.read_text())
                except (ValueError, UnicodeError):
                    result = {"invalidOutputSHA256": digest(log)}
                    errors.append(f"{variant}/{name}: invalid JSON output")
                results[variant][name] = result
                print(f"Completed {variant}/{name}; exit {code}", flush=True)
    for name, value in results["baseline"].items():
        if value != results["fixed"][name]:
            errors.append(f"{name}: baseline/candidate mismatch")
    tests = None
    if args.upstream_tests:
        print("Running candidate upstream library tests…", flush=True)
        log = artifacts / "candidate-library-tests.log"
        code = run(["swift", "test", "--package-path", str(package_root / "fixed"), "-c", "release", "--disable-sandbox"], log)
        output = log.read_text()
        totals = re.findall(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", output)
        tests = {"exitCode": code, "summary": totals[-1] if totals else None,
                 "logSHA256": digest(log), "cliTestsIncluded": False}
        if code or not totals:
            errors.append("Candidate upstream library suite failed or lacks a test summary")
    # Verify original fixtures remained byte-identical after every reader/test finished.
    for item in environment["inputs"]:
        if digest(Path(item["path"])) != item["sha256"]:
            errors.append("Input bytes changed during validation")
    for item in environment["sidecarCandidates"]:
        path = Path(item["path"])
        if (digest(path) if path.is_file() else None) != item["sha256"]:
            errors.append("Sidecar contents or presence changed during validation")
    summary = {"passed": not errors, "errors": errors, "results": results, "upstreamLibraryTests": tests}
    (artifacts / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Real-media parity passed; artifacts: {artifacts}")


if __name__ == "__main__":
    main()
