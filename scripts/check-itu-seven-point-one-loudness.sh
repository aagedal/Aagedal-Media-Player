#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# != 2 )); then
  print -u2 'Usage: check-itu-seven-point-one-loudness.sh NEW_ARTIFACT_DIRECTORY REFERENCE_DIRECTORY'
  print -u2 'Provide the original ITU 1770Conf-23LKFS-8channel.wav file. Keep native app automation idle during the run.'
  exit 1
fi
artifact_dir="${1:A}"
reference_dir="${2:A}"
if [[ -e "$artifact_dir" ]]; then
  print -u2 "Artifact directory already exists: $artifact_dir"
  exit 1
fi
inputs=(
  "$reference_dir/1770Conf-23LKFS-8channel.wav"
)
for input in "${inputs[@]}"; do
  if [[ ! -f "$input" ]]; then
    print -u2 "Missing official reference: $input"
    exit 1
  fi
done
mkdir -p "$artifact_dir"
derived_data="${ITU_7_1_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-itu-7-1-derived}"
cd "$repository_dir"
{
  git rev-parse HEAD
  git status --short
  sw_vers
  xcodebuild -version
  shasum -a 256 "${inputs[@]}"
} > "$artifact_dir/environment.txt"

print -u2 'Building production ITU 7.1 reference test…'
if ! xcodebuild build-for-testing -project 'Aagedal Media Player.xcodeproj' \
  -scheme 'Aagedal Media Player' -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" -onlyUsePackageVersionsFromResolvedFile ENABLE_TESTABILITY=YES \
  > "$artifact_dir/build.log" 2>&1; then
  tail -n 100 "$artifact_dir/build.log" >&2
  exit 1
fi
xctestrun_files=("$derived_data"/Build/Products/*.xctestrun(N))
if (( ${#xctestrun_files} != 1 )); then
  print -u2 'Expected exactly one xctestrun file.'
  exit 1
fi
# Keep __TESTROOT__ relative paths valid without altering the shared manifest.
reference_run="$derived_data/Build/Products/ITUSevenPointOne.$(uuidgen).xctestrun"
trap 'rm -f -- "$reference_run"' EXIT
cp "$xctestrun_files[1]" "$reference_run"
/usr/bin/python3 - "$reference_run" "$reference_dir" <<'PY'
import plistlib, sys
path, directory = sys.argv[1:]
with open(path, 'rb') as source:
    run = plistlib.load(source)
for configuration in run['TestConfigurations']:
    for target in configuration['TestTargets']:
        target.setdefault('EnvironmentVariables', {})['ITU_7_1_REFERENCE_DIRECTORY'] = directory
with open(path, 'wb') as destination:
    plistlib.dump(run, destination)
PY
print -u2 'Checking the official eight-channel gain reference…'
if ! xcodebuild test-without-building -xctestrun "$reference_run" \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -resultBundlePath "$artifact_dir/ITUSevenPointOneLoudness.xcresult" \
  -only-testing:'Aagedal Media Player Tests/ITUSevenPointOneLoudnessTests/testOfficialEightChannelReferenceWhenRequested' \
  > "$artifact_dir/test.log" 2>&1; then
  tail -n 100 "$artifact_dir/test.log" >&2
  exit 1
fi
xcrun xcresulttool export attachments --path "$artifact_dir/ITUSevenPointOneLoudness.xcresult" \
  --output-path "$artifact_dir/attachments" >/dev/null
# A test that returned because its environment was absent must not appear as a
# successful reference run. Require the prepared reference measurement attachment.
/usr/bin/python3 - "$artifact_dir" <<'PY'
import json, math, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = []
for path in (root / 'attachments').rglob('*'):
    if path.is_file():
        for line in path.read_text(errors='replace').splitlines():
            if line.startswith('ITU_7_1_LOUDNESS '):
                rows.append(json.loads(line.removeprefix('ITU_7_1_LOUDNESS ')))
if len(rows) != 1:
    raise SystemExit('Missing or duplicate ITU 7.1 measurement attachment')
row = rows[0]
value = float(row['integratedLUFS'])
expected = {
    'file': '1770Conf-23LKFS-8channel.wav',
    'sourceSHA256': '421f7441bbc7c0a922148f9b68d50640a8ab251bf2ceca376188fbbb952a240c',
    'preparedPCMSHA256': '3c585490610ff8e14d9e80c6967a2a0b848cc3d4cc8a4181642403daa4142f72',
    'channels': 8, 'sampleRate': 48000, 'channelLayout': '7.1',
    'weightingCorrection': 'bs1770Conventional7Point1RearChannels',
    'expectedIntegratedLUFS': -23.0, 'toleranceLU': 0.1,
}
if not math.isfinite(value) or abs(value + 23) > 0.1000001 or any(row.get(k) != v for k, v in expected.items()):
    raise SystemExit('Invalid ITU prepared 7.1 reference result')
(root / 'measurements.json').write_text(json.dumps(rows, indent=2, sort_keys=True) + '\n')
print('Official prepared 7.1 integrated loudness reference passed. LRA and true peak are observations only.')
PY
print -r -- "Artifacts: $artifact_dir"
