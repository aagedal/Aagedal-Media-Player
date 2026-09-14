#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# < 2 )); then
  print -u2 'Usage: profile-live-audio-meter.sh NEW_ARTIFACT_DIRECTORY MEDIA_FILE [MEDIA_FILE ...]'
  print -u2 'Use explicit representative media with at least 20 seconds of supported 44.1/48/96 kHz, 1-8 channel audio.'
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
derived_data="${LIVE_AUDIO_METER_PROFILE_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-live-audio-meter-profile-derived}"
observation_seconds="${LIVE_AUDIO_METER_PROFILE_SECONDS:-5}"
test_allowance=$((120 + 90 * ${#inputs}))
cd "$repository_dir"

/usr/bin/python3 - "$artifact_dir/inputs.json" "${inputs[@]}" <<'PY'
import hashlib, json, pathlib, sys
destination = pathlib.Path(sys.argv[1])
manifest = []
for value in sys.argv[2:]:
    path = pathlib.Path(value)
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    manifest.append({'path': str(path), 'sha256': digest.hexdigest()})
destination.write_text(json.dumps(manifest, indent=2) + '\n')
PY

{
  git rev-parse HEAD
  git status --short
  sw_vers
  system_profiler SPHardwareDataType | sed '/Serial Number/d; /Hardware UUID/d; /Provisioning UDID/d'
  xcodebuild -version
  pmset -g batt
  print -r -- "Observation seconds: $observation_seconds"
  shasum -a 256 "${inputs[@]}"
} > "$artifact_dir/environment.txt"

print -u2 'Building production live-audio-meter profiling test…'
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
if ! xcodebuild test-without-building -xctestrun "$profile_run" \
  -destination 'platform=macOS' -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance "$test_allowance" \
  -maximum-test-execution-time-allowance "$test_allowance" \
  -resultBundlePath "$artifact_dir/LiveAudioMeterProfile.xcresult" \
  -only-testing:'Aagedal Media Player Tests/LiveAudioMeterPerformanceTests/testRepresentativeProductionPathWhenRequested' \
  > "$artifact_dir/profile.log" 2>&1; then
  tail -n 120 "$artifact_dir/profile.log" >&2
  exit 1
fi
profile_end="$(date '+%Y-%m-%d %H:%M:%S')"
xcrun xcresulttool export attachments --path "$artifact_dir/LiveAudioMeterProfile.xcresult" \
  --output-path "$artifact_dir/attachments" >/dev/null
/usr/bin/python3 "$repository_dir/scripts/validate-live-audio-meter-profile.py" "$artifact_dir"
pmset -g batt > "$artifact_dir/power-end.txt"
/usr/bin/python3 "$repository_dir/scripts/check-programme-profile-power.py" \
  "$profile_start" "$profile_end" "$artifact_dir"
print -r -- "Artifacts: $artifact_dir"
