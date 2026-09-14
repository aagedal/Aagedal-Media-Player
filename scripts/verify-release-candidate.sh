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

repository_dir="$(git rev-parse --show-toplevel)"
artifact_dir="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$artifact_dir")"
case "$artifact_dir/" in
    "$repository_dir/"*)
        echo "ERROR: candidate evidence must be written outside the source checkout." >&2
        exit 2
        ;;
esac

project="Aagedal Media Player.xcodeproj"
scheme="Aagedal Media Player"
resolved_packages="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
derived_data="$artifact_dir/DerivedData"
source_commit="$(git rev-parse --verify HEAD)"
package_resolved_sha256="$(shasum -a 256 "$resolved_packages" | awk '{print $1}')"

if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: could not resolve HEAD to a full lowercase commit SHA." >&2
    exit 2
fi

mkdir -p "$artifact_dir"

{
    echo "sourceCommit=$source_commit"
    echo "packageResolvedSHA256=$package_resolved_sha256"
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
    -skip-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryShareTransport" \
    -skip-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryShareTransport" \
    ENABLE_TESTABILITY=YES \
    2>&1 | tee "$artifact_dir/tests.log"

echo "==> Release XCTest evidence"
xcrun xcresulttool get test-results summary \
    --path "$artifact_dir/Tests.xcresult" \
    > "$artifact_dir/test-summary.json"
xcrun xcresulttool get test-results tests \
    --path "$artifact_dir/Tests.xcresult" \
    > "$artifact_dir/test-details.json"
python3 scripts/validate-release-xcresult.py \
    "$artifact_dir/test-summary.json" \
    "$artifact_dir/test-details.json" \
    --minimum-tests 683 \
    2>&1 | tee "$artifact_dir/test-evidence-validation.log"

# The full bundle deliberately retains Xcode's process isolation and excludes
# two historically order-sensitive mixed-backend transport cases. Run those
# cases together in one fresh serial runner so candidate evidence contains an
# independent stability check and still covers all 685 tests without forcing
# every hosted decoder test into one long-lived process.
echo "==> Focused mixed-backend transport repeat"
xcodebuild test \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$artifact_dir/MixedBackendTransport.xcresult" \
    -onlyUsePackageVersionsFromResolvedFile \
    -parallel-testing-enabled NO \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryShareTransport" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryShareTransport" \
    ENABLE_TESTABILITY=YES \
    2>&1 | tee "$artifact_dir/mixed-backend-transport.log"
xcrun xcresulttool get test-results summary \
    --path "$artifact_dir/MixedBackendTransport.xcresult" \
    > "$artifact_dir/mixed-backend-transport-summary.json"
xcrun xcresulttool get test-results tests \
    --path "$artifact_dir/MixedBackendTransport.xcresult" \
    > "$artifact_dir/mixed-backend-transport-details.json"
python3 scripts/validate-release-xcresult.py \
    "$artifact_dir/mixed-backend-transport-summary.json" \
    "$artifact_dir/mixed-backend-transport-details.json" \
    --minimum-tests 2 \
    --exact-tests 2 \
    --require-test "CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryShareTransport()" \
    --require-test "CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryShareTransport()" \
    2>&1 | tee "$artifact_dir/mixed-backend-transport-validation.log"

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

echo "==> Final source identity"
if [[ "$(git rev-parse --verify HEAD)" != "$source_commit" ]]; then
    echo "ERROR: HEAD changed during candidate verification." >&2
    exit 2
fi
if [[ "$(shasum -a 256 "$resolved_packages" | awk '{print $1}')" != "$package_resolved_sha256" ]]; then
    echo "ERROR: Package.resolved changed during candidate verification." >&2
    exit 2
fi
if ! final_worktree_status="$(git status --porcelain)" || [[ -n "$final_worktree_status" ]]; then
    echo "ERROR: checkout changed during candidate verification." >&2
    exit 2
fi

{
    echo "completedAt=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "status=passed"
} >> "$artifact_dir/environment.txt"

echo "==> Candidate verification passed; evidence retained at $artifact_dir"
