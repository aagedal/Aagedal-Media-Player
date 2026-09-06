#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

repository_dir="${0:A:h:h}"
if (( $# < 2 )); then
  print -u2 'Usage: profile-timeline-thumbnails.sh NEW_ARTIFACT_DIRECTORY MEDIA_FILE [MEDIA_FILE ...]'
  print -u2 'Inputs must contain video and be at least 40 seconds long. Keep native app automation idle during the run.'
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
derived_data="${TIMELINE_PROFILE_DERIVED_DATA:-${TMPDIR:-/tmp/}aagedal-timeline-profile-derived}"
cd "$repository_dir"
{
  git rev-parse HEAD
  git status --short
  sw_vers
  system_profiler SPHardwareDataType | sed '/Serial Number/d; /Hardware UUID/d; /Provisioning UDID/d'
  xcodebuild -version
  pmset -g batt
  shasum -a 256 "${inputs[@]}"
} > "$artifact_dir/environment.txt"

print -u2 'Building production thumbnail profiling tests…'
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
profile_run="$derived_data/Build/Products/TimelineProfile.$(uuidgen).xctestrun"
trap 'rm -f -- "$profile_run"' EXIT
cp "$xctestrun_files[1]" "$profile_run"
/usr/bin/python3 - "$profile_run" "${inputs[@]}" <<'PY'
import json, plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    run = plistlib.load(source)
targets = run['TestConfigurations'][0]['TestTargets']
for target in targets:
    target.setdefault('EnvironmentVariables', {})['TIMELINE_PROFILE_INPUTS'] = json.dumps(sys.argv[2:])
with open(path, 'wb') as destination:
    plistlib.dump(run, destination)
PY
print -u2 'Measuring 40 distributed cold seeks per file, including the production hover delay…'
if ! xcodebuild test-without-building -xctestrun "$profile_run" \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -resultBundlePath "$artifact_dir/TimelineProfile.xcresult" \
  -only-testing:'Aagedal Media Player Tests/TimelineThumbnailLoaderTests/testProductionThumbnailProfileWhenRequested' \
  > "$artifact_dir/profile.log" 2>&1; then
  tail -n 100 "$artifact_dir/profile.log" >&2
  exit 1
fi
xcrun xcresulttool export attachments --path "$artifact_dir/TimelineProfile.xcresult" \
  --output-path "$artifact_dir/attachments" >/dev/null
/usr/bin/python3 - "$artifact_dir" "${#inputs}" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = []
for path in (root / 'attachments').rglob('*'):
    if path.is_file():
        for line in path.read_text(errors='replace').splitlines():
            if line.startswith('TIMELINE_PROFILE '):
                row = json.loads(line.removeprefix('TIMELINE_PROFILE '))
                if row['samples'] != 40 or row['cachedImages'] != 32:
                    raise SystemExit('Incomplete thumbnail profile')
                rows.append(row)
if len(rows) != int(sys.argv[2]):
    raise SystemExit(f'Expected {sys.argv[2]} profile records, got {len(rows)}')
(root / 'summary.json').write_text(json.dumps(rows, indent=2) + '\n')
for row in rows:
    print(json.dumps(row, sort_keys=True))
PY
print -r -- "Artifacts: $artifact_dir"
