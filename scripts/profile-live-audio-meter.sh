#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# < 2 )); then
  print -u2 'Usage: profile-live-audio-meter.sh NEW_ARTIFACT_DIRECTORY [--audio-stream-order N] MEDIA_FILE [[--audio-stream-order N] MEDIA_FILE ...]'
  print -u2 'Use explicit representative media with at least 20 seconds of supported 44.1/48/96 kHz, 1-8 channel audio.'
  exit 1
fi
artifact_dir="${1:A}"
shift
if [[ -e "$artifact_dir" ]]; then
  print -u2 "Artifact directory already exists: $artifact_dir"
  exit 1
fi
# Each selector applies only to the next file. Repeating a file is allowed
# when deliberately selecting a different FFmpeg audio-only ordinal.
input_manifest="$(/usr/bin/python3 "$repository_dir/scripts/live-audio-meter-profile-inputs.py" "$@")"
input_count="$(print -r -- "$input_manifest" | /usr/bin/python3 -c 'import json, sys; print(len(json.load(sys.stdin)))')"
observation_seconds="${LIVE_AUDIO_METER_PROFILE_SECONDS:-5}"
# A sustained 30-minute observation must fit inside XCTest's deadline. Keep
# the existing setup/routing/EOF allowance in addition to each paced interval.
# Validate before creating artifacts or doing an expensive build.
test_allowance="$(/usr/bin/python3 "$repository_dir/scripts/live-audio-meter-profile-settings.py" \
  "$observation_seconds" "$input_count")"
mkdir -p "$artifact_dir"
derived_data="${LIVE_AUDIO_METER_PROFILE_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-live-audio-meter-profile-derived}"
build_configuration="${LIVE_AUDIO_METER_PROFILE_CONFIGURATION:-Release}"
if [[ "$build_configuration" != Release && "$build_configuration" != Debug ]]; then
  print -u2 'LIVE_AUDIO_METER_PROFILE_CONFIGURATION must be Release or Debug.'
  exit 1
fi
cd "$repository_dir"

print -r -- "$input_manifest" > "$artifact_dir/inputs.json"

{
  git rev-parse HEAD
  git status --short
  sw_vers
  system_profiler SPHardwareDataType | sed '/Serial Number/d; /Hardware UUID/d; /Provisioning UDID/d'
  xcodebuild -version
  pmset -g batt
  print -r -- "Observation seconds: $observation_seconds"
  print -r -- "Build configuration: $build_configuration"
  print -r -- "$input_manifest"
} > "$artifact_dir/environment.txt"

print -u2 'Building production live-audio-meter profiling test…'
if ! xcodebuild build-for-testing -project 'Aagedal Media Player.xcodeproj' \
  -scheme 'Aagedal Media Player' -configuration "$build_configuration" -destination 'platform=macOS' \
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
profile_run="$derived_data/Build/Products/LiveAudioMeterProfile.$(uuidgen).xctestrun"
trap 'rm -f -- "$profile_run"' EXIT
cp "$xctestrun_files[1]" "$profile_run"
/usr/bin/python3 - "$profile_run" "$artifact_dir/inputs.json" "$observation_seconds" <<'PY'
import json, plistlib, sys
path, manifest_path, seconds = sys.argv[1:]
with open(path, 'rb') as source:
    run = plistlib.load(source)
manifest = json.loads(open(manifest_path).read())
targets = run['TestConfigurations'][0]['TestTargets']
for target in targets:
    environment = target.setdefault('EnvironmentVariables', {})
    environment['LIVE_AUDIO_METER_PROFILE_INPUTS'] = json.dumps(manifest)
    environment['LIVE_AUDIO_METER_PROFILE_SECONDS'] = seconds
with open(path, 'wb') as destination:
    plistlib.dump(run, destination)
PY

profile_start="$(date '+%Y-%m-%d %H:%M:%S')"
print -u2 'Exercising production playback, live-meter cancellation, routing invariance and near-EOF drainage…'
profile_status=0
if ! xcodebuild test-without-building -xctestrun "$profile_run" \
  -destination 'platform=macOS' -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance "$test_allowance" \
  -maximum-test-execution-time-allowance "$test_allowance" \
  -resultBundlePath "$artifact_dir/LiveAudioMeterProfile.xcresult" \
  -only-testing:'Aagedal Media Player Tests/LiveAudioMeterPerformanceTests/testRepresentativeProductionPathWhenRequested' \
  > "$artifact_dir/profile.log" 2>&1; then
  tail -n 120 "$artifact_dir/profile.log" >&2
  profile_status=1
fi
profile_end="$(date '+%Y-%m-%d %H:%M:%S')"
# Failure diagnostics are essential to distinguish meter and native AO faults.
# Preserve them even when XCTest fails before producing a complete profile row.
xcrun xcresulttool export attachments --path "$artifact_dir/LiveAudioMeterProfile.xcresult" \
  --output-path "$artifact_dir/attachments" >/dev/null
if (( profile_status != 0 )); then
  print -u2 "Production profile failed; retained diagnostics: $artifact_dir"
  exit "$profile_status"
fi
/usr/bin/python3 "$repository_dir/scripts/validate-live-audio-meter-profile.py" "$artifact_dir"
pmset -g batt > "$artifact_dir/power-end.txt"
/usr/bin/python3 "$repository_dir/scripts/check-programme-profile-power.py" \
  "$profile_start" "$profile_end" "$artifact_dir"
print -r -- "Artifacts: $artifact_dir"
