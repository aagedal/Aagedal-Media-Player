#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# < 2 )); then
  print -u2 'Usage: profile-programme-loudness.sh NEW_ARTIFACT_DIRECTORY MEDIA_FILE [MEDIA_FILE ...]'
  print -u2 'Inputs must contain at least eight mono audio tracks and be at least 60 seconds long. Keep native app automation idle during the run.'
  exit 1
fi
artifact_dir="${1:A}"
shift
if [[ -e "$artifact_dir" ]]; then
  print -u2 "Artifact directory already exists: $artifact_dir"
  exit 1
fi
inputs=()
for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    print -u2 "Media file does not exist: $input"
    exit 1
  fi
  inputs+=("${input:A}")
done
mkdir -p "$artifact_dir"
derived_data="${PROGRAMME_LOUDNESS_PROFILE_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-programme-loudness-profile-derived}"
cd "$repository_dir"
# Keep long decodes awake without changing persistent system preferences.
profile_run=''
/usr/bin/caffeinate -disu -w "$$" &
power_assertion_pid=$!
cleanup() {
  if [[ -n "$profile_run" ]]; then rm -f -- "$profile_run"; fi
  kill "$power_assertion_pid" 2>/dev/null || true
}
trap cleanup EXIT
{
  git rev-parse HEAD
  git status --short
  sw_vers
  system_profiler SPHardwareDataType | sed '/Serial Number/d; /Hardware UUID/d; /Provisioning UDID/d'
  xcodebuild -version
  pmset -g batt
  shasum -a 256 "${inputs[@]}"
} > "$artifact_dir/environment.txt"

print -u2 'Building production loudness profiling tests…'
if ! xcodebuild build-for-testing -project 'Aagedal Media Player.xcodeproj' \
  -scheme 'Aagedal Media Player' -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" ENABLE_TESTABILITY=YES \
  > "$artifact_dir/build.log" 2>&1; then
  tail -n 100 "$artifact_dir/build.log" >&2
  exit 1
fi
xctestrun_files=("$derived_data"/Build/Products/*.xctestrun(N))
if (( ${#xctestrun_files} != 1 )); then
  print -u2 'Expected exactly one xctestrun file.'
  exit 1
fi
# Copy beside the original so relative __TESTROOT__ paths remain valid; do
# not leave profile environment variables in a shared build's test manifest.
profile_run="$derived_data/Build/Products/ProgrammeLoudnessProfile.$(uuidgen).xctestrun"
cp "$xctestrun_files[1]" "$profile_run"
/usr/bin/python3 - "$profile_run" "${inputs[@]}" <<'PY'
import json, plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    run = plistlib.load(source)
targets = run['TestConfigurations'][0]['TestTargets']
for target in targets:
    target.setdefault('EnvironmentVariables', {})['PROGRAMME_LOUDNESS_PROFILE_INPUTS'] = json.dumps(sys.argv[2:])
with open(path, 'wb') as destination:
    plistlib.dump(run, destination)
PY
profile_start="$(date '+%Y-%m-%d %H:%M:%S')"
pmset -g batt > "$artifact_dir/power-start.txt"
print -u2 'Measuring whole-file and early/late 30-second stereo and 5.1 split-mono loudness…'
profile_status=0
if ! xcodebuild test-without-building -xctestrun "$profile_run" \
  -destination 'platform=macOS' -parallel-testing-enabled NO -test-timeouts-enabled NO \
  -resultBundlePath "$artifact_dir/ProgrammeLoudnessProfile.xcresult" \
  -only-testing:'Aagedal Media Player Tests/ProgrammeLoudnessPerformanceTests/testProductionProgrammeLoudnessProfileWhenRequested' \
  > "$artifact_dir/profile.log" 2>&1; then
  tail -n 100 "$artifact_dir/profile.log" >&2
  profile_status=1
fi
profile_end="$(date '+%Y-%m-%d %H:%M:%S')"
# Retain completed workloads and power diagnostics even if XCTest fails.
pmset -g batt > "$artifact_dir/power-end.txt"
power_status=0
if ! /usr/bin/python3 "$repository_dir/scripts/check-programme-profile-power.py" "$profile_start" "$profile_end" "$artifact_dir"; then
  power_status=1
fi
xcrun xcresulttool export attachments --path "$artifact_dir/ProgrammeLoudnessProfile.xcresult" \
  --output-path "$artifact_dir/attachments" >/dev/null
if (( profile_status != 0 || power_status != 0 )); then
  print -u2 "Production programme profile failed; retained diagnostics: $artifact_dir"
  exit 1
fi
/usr/bin/python3 "$repository_dir/scripts/validate-programme-loudness-profile.py" "$artifact_dir" "${#inputs}"
print -r -- "Artifacts: $artifact_dir"
