#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# < 2 )); then
  print -u2 'Usage: profile-production-metadata-memory.sh NEW_ARTIFACT_DIRECTORY MEDIA_FILE [MEDIA_FILE ...]'
  print -u2 'Inputs must be regular media files at least 60 seconds long. Each input runs in a fresh XCTest host.'
  exit 1
fi
artifact_dir="${1:A}"
shift
if [[ -e "$artifact_dir" ]]; then
  print -u2 "Artifact directory already exists: $artifact_dir"
  exit 1
fi
inputs=()
typeset -A seen_inputs
for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    print -u2 "Media file does not exist: $input"
    exit 1
  fi
  canonical_input="${input:A}"
  if [[ -n "${seen_inputs[$canonical_input]:-}" ]]; then
    print -u2 "Duplicate input path: $canonical_input"
    exit 1
  fi
  seen_inputs[$canonical_input]=1
  inputs+=("$canonical_input")
done

mkdir -p "$artifact_dir/runs" "$artifact_dir/attachments"
derived_data="${METADATA_MEMORY_PROFILE_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-production-metadata-memory-derived}"
active_profile_run=""
cleanup() {
  if [[ -n "$active_profile_run" ]]; then
    rm -f -- "$active_profile_run"
  fi
}
trap cleanup EXIT
cd "$repository_dir"
resolved_packages='Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
cp "$resolved_packages" "$artifact_dir/Package.resolved"
{
  git rev-parse HEAD
  git status --short
  sw_vers
  system_profiler SPHardwareDataType | sed '/Serial Number/d; /Hardware UUID/d; /Provisioning UDID/d'
  xcodebuild -version
  pmset -g batt
  shasum -a 256 "$resolved_packages" \
    'Aagedal Media Player Tests/ProductionMetadataMemoryPerformanceTests.swift' \
    scripts/profile-production-metadata-memory.sh \
    scripts/validate-production-metadata-memory-profile.py
  shasum -a 256 "${inputs[@]}"
} > "$artifact_dir/environment.txt"

print -u2 'Building the production metadata memory profiling test…'
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

for (( input_index = 0; input_index < ${#inputs}; input_index++ )); do
  input="${inputs[$(( input_index + 1 ))]}"
  profile_run="$derived_data/Build/Products/ProductionMetadataMemoryProfile.$(uuidgen).xctestrun"
  active_profile_run="$profile_run"
  cp "$xctestrun_files[1]" "$profile_run"
  /usr/bin/python3 - "$profile_run" "$input" "$input_index" <<'PY'
import plistlib, sys
path, media, index = sys.argv[1:]
with open(path, 'rb') as source:
    run = plistlib.load(source)
targets = run['TestConfigurations'][0]['TestTargets']
for target in targets:
    environment = target.setdefault('EnvironmentVariables', {})
    environment['METADATA_MEMORY_PROFILE_INPUT'] = media
    environment['METADATA_MEMORY_PROFILE_INPUT_INDEX'] = index
with open(path, 'wb') as destination:
    plistlib.dump(run, destination)
PY
  run_dir="$artifact_dir/runs/input-$input_index"
  mkdir -p "$run_dir"
  print -u2 "Profiling production metadata load $(( input_index + 1 ))/${#inputs}: ${input:t}"
  if ! xcodebuild test-without-building -xctestrun "$profile_run" \
    -destination 'platform=macOS' -parallel-testing-enabled NO -test-timeouts-enabled NO \
    -resultBundlePath "$run_dir/Profile.xcresult" \
    -only-testing:'Aagedal Media Player Tests/ProductionMetadataMemoryPerformanceTests/testProductionMetadataMemoryProfileWhenRequested' \
    > "$run_dir/profile.log" 2>&1; then
    tail -n 100 "$run_dir/profile.log" >&2
    exit 1
  fi
  xcrun xcresulttool export attachments --path "$run_dir/Profile.xcresult" \
    --output-path "$artifact_dir/attachments/input-$input_index" >/dev/null
  rm -f -- "$profile_run"
  active_profile_run=""
done

/usr/bin/python3 "$repository_dir/scripts/validate-production-metadata-memory-profile.py" \
  "$artifact_dir" "${#inputs}"
print -r -- "Artifacts: $artifact_dir"
