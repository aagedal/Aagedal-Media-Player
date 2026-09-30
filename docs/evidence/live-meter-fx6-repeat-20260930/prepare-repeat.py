#!/usr/bin/env python3
"""Prepare a new FX6 repeat without modifying historical candidate artifacts."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("artifact_directory", type=Path)
parser.add_argument("--candidate", choices=("incremental", "fullbuild"), required=True)
parser.add_argument("--ordinal", type=int, choices=(0, 7), required=True)
args = parser.parse_args()
repository = Path(__file__).resolve().parents[3]
baseline = Path("/private/tmp/aagedal-live-authentic-20260930")
run_name = "fx6-selected-120s" if args.candidate == "incremental" else "fullbuild-fx6-120s"
template = baseline / run_name
artifact = args.artifact_directory.resolve()
if artifact.exists():
    raise SystemExit(f"Artifact directory already exists: {artifact}")

identities = json.loads((template / "candidate-identities.json").read_text())
def digest(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as source:
        for data in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(data)
    return hasher.hexdigest()

reused_original_cache = Path("/private/tmp/aagedal-live-authentic-current-dd-20260930/Build/Products")
unlinked_original_changes = {}
verified_identities = {}
for path, expected in identities.items():
    actual = digest(path)
    # The authentic-check report records root's later reuse of this original
    # shipping-pin cache. The copied test host and linked local frameworks are
    # the measured artifacts; these two historical original receipts are not.
    if Path(path).is_relative_to(reused_original_cache):
        if actual != expected:
            unlinked_original_changes[path] = {"historical": expected, "current": actual}
        continue
    if actual != expected:
        raise SystemExit(f"Retained candidate identity changed: {path}")
    verified_identities[path] = actual

inputs = json.loads((template / "inputs.json").read_text())[:1]
inputs[0]["audioStreamOrderIndex"] = args.ordinal
inputs[0]["audioTrackSelectionExplicit"] = True
if digest(inputs[0]["path"]) != inputs[0]["sha256"]:
    raise SystemExit("The producer-original FX6 identity changed")
run = plistlib.loads((template / "candidate.xctestrun").read_bytes())
for configuration in run["TestConfigurations"]:
    for target in configuration["TestTargets"]:
        environment = target.setdefault("EnvironmentVariables", {})
        environment["LIVE_AUDIO_METER_PROFILE_INPUTS"] = json.dumps(inputs)
        environment["LIVE_AUDIO_METER_PROFILE_SECONDS"] = "5"

artifact.mkdir(parents=True)
(artifact / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
(artifact / "candidate.xctestrun").write_bytes(plistlib.dumps(run))
(artifact / "candidate-identities-before.json").write_text(json.dumps(verified_identities, indent=2) + "\n")
(artifact / "preparation.json").write_text(json.dumps({
    "candidate": args.candidate, "historicalTemplate": str(template),
    "historicalBinary": True, "includesClockFailureContextChange": False,
    "requestedAudioOrdinal": args.ordinal, "observationSeconds": 5,
    "shippingPinChanged": False,
    "unlinkedOriginalCacheChanges": unlinked_original_changes,
}, indent=2) + "\n")
environment = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository, text=True)
environment += subprocess.check_output(["git", "status", "--short"], cwd=repository, text=True)
environment += subprocess.check_output(["sw_vers"], text=True)
environment += subprocess.check_output(["xcodebuild", "-version"], text=True)
environment += "Build configuration: Release\nHistorical candidate binary; no rebuild.\nObservation seconds: 5\n"
(artifact / "environment.txt").write_text(environment)
print(artifact)
