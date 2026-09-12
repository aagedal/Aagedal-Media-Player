#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build baseline/fixed isolated dependency probes; never edit the resolved checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from metadata_candidate import add_candidate_arguments, resolve_candidate

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("checkout", type=Path, help="resolved SwiftMediaMetadata 3.0.0 checkout")
parser.add_argument("artifacts", type=Path, help="new artifact directory")
parser.add_argument("inputs", type=Path, nargs="+")
add_candidate_arguments(parser)
args = parser.parse_args()
checkout = args.checkout.resolve(strict=True)
root = Path(__file__).resolve().parent.parent
patch = root / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
candidate_source = resolve_candidate(args, parser, checkout, patch)
inputs = [path.resolve(strict=True) for path in args.inputs]
if any(not path.is_file() for path in inputs) or len(set(inputs)) != len(inputs):
    parser.error("Inputs must be distinct regular files")
revision = candidate_source.provenance["baselineRevision"]
artifacts = args.artifacts.resolve()
if any(artifacts == source or source in artifacts.parents
       for source in {candidate_source.baseline, candidate_source.candidate, *inputs}):
    parser.error("Artifacts must be outside source checkout and input paths")
artifacts.mkdir(parents=True, exist_ok=False)
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(artifacts / "module-cache"))
def run(command, log, **kwargs):
    with log.open("w") as output:
        subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True,
                       env=env, timeout=1800, **kwargs)
def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()
environment = {"dependencyRevision": revision,
               "candidateProvenance": candidate_source.provenance,
               "probeSHA256": digest(root / "scripts/MetadataMemoryProfiler.swift"),
               "patchSHA256": digest(patch),
               "harnessSHA256": digest(Path(__file__)),
               "validatorSHA256": digest(root / "scripts/validate-metadata-memory-profile.py"),
               "appRevision": subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
               "appWorkingTree": subprocess.check_output(["git", "-C", str(root), "status", "--short"], text=True),
               "inputs": [{"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)} for path in inputs]}
for name, command in [("os", ["sw_vers"]), ("xcode", ["xcodebuild", "-version"]),
                      ("hardware", ["sysctl", "-n", "machdep.cpu.brand_string", "hw.memsize"])]:
    result = subprocess.run(command, text=True, capture_output=True, timeout=60)
    environment[name] = {"output": result.stdout.strip(), "error": result.stderr.strip(), "exitCode": result.returncode}
(artifacts / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
manifest = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MetadataProbe", platforms: [.macOS(.v13)], products: [.executable(name: "metadata-probe", targets: ["Probe"])], targets: [.systemLibrary(name: "CZlib"), .target(name: "SwiftMediaMetadata", dependencies: ["CZlib"], resources: [.copy("Resources/GeoLocationDatabase.bin")], linkerSettings: [.linkedLibrary("z")]), .executableTarget(name: "Probe", dependencies: ["SwiftMediaMetadata"])])
'''
records = []
for variant in ("baseline", "fixed"):
    package = artifacts / variant
    sources = package / "Sources"
    sources.mkdir(parents=True)
    source_checkout = candidate_source.checkout_for(variant)
    for module in ("SwiftMediaMetadata", "CZlib"):
        shutil.copytree(source_checkout / "Sources" / module, sources / module)
    (sources / "Probe").mkdir()
    shutil.copyfile(root / "scripts/MetadataMemoryProfiler.swift", sources / "Probe/main.swift")
    (package / "Package.swift").write_text(manifest)
    if variant == "fixed":
        if candidate_source.mode == "recordedPatch":
            source = sources / "SwiftMediaMetadata/Video/RTMDReader.swift"
            source.chmod(source.stat().st_mode | 0o200)
        candidate_source.apply_patch(package, package / "patch.log")
    print(f"Building {variant} dependency probe…", flush=True)
    run(["swift", "build", "--package-path", str(package), "-c", "release", "--disable-sandbox"], package / "build.log")
    binary = package / ".build/release/metadata-probe"
    for index, path in enumerate(inputs):
        for mode in ("read", "rtmd", "skip-mdat"):
            output = package / f"input-{index}-{mode}.jsonl"
            run([str(binary), mode, str(path)], output)
            phases = [json.loads(line) for line in output.read_text().splitlines()]
            records.append({"variant": variant, "input": str(path), "mode": mode, "phases": phases})
validate = runpy.run_path(str(root / "scripts/validate-metadata-memory-profile.py"))["validate"]
validate(records, [str(path) for path in inputs])
if not candidate_source.verify_unchanged():
    raise ValueError("Baseline or candidate source checkout changed during validation")
(artifacts / "summary.json").write_text(json.dumps({"snapshotParity": True, "records": records}, indent=2) + "\n")
print(f"Profiles and matching metadata snapshots saved to {artifacts}")
