#!/bin/bash
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the optional real-ENOSPC test on a disposable 32 MiB HFS+ disk image.
# Usage: scripts/test-compare-review-disk-full.sh [xcodebuild test arguments...]
# Or: scripts/test-compare-review-disk-full.sh --xctestrun /path/to/tests.xctestrun [arguments...]
# Set AAGEDAL_DISK_FULL_FULL_SUITE=1 to run the full suite on the owned image.
# Additional arguments can select a derived-data path/configuration. The harness
# selects only this test by default and disables parallel execution.
# AAGEDAL_DISK_FULL_OUTPUT optionally chooses a new evidence directory.
set -euo pipefail
artifact_dir="${AAGEDAL_DISK_FULL_OUTPUT:-/private/tmp/aagedal-disk-full-evidence.$(date +%Y%m%dT%H%M%S).$$}"
/bin/mkdir "$artifact_dir"
artifact_dir="$(cd "$artifact_dir" && pwd)"
echo "Evidence: $artifact_dir"
exec > "$artifact_dir/run.log" 2>&1
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d /private/tmp/aagedal-disk-full.XXXXXXXX)"
mount_dir="$fixture_dir/mount"
mounted=0
test_run_copy=""
cleanup() {
    result=$?
    if [[ -n "$test_run_copy" ]]; then /bin/rm -f "$test_run_copy"; fi
    if [[ "$mounted" == 1 ]]; then
        if ! /usr/bin/hdiutil detach "$mount_dir"; then
            echo "Could not detach test image; retained fixture at $fixture_dir" >&2
            printf "Harness exit status: %s\nDetach: failed\n" "$result" > "$artifact_dir/status.txt"
            exit 1
        fi
    fi
    /bin/rm -rf "$fixture_dir"
    printf "Harness exit status: %s\nDetach: completed or not mounted\n" "$result" > "$artifact_dir/status.txt"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/bin/mkdir "$mount_dir"
/usr/bin/hdiutil create -size 32m -fs HFS+ -volname AagedalDiskFullTest "$fixture_dir/test.dmg"
/usr/bin/hdiutil attach -nobrowse -mountpoint "$mount_dir" "$fixture_dir/test.dmg"
mounted=1
# Attest the mount before giving the test permission to fill it. The XCTest
# independently checks statfs and refuses any other filesystem/mount/size.
/usr/sbin/diskutil info -plist "$mount_dir" > "$artifact_dir/volume.plist"
actual_mount="$(/usr/bin/plutil -extract MountPoint raw "$artifact_dir/volume.plist")"
actual_size="$(/usr/bin/plutil -extract TotalSize raw "$artifact_dir/volume.plist")"
[[ "$actual_mount" == "$mount_dir" && "$actual_size" =~ ^[0-9]+$ && "$actual_size" -le 41943040 && "$actual_size" -ge 8388608 ]]
token="$(/usr/bin/uuidgen)"
printf '%s' "$token" > "$mount_dir/.aagedal-disk-full-token"
export TEST_RUNNER_AAGEDAL_DISK_FULL_MOUNT="$mount_dir"
export TEST_RUNNER_AAGEDAL_DISK_FULL_TOKEN="$token"
cd "$repository_dir"
{
    git rev-parse HEAD
    git status --short
    /usr/bin/sw_vers
    /usr/bin/xcodebuild -version
    /usr/bin/shasum -a 256 scripts/test-compare-review-disk-full.sh \
        'Aagedal Media Player Tests/CompareReviewDiskFullTests.swift'
} > "$artifact_dir/environment.txt"
test_selection=(-only-testing:'Aagedal Media Player Tests/CompareReviewDiskFullTests')
if [[ "${AAGEDAL_DISK_FULL_FULL_SUITE:-0}" == 1 ]]; then
    test_selection=()
fi
if [[ "${1:-}" == --xctestrun ]]; then
    [[ $# -ge 2 && -f "$2" ]] || { echo 'Expected an existing .xctestrun file' >&2; exit 2; }
    # Keep __TESTROOT__ paths valid by placing the temporary manifest beside
    # the supplied file. The original manifest and existing ITU env stay intact.
    test_run_copy="$(/usr/bin/python3 - "$2" "$mount_dir" "$token" <<'PYTHON'
import os
import plistlib
import sys
import tempfile
source, mount, token = sys.argv[1:]
with open(source, "rb") as handle:
    manifest = plistlib.load(handle)
target_count = 0
def inject(value):
    global target_count
    if isinstance(value, dict):
        if "TestBundlePath" in value:
            environment = value.setdefault("EnvironmentVariables", {})
            environment["AAGEDAL_DISK_FULL_MOUNT"] = mount
            environment["AAGEDAL_DISK_FULL_TOKEN"] = token
            target_count += 1
        for child in value.values():
            inject(child)
    elif isinstance(value, list):
        for child in value:
            inject(child)
inject(manifest)
if not target_count:
    raise SystemExit("No test targets found in the supplied xctestrun manifest")
with tempfile.NamedTemporaryFile(prefix="AagedalDiskFull-", suffix=".xctestrun",
        dir=os.path.dirname(os.path.abspath(source)), delete=False) as handle:
    try:
        plistlib.dump(manifest, handle)
    except BaseException:
        os.unlink(handle.name)
        raise
    print(handle.name)
PYTHON
)"
    test_run="$test_run_copy"
    /bin/cp "$test_run_copy" "$artifact_dir/TestRun.xctestrun"
    shift 2
    /usr/bin/xcodebuild test-without-building -xctestrun "$test_run" \
        -destination 'platform=macOS' -resultBundlePath "$artifact_dir/Tests.xcresult" "$@" -parallel-testing-enabled NO ${test_selection[@]+"${test_selection[@]}"}
else
    /usr/bin/xcodebuild test -project 'Aagedal Media Player.xcodeproj' \
        -scheme 'Aagedal Media Player' -destination 'platform=macOS' -resultBundlePath "$artifact_dir/Tests.xcresult" "$@" \
        -parallel-testing-enabled NO ${test_selection[@]+"${test_selection[@]}"}
fi
# A skipped/missing optional test must never be reported as verified.
[[ -f "$mount_dir/.aagedal-disk-full-verified" ]] || {
    echo 'Disk-full test did not produce completion proof (missing or skipped test)' >&2
    exit 1
}
[[ "$(cat "$mount_dir/.aagedal-disk-full-verified")" == "$token" ]] || {
    echo 'Disk-full completion proof does not match this owned volume' >&2
    exit 1
}
/bin/cp "$mount_dir/.aagedal-disk-full-verified" "$artifact_dir/verified-token.txt"
/usr/bin/xcrun xcresulttool get test-results tests --path "$artifact_dir/Tests.xcresult" > "$artifact_dir/tests.json"
echo 'Verified actual ENOSPC, preservation, and recovery on the disposable image.'
