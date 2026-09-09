#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# != 2 )); then
  print -u2 'Usage: check-itu-programme-loudness.sh NEW_ARTIFACT_DIRECTORY REFERENCE_DIRECTORY'
  print -u2 'Provide the original ITU mono, stereo, and centre-voice 5.1 -23 LKFS WAV files. Keep native app automation idle during the run.'
  exit 1
fi
artifact_dir="${1:A}"
reference_dir="${2:A}"
if [[ -e "$artifact_dir" ]]; then
  print -u2 "Artifact directory already exists: $artifact_dir"
  exit 1
fi
inputs=(
  "$reference_dir/1770-2 Conf Mono Voice+Music-23LKFS.wav"
  "$reference_dir/1770-2 Conf Stereo VinL+R-23LKFS.wav"
  "$reference_dir/1770-2 Conf 6ch VinCntr-23LKFS.wav"
)
for input in "${inputs[@]}"; do
  if [[ ! -f "$input" ]]; then
    print -u2 "Missing official reference: $input"
    exit 1
  fi
done
mkdir -p "$artifact_dir"
derived_data="${ITU_LOUDNESS_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-itu-loudness-derived}"
cd "$repository_dir"
{
  git rev-parse HEAD
  git status --short
  sw_vers
  xcodebuild -version
  shasum -a 256 "${inputs[@]}"
} > "$artifact_dir/environment.txt"

print -u2 'Building production ITU programme reference tests…'
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
reference_run="$derived_data/Build/Products/ITUProgramme.$(uuidgen).xctestrun"
trap 'rm -f -- "$reference_run"' EXIT
cp "$xctestrun_files[1]" "$reference_run"
/usr/bin/python3 - "$reference_run" "$reference_dir" <<'PY'
import plistlib, sys
path, directory = sys.argv[1:]
with open(path, 'rb') as source:
    run = plistlib.load(source)
for configuration in run['TestConfigurations']:
    for target in configuration['TestTargets']:
        target.setdefault('EnvironmentVariables', {})['ITU_LOUDNESS_REFERENCE_DIRECTORY'] = directory
with open(path, 'wb') as destination:
    plistlib.dump(run, destination)
PY
print -u2 'Checking the three official programme loudness references…'
if ! xcodebuild test-without-building -xctestrun "$reference_run" \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -resultBundlePath "$artifact_dir/ITUProgrammeLoudness.xcresult" \
  -only-testing:'Aagedal Media Player Tests/ITUProgrammeLoudnessTests/testOfficialProgrammeReferencesWhenRequested' \
  > "$artifact_dir/test.log" 2>&1; then
  tail -n 100 "$artifact_dir/test.log" >&2
  exit 1
fi
xcrun xcresulttool export attachments --path "$artifact_dir/ITUProgrammeLoudness.xcresult" \
  --output-path "$artifact_dir/attachments" >/dev/null
# A test that returned because its environment was absent must not appear as a
# successful reference run. Require all three distinct measurement attachments.
/usr/bin/python3 - "$artifact_dir" <<'PY'
import json, math, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = []
for path in (root / 'attachments').rglob('*'):
    if path.is_file():
        for line in path.read_text(errors='replace').splitlines():
            if line.startswith('ITU_PROGRAMME_LOUDNESS '):
                rows.append(json.loads(line.removeprefix('ITU_PROGRAMME_LOUDNESS ')))
if len(rows) != 3 or {row['channels'] for row in rows} != {1, 2, 6}:
    raise SystemExit('Missing or duplicate ITU programme measurement attachments')
for row in rows:
    value = float(row['integratedLUFS'])
    if not math.isfinite(value) or abs(value + 23) > 0.1000001 or row['sampleRate'] != 48000:
        raise SystemExit(f'Invalid ITU programme result: {row["file"]}')
(root / 'measurements.json').write_text(json.dumps(rows, indent=2, sort_keys=True) + '\n')
print('All three official integrated loudness references passed. Checking independently calculated programme LRA next.')
PY
print -u2 'Validating the independent PCM LRA calculator against analytic references…'
if ! /usr/bin/python3 scripts/test-itu-programme-lra-reference.py \
  > "$artifact_dir/lra-calculator-tests.log" 2>&1; then
  cat "$artifact_dir/lra-calculator-tests.log" >&2
  exit 1
fi
# Keep the precise independent implementation alongside its hash and results.
cp scripts/itu-programme-lra-reference.py scripts/test-itu-programme-lra-reference.py "$artifact_dir/"
print -u2 'Comparing programme LRA to the independent PCM calculation…'
/usr/bin/python3 scripts/itu-programme-lra-reference.py "$reference_dir" \
  "$artifact_dir/measurements.json" "$artifact_dir/independent-lra-comparison.json" \
  | tee "$artifact_dir/lra-comparison.log"
print -u2 'Validating the independent true-peak FIR calculator…'
if ! /usr/bin/python3 scripts/test-itu-programme-true-peak-reference.py \
  > "$artifact_dir/true-peak-calculator-tests.log" 2>&1; then
  cat "$artifact_dir/true-peak-calculator-tests.log" >&2
  exit 1
fi
cp scripts/itu-programme-true-peak-reference.py scripts/test-itu-programme-true-peak-reference.py "$artifact_dir/"
print -u2 'Comparing programme true peak to the independent PCM calculation…'
/usr/bin/python3 scripts/itu-programme-true-peak-reference.py "$reference_dir" \
  "$artifact_dir/measurements.json" "$artifact_dir/independent-true-peak-comparison.json" \
  | tee "$artifact_dir/true-peak-comparison.log"
print -r -- "Artifacts: $artifact_dir"
