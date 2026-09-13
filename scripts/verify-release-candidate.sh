#!/usr/bin/env bash
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: scripts/verify-release-candidate.sh OUTPUT_DIRECTORY" >&2
    exit 2
fi

artifact_dir="$1"
if [[ -e "$artifact_dir" ]]; then
    echo "ERROR: output already exists: $artifact_dir" >&2
    exit 2
fi

if ! worktree_status="$(git status --porcelain)"; then
    echo "ERROR: could not inspect the release-candidate checkout." >&2
    exit 2
fi
if [[ -n "$worktree_status" ]]; then
    echo "ERROR: release-candidate verification requires a clean checkout." >&2
    echo "Commit or stash every tracked and untracked change, then retry." >&2
    exit 2
fi

project="Aagedal Media Player.xcodeproj"
scheme="Aagedal Media Player"
resolved_packages="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
derived_data="$artifact_dir/DerivedData"

mkdir -p "$artifact_dir"

{
    echo "sourceCommit=$(git rev-parse HEAD)"
    echo "packageResolvedSHA256=$(shasum -a 256 "$resolved_packages" | awk '{print $1}')"
    echo "startedAt=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "host=$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    xcodebuild -version
} > "$artifact_dir/environment.txt"

echo "==> Script-validator self-tests"
scripts/test-script-validators.sh 2>&1 | tee "$artifact_dir/script-validator-tests.log"

echo "==> Optimized Release tests"
xcodebuild test \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$artifact_dir/Tests.xcresult" \
    -onlyUsePackageVersionsFromResolvedFile \
    ENABLE_TESTABILITY=YES \
    2>&1 | tee "$artifact_dir/tests.log"

echo "==> Release static analysis"
xcodebuild analyze \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data" \
    -onlyUsePackageVersionsFromResolvedFile \
    2>&1 | tee "$artifact_dir/analyze.log"

echo "==> Source-tree release preflight"
python3 scripts/release-preflight.py 2>&1 | tee "$artifact_dir/preflight.log"

{
    echo "completedAt=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "status=passed"
} >> "$artifact_dir/environment.txt"

echo "==> Candidate verification passed; evidence retained at $artifact_dir"
