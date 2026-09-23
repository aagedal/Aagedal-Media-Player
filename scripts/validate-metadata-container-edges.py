#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare the RTMD candidate on deterministic synthetic containers in source copies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from metadata_candidate import add_candidate_arguments, resolve_candidate

REVISION = "c2d77c2dcefcb997623e52beca57bc61ce302cb9"
ROOT = Path(__file__).resolve().parent.parent


def u32(*values):
    return struct.pack(">" + "I" * len(values), *values)


def atom(kind, payload=b"", style="normal"):
    if style == "extended":
        return u32(1) + kind.encode() + struct.pack(">Q", len(payload) + 16) + payload
    return u32(0 if style == "zero" else len(payload) + 8) + kind.encode() + payload


def sample(iso):
    def tag(number, data):
        return struct.pack(">HH", number, len(data)) + data
    triples = struct.pack(">hhhhhh", 1, -2, 3, -4, 5, -6)
    imu = u32(2, 6) + triples
    return (struct.pack(">H", 28) + bytes(26) + tag(0xe301, u32(iso))
            + tag(0xe43b, imu) + tag(0xe44b, imu) + bytes(4))


def movie(offset, sizes, co64=False, style="normal"):
    table = (atom("stsd", u32(0, 1) + atom("rtmd"))
             + atom("stts", u32(0, 1, 2, 20))
             + atom("stsz", u32(0, 0, 2, *sizes))
             + atom("stsc", u32(0, 1, 1, 2, 1)))
    table += atom("co64", u32(0, 1) + struct.pack(">Q", offset)) if co64 else atom("stco", u32(0, 1, offset))
    mdia = (atom("mdhd", u32(0, 0, 0, 1000, 40, 0))
            + atom("hdlr", u32(0, 0) + b"meta") + atom("minf", atom("stbl", table)))
    return atom("moov", atom("trak", atom("mdia", mdia)), style)


def fixtures():
    first, second = sample(800), sample(1600)
    sizes = [len(first), len(second)]
    prefix = atom("ftyp", b"isom" + u32(0) + b"isom")
    padding = bytes(37)  # Deliberately unaligned absolute sample offsets.
    payload = padding + first + second
    cases = {}
    for leading in (True, False):
        for co64 in (False, True):
            for style in ("normal", "extended"):
                moov = movie(0, sizes, co64, style)
                offset = len(prefix) + (len(moov) if leading else 0) + (16 if style == "extended" else 8) + len(padding)
                moov = movie(offset, sizes, co64, style)
                mdat = atom("mdat", payload, style)
                name = f"{'leading' if leading else 'trailing'}-moov-{'co64' if co64 else 'stco'}-{style}"
                cases[name] = (prefix + (moov + mdat if leading else mdat + moov), True, True)
    moov = movie(0, sizes)
    offset = len(prefix) + len(moov) + 8 + len(padding)
    valid = prefix + movie(offset, sizes) + atom("mdat", payload)
    cases["zero-size-mdat"] = (prefix + movie(offset, sizes) + atom("mdat", payload, "zero"), True, True)
    offset = len(prefix) + 8 + len(padding)
    cases["zero-size-moov"] = (prefix + atom("mdat", payload) + movie(offset, sizes, style="zero"), True, True)
    # Ordinary non-media atoms and an empty first mdat must not alter the
    # absolute offsets into the later mdat containing the RTMD samples.
    leading_free = atom("free", b"before-moov")
    offset = len(prefix) + len(leading_free) + len(moov) + 8 + len(padding)
    cases["leading-free"] = (prefix + leading_free + movie(offset, sizes) + atom("mdat", payload), True, True)
    between_free = atom("free", b"between-moov-and-mdat", "extended")
    offset = len(prefix) + len(moov) + len(between_free) + 8 + len(padding)
    cases["extended-free-between"] = (prefix + movie(offset, sizes) + between_free + atom("mdat", payload), True, True)
    empty_mdat = atom("mdat")
    offset = len(prefix) + len(empty_mdat) + len(moov) + 8 + len(padding)
    cases["empty-first-mdat"] = (prefix + empty_mdat + movie(offset, sizes) + atom("mdat", payload), True, True)
    cases["trailing-free"] = (valid + atom("free", b"after-mdat"), True, True)
    cases["no-rtmd"] = (prefix + atom("mdat", payload) + atom("moov"), False, False)
    cases["empty-file"] = (b"", False, False)
    cases["ftyp-only"] = (prefix, False, False)
    cases["mdat-only"] = (prefix + atom("mdat", payload), False, False)
    malformed = {
        "short-header": b"abc",
        "short-extended-header": u32(1) + b"free" + bytes(3),
        "undersized-atom": u32(7) + b"free",
        "undersized-extended": u32(1) + b"free" + struct.pack(">Q", 15),
        "huge-extended": u32(1) + b"free" + struct.pack(">Q", 2**64 - 1),
        "int-max-extended": u32(1) + b"free" + struct.pack(">Q", 2**63 - 1),
        "truncated-payload": u32(100) + b"free" + b"abc",
    }
    for name, bad in malformed.items():
        # A short extended header throws; public RTMD discovery swallows that error.
        cases[f"suffix-{name}"] = (valid + bad, name != "short-extended-header", name != "short-extended-header")
        cases[f"prefix-{name}"] = (bad if name == "short-header" else bad + valid, False, False)
    cases["truncated-sample"] = (valid[:-(len(second) + len(first) // 2)], True, False)
    cases["out-of-range-co64"] = (prefix + movie(2**64 - 1, sizes, True) + atom("mdat", payload), True, False)
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("artifacts", type=Path, help="new directory for source copies, fixtures and logs")
    add_candidate_arguments(parser)
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    patch = ROOT / "docs/dependency-patches/swift-media-metadata-3.0.0-rtmd-skip-mdat.patch"
    candidate_source = resolve_candidate(args, parser, checkout, patch)
    revision = candidate_source.provenance["baselineRevision"]
    artifacts = args.artifacts.resolve()
    if any(artifacts == source or source in artifacts.parents
           for source in (candidate_source.baseline, candidate_source.candidate)):
        parser.error("Artifacts must be outside source checkouts")
    artifacts.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(artifacts / "module-cache"))
    probe = ROOT / "scripts/MetadataContainerEdgeProbe.swift"
    cases = fixtures()
    fixture_dir = artifacts / "fixtures"
    fixture_dir.mkdir()
    for name, (data, _, _) in cases.items():
        (fixture_dir / f"{name}.mov").write_bytes(data)
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    environment = {"dependencyRevision": revision, "candidateProvenance": candidate_source.provenance,
                   "toolchain": subprocess.check_output(["swift", "--version"], text=True),
                   "hashes": {str(path): digest(path) for path in [Path(__file__), patch, probe]},
                   "fixtures": {name: hashlib.sha256(data).hexdigest() for name, (data, _, _) in cases.items()}}
    (artifacts / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    manifest = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ContainerEdgeProbe", platforms: [.macOS(.v13)], targets: [.systemLibrary(name: "CZlib"), .target(name: "SwiftMediaMetadata", dependencies: ["CZlib"], resources: [.copy("Resources/GeoLocationDatabase.bin")], linkerSettings: [.linkedLibrary("z")]), .executableTarget(name: "Probe", dependencies: ["SwiftMediaMetadata"])])
'''
    results = {}
    for variant in ("baseline", "fixed"):
        package = artifacts / variant
        sources = package / "Sources"
        sources.mkdir(parents=True)
        source_checkout = candidate_source.checkout_for(variant)
        for module in ("SwiftMediaMetadata", "CZlib"):
            shutil.copytree(source_checkout / "Sources" / module, sources / module)
        (sources / "Probe").mkdir()
        shutil.copyfile(probe, sources / "Probe/main.swift")
        (package / "Package.swift").write_text(manifest)
        if variant == "fixed":
            if candidate_source.mode == "recordedPatch":
                source = sources / "SwiftMediaMetadata/Video/RTMDReader.swift"
                source.chmod(source.stat().st_mode | 0o200)
            candidate_source.apply_patch(package, package / "patch.log")
        print(f"Building {variant}…", flush=True)
        with (package / "build.log").open("w") as output:
            subprocess.run(["swift", "build", "--package-path", str(package), "-c", "release", "--disable-sandbox"], env=env, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=1800)
        results[variant] = {}
        for name in cases:
            # Isolate each malformed input so traps or hangs fail with a retained case log.
            with (package / f"{name}.json").open("w") as output:
                subprocess.run([str(package / ".build/release/Probe"), str(fixture_dir / f"{name}.mov")], stdout=output, stderr=subprocess.STDOUT, check=True, timeout=30)
            results[variant][name] = json.loads((package / f"{name}.json").read_text())
    errors = []
    missing_track_error = "Invalid video file: No Sony RTMD track found"
    read_errors = ("attributeError", "gyroscopeError", "accelerometerError")
    for name, (_, presence, decoded) in cases.items():
        baseline, fixed = results["baseline"][name], results["fixed"][name]
        if baseline != fixed:
            errors.append(f"{name}: baseline/candidate mismatch")
        for variant in results:
            value = results[variant][name]
            if value["hasRTMD"] != presence:
                errors.append(f"{variant}/{name}: unexpected track presence")
            expected_error = None if presence else missing_track_error
            for key in read_errors:
                if value.get(key) != expected_error:
                    errors.append(f"{variant}/{name}: unexpected {key}: {value.get(key)!r}")
            if decoded:
                if ([frame["iso"] for frame in value.get("frames", [])] != [800, 1600]
                        or [frame["timestamp"] for frame in value.get("frames", [])] != [0, 0.02]
                        or value["firstFrame"] != value["frames"][0] or value["imuRate"] != 100):
                    errors.append(f"{variant}/{name}: incorrect absolute-offset frame/IMU decode")
                expected = [{"timestamp": timestamp, "x": x, "y": y, "z": z}
                            for timestamp, (x, y, z) in zip([0, 0.01, 0.02, 0.03], [(1, -2, 3), (-4, 5, -6)] * 2)]
                if value.get("gyroscope") != expected or value.get("accelerometer") != expected:
                    errors.append(f"{variant}/{name}: incorrect motion samples")
            elif (value["firstFrame"] is not None or value["imuRate"] is not None
                  or value.get("frames", []) or value.get("gyroscope", []) or value.get("accelerometer", [])):
                errors.append(f"{variant}/{name}: unexpected sample decode")
    if not candidate_source.verify_unchanged():
        errors.append("Baseline or candidate source checkout changed")
    (artifacts / "summary.json").write_text(json.dumps({"passed": not errors, "caseCount": len(cases), "errors": errors, "results": results}, indent=2) + "\n")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Passed {len(cases)} cases in both variants; artifacts: {artifacts}")


if __name__ == "__main__":
    main()
