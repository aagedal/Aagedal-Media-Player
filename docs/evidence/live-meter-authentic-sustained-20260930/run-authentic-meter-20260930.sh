#!/bin/zsh
set -euo pipefail
repository_dir='/Users/truls.aagedal/Developer/Aagedal-Media-Player'
artifact_dir="${1:A}"
[[ -d "$artifact_dir" && -f "$artifact_dir/candidate.xctestrun" && ! -e "$artifact_dir/LiveAudioMeterProfile.xcresult" ]]
seconds=$(/usr/bin/python3 - "$artifact_dir/candidate.xctestrun" <<'PY'
import sys,plistlib
r=plistlib.load(open(sys.argv[1],'rb'))
print(r['TestConfigurations'][0]['TestTargets'][0]['EnvironmentVariables']['LIVE_AUDIO_METER_PROFILE_SECONDS'])
PY
)
input_count=$(/usr/bin/python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$artifact_dir/inputs.json")
allowance=$(/usr/bin/python3 "$repository_dir/scripts/live-audio-meter-profile-settings.py" "$seconds" "$input_count")
cd "$repository_dir"
/usr/bin/pmset -g batt > "$artifact_dir/power-start.txt"
/bin/ps -axo pid,pcpu,comm | /usr/bin/awk '/clang|xcodebuild|ninja|ffmpeg|Media Player/ { print }' > "$artifact_dir/concurrent-processes-start.txt"
start=$(date '+%Y-%m-%d %H:%M:%S')
print -r -- "$start" > "$artifact_dir/profile-start.txt"
profile_status=0
if ! /usr/bin/xcodebuild test-without-building -xctestrun "$artifact_dir/candidate.xctestrun" \
 -destination 'platform=macOS' -parallel-testing-enabled NO -test-timeouts-enabled YES \
 -default-test-execution-time-allowance "$allowance" -maximum-test-execution-time-allowance "$allowance" \
 -resultBundlePath "$artifact_dir/LiveAudioMeterProfile.xcresult" \
 -only-testing:'Aagedal Media Player Tests/LiveAudioMeterPerformanceTests/testRepresentativeProductionPathWhenRequested' \
 > "$artifact_dir/profile.log" 2>&1; then
 profile_status=1
fi
end=$(date '+%Y-%m-%d %H:%M:%S')
print -r -- "$end" > "$artifact_dir/profile-end.txt"
/usr/bin/xcrun xcresulttool export attachments --path "$artifact_dir/LiveAudioMeterProfile.xcresult" --output-path "$artifact_dir/attachments" >/dev/null
/usr/bin/pmset -g batt > "$artifact_dir/power-end.txt"
/usr/bin/python3 "$repository_dir/scripts/check-programme-profile-power.py" "$start" "$end" "$artifact_dir"
if (( profile_status != 0 )); then
 tail -n 100 "$artifact_dir/profile.log"
 exit "$profile_status"
fi
/usr/bin/python3 "$repository_dir/scripts/validate-live-audio-meter-profile.py" "$artifact_dir"
print -r -- "Artifacts: $artifact_dir"
