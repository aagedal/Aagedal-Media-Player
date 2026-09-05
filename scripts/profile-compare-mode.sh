#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repository_dir="${0:A:h:h}"
ffmpeg_binary="${FFMPEG:-$(command -v ffmpeg || true)}"
frame_size="${COMPARE_PROFILE_SIZE:-3840x2160}"
render_size="${COMPARE_PROFILE_RENDER_SIZE:-$frame_size}"
frame_rate="${COMPARE_PROFILE_FRAME_RATE:-24}"
observation_seconds="${COMPARE_PROFILE_SECONDS:-30}"
reuse_fixtures="${COMPARE_PROFILE_REUSE_FIXTURES:-0}"
reflected="${COMPARE_PROFILE_REFLECTED:-0}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp/}aagedal-compare-profile.XXXXXX")"
fixture_dir="${COMPARE_PROFILE_FIXTURE_DIR:-$temporary_dir/fixtures}"
fixture_dir="${fixture_dir:A}"
build_log="$temporary_dir/build.log"
profile_log="$temporary_dir/profile.log"
thermal_log="$temporary_dir/thermal.log"
thermal_sampler_pid=""
result_bundle="$temporary_dir/CompareModeProfile.xcresult"
attachments_dir="$temporary_dir/attachments"
attachments_exported=false
derived_data="${COMPARE_PROFILE_DERIVED_DATA:-$temporary_dir/DerivedData}"
derived_data="${derived_data:A}"
artifact_dir="${COMPARE_PROFILE_ARTIFACT_DIR:-}"
git_revision="$(git -C "$repository_dir" rev-parse HEAD 2>/dev/null || true)"
git_state="clean"
if [[ -n "$(git -C "$repository_dir" status --porcelain 2>/dev/null)" ]]; then
  git_state="dirty"
fi
xcode_version="$(xcodebuild -version 2>/dev/null | /usr/bin/paste -s -d ' ' - || true)"

cleanup() {
  local original_status=$?
  if [[ -n "$thermal_sampler_pid" ]]; then
    kill "$thermal_sampler_pid" 2>/dev/null || true
    wait "$thermal_sampler_pid" 2>/dev/null || true
  fi
  if (( ${+functions[retain_artifacts]} )) && [[ -d "$artifact_dir" ]]; then
    retain_artifacts || print -u2 "Could not retain every profiling artifact."
  fi
  rm -Rf -- "$temporary_dir"
  return "$original_status"
}
trap cleanup EXIT

if [[ "$reuse_fixtures" != 0 && "$reuse_fixtures" != 1 ]]; then
  print -u2 "COMPARE_PROFILE_REUSE_FIXTURES must be 0 or 1."
  exit 1
fi

if [[ "$reflected" != 0 && "$reflected" != 1 ]]; then
  print -u2 "COMPARE_PROFILE_REFLECTED must be 0 or 1."
  exit 1
fi

if ! [[ "$observation_seconds" == <8-3600> ]]; then
  print -u2 "COMPARE_PROFILE_SECONDS must be an integer from 8 through 3600."
  exit 1
fi
fixture_seconds=$((observation_seconds + 5))

size_pattern='^[1-9][0-9]*x[1-9][0-9]*$'
rate_pattern='^([1-9][0-9]*)(\.[0-9]+|/[1-9][0-9]*)?$'
if ! [[ "$frame_size" =~ $size_pattern ]]; then
  print -u2 "COMPARE_PROFILE_SIZE must use WIDTHxHEIGHT with positive integers."
  exit 1
fi

if ! [[ "$render_size" =~ $size_pattern ]]; then
  print -u2 "COMPARE_PROFILE_RENDER_SIZE must use WIDTHxHEIGHT with positive integers."
  exit 1
fi

if ! [[ "$frame_rate" =~ $rate_pattern ]]; then
  print -u2 "COMPARE_PROFILE_FRAME_RATE must be a positive number or fraction."
  exit 1
fi

if [[ -n "$artifact_dir" ]]; then
  artifact_dir="${artifact_dir:A}"
  if [[ -e "$artifact_dir" ]]; then
    print -u2 "COMPARE_PROFILE_ARTIFACT_DIR must name a new directory: $artifact_dir"
    exit 1
  fi
  mkdir -p "$artifact_dir"
fi

retain_artifacts() {
  [[ -n "$artifact_dir" ]] || return 0
  if [[ -f "$build_log" ]]; then cp "$build_log" "$artifact_dir/build.log" || return 1; fi
  if [[ -f "$profile_log" ]]; then cp "$profile_log" "$artifact_dir/profile.log" || return 1; fi
  if [[ -f "$thermal_log" ]]; then cp "$thermal_log" "$artifact_dir/thermal.log" || return 1; fi
  if [[ -f "$fixture_dir/MANIFEST.txt" ]]; then cp "$fixture_dir/MANIFEST.txt" "$artifact_dir/fixture-manifest.txt" || return 1; fi
  if [[ -d "$result_bundle" ]]; then cp -R "$result_bundle" "$artifact_dir/CompareModeProfile.xcresult" || return 1; fi
  if [[ -d "$attachments_dir" ]]; then cp -R "$attachments_dir" "$artifact_dir/attachments" || return 1; fi
  return 0
}

manifest_value() {
  local key="$1"
  /usr/bin/awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' \
    "$fixture_dir/MANIFEST.txt"
}

validate_reused_fixtures() {
  local manifest="$fixture_dir/MANIFEST.txt"
  local source_a="$fixture_dir/compare/source-a.mov"
  local source_b="$fixture_dir/compare/source-b.mov"
  if [[ ! -f "$manifest" || ! -s "$source_a" || ! -s "$source_b" ]]; then
    print -u2 "Reusable fixtures are incomplete in $fixture_dir."
    print -u2 "Run once with COMPARE_PROFILE_REUSE_FIXTURES=0 to regenerate them."
    return 1
  fi
  local fixture_reflected="$(manifest_value reflected)"
  # Older profiler manifests describe the original unreflected fixtures.
  fixture_reflected="${fixture_reflected:-0}"
  if [[ "$fixture_reflected" != "$reflected" \
        || "$(manifest_value schema)" != 5 \
        || "$(manifest_value size)" != "$frame_size" \
        || "$(manifest_value frame_rate)" != "$frame_rate" \
        || "$(manifest_value duration)" != "$fixture_seconds" ]]; then
    print -u2 "Reusable fixtures do not match this profile configuration."
    print -u2 "Run once with COMPARE_PROFILE_REUSE_FIXTURES=0 to regenerate them."
    return 1
  fi
}

if [[ "$reuse_fixtures" == 0 ]]; then
  if [[ -z "$ffmpeg_binary" || ! -x "$ffmpeg_binary" ]]; then
    print -u2 "A full ffmpeg installation is required to create profiling inputs."
    print -u2 "Install ffmpeg or set FFMPEG=/path/to/ffmpeg."
    exit 1
  fi

  encoder_list="$($ffmpeg_binary -hide_banner -encoders 2>/dev/null)"
  if [[ "$encoder_list" != *" libx265 "* ]]; then
    print -u2 "The selected ffmpeg does not include libx265: $ffmpeg_binary"
    exit 1
  fi
elif [[ -z "${COMPARE_PROFILE_FIXTURE_DIR:-}" ]]; then
  print -u2 "COMPARE_PROFILE_REUSE_FIXTURES=1 requires COMPARE_PROFILE_FIXTURE_DIR."
  exit 1
fi

mkdir -p "$fixture_dir/compare"

ffmpeg() {
  "$ffmpeg_binary" -hide_banner -loglevel error -nostdin -y "$@"
}

generate_fixture() {
  local destination="$1"
  local duration="$2"
  local tone="$3"
  local timecode="$4"
  local display_options=()
  if [[ "$reflected" == 1 ]]; then
    display_options=(-noautorotate -display_hflip:v)
  fi

  ffmpeg "${display_options[@]}" \
    -f lavfi -i "testsrc2=size=${frame_size}:rate=${frame_rate}:duration=${duration}" \
    -f lavfi -i "sine=frequency=${tone}:sample_rate=48000:duration=${duration}" \
    -map 0:v:0 -map 1:a:0 \
    -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p10le \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
    -x265-params "log-level=error:hdr10=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" \
    -tag:v hvc1 -c:a aac -timecode "$timecode" -movflags +faststart \
    "$destination"
}

if [[ "$reuse_fixtures" == 1 ]]; then
  validate_reused_fixtures
  print -u2 "Reusing validated comparison fixtures from $fixture_dir…"
else
  print -u2 "Generating $frame_size, ${frame_rate} fps, 10-bit HDR comparison fixtures…"
  generate_fixture "$fixture_dir/compare/source-a.mov" "$fixture_seconds" 440 "01:00:00:00"
  generate_fixture "$fixture_dir/compare/source-b.mov" "$((fixture_seconds + 1))" 660 "00:59:59:00"

  {
    print "Aagedal Media Player Compare Mode profiling fixtures"
    # CompareLiveBackendTests owns this contract; keep the generated profile
    # tree directly consumable by the same schema-5 fixture validator.
    print "schema=5"
    print "reflected=$reflected"
    print "size=$frame_size"
    print "frame_rate=$frame_rate"
    print "duration=$fixture_seconds"
    print "ffmpeg=$($ffmpeg_binary -hide_banner -version 2>&1 | head -n 1)"
  } > "$fixture_dir/MANIFEST.txt"
fi

cd "$repository_dir"
print -u2 "Building the Compare Mode integration tests…"
if xcodebuild build-for-testing \
  -project "Aagedal Media Player.xcodeproj" \
  -scheme "Aagedal Media Player" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data" \
  ENABLE_TESTABILITY=YES \
  -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests" \
  > "$build_log" 2>&1; then
  :
else
  build_status=$?
  tail -n 200 "$build_log" >&2
  exit "$build_status"
fi

xctestrun_files=("$derived_data"/Build/Products/*.xctestrun(N))
if (( ${#xctestrun_files} != 1 )); then
  print -u2 "Expected one xctestrun file, found ${#xctestrun_files}."
  exit 1
fi
xctestrun_file="${xctestrun_files[1]}"
test_environment_path="TestConfigurations.0.TestTargets.0.EnvironmentVariables"
set_test_environment() {
  local key="$1"
  local value="$2"
  if ! plutil -replace "$test_environment_path.$key" -string "$value" "$xctestrun_file" 2>/dev/null; then
    plutil -insert "$test_environment_path.$key" -string "$value" "$xctestrun_file"
  fi
}
set_test_environment MEDIA_FIXTURE_DIR "$fixture_dir"
set_test_environment COMPARE_SUSTAINED_PLAYBACK_SECONDS "$observation_seconds"
set_test_environment COMPARE_PROFILE_REPORT 1
set_test_environment COMPARE_PROFILE_REFLECTED "$reflected"
set_test_environment COMPARE_PROFILE_RENDER_SIZE "$render_size"

print -u2 "Profiling all four backend pairings plus mixed-backend visual and live-scope canvases for $observation_seconds seconds each…"
pre_profile_power="$(pmset -g batt 2>/dev/null | head -n 1 || true)"
pre_profile_low_power="$(pmset -g custom 2>/dev/null | /usr/bin/awk '/Power:$/ { power = $0; sub(/:$/, "", power) } /lowpowermode/ { values = values (values ? ", " : "") power "=" $NF } END { print values }' || true)"
pre_profile_thermal="$(pmset -g therm 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\{1,\}/ /g' || true)"
# Sample throughout the run: endpoint snapshots can miss transient pressure.
# pmset reports system thermal/speed-limit information, not per-process state.
(
  while true; do
    print -r -- "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    pmset -g therm 2>&1 || true
    sleep 2
  done
) > "$thermal_log" &
thermal_sampler_pid=$!
set +e
/usr/bin/time -lp \
  xcodebuild test-without-building \
    -xctestrun "$xctestrun_file" \
    -destination "platform=macOS" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$result_bundle" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testMPVPairAlignsBySourceTimecodeAndSharesTransport" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryShareTransport" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testAVFoundationPairAlignsBySourceTimecodeAndSharesTransport" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryShareTransport" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryKeepSurfacesAcrossVisualModes" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryKeepSurfacesAcrossVisualModes" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryRenderLiveComparisonScopes" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryRenderLiveComparisonScopes" \
    > "$profile_log" 2>&1
profile_status=$?
set -e
kill "$thermal_sampler_pid" 2>/dev/null || true
wait "$thermal_sampler_pid" 2>/dev/null || true
thermal_sampler_pid=""
post_profile_thermal="$(pmset -g therm 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\{1,\}/ /g' || true)"

# XCTest treats XCTSkip as a successful test process. Require each expected
# scenario exactly once, so duplicates cannot hide missing scenarios. Preserve
# xcodebuild's original failure status when validation also fails.
if ! /usr/bin/awk -f "$repository_dir/scripts/validate-compare-profile.awk" "$profile_log"; then
  if (( profile_status == 0 )); then
    profile_status=1
  fi
fi

if [[ -d "$result_bundle" ]]; then
  if ! xcrun xcresulttool export attachments \
    --path "$result_bundle" --output-path "$attachments_dir" >/dev/null; then
    print -u2 "Could not export profile attachments; falling back to the test log."
  else
    attachments_exported=true
  fi
else
  print -u2 "The test run did not produce an xcresult bundle."
fi

hardware_model="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ { print $2; exit }')"
chip="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ { print $2; exit }')"
memory="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Memory/ { print $2; exit }')"
model_identifier="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/ { print $2; exit }')"
source_a_bytes="$(stat -f %z "$fixture_dir/compare/source-a.mov" 2>/dev/null || true)"
source_b_bytes="$(stat -f %z "$fixture_dir/compare/source-b.mov" 2>/dev/null || true)"
source_a_bitrate="$(/usr/bin/awk -v file_bytes="$source_a_bytes" -v seconds="$fixture_seconds" 'BEGIN { if (file_bytes > 0 && seconds > 0) printf "%.2f", file_bytes * 8 / seconds / 1000000 }')"
source_b_bitrate="$(/usr/bin/awk -v file_bytes="$source_b_bytes" -v seconds="$((fixture_seconds + 1))" 'BEGIN { if (file_bytes > 0 && seconds > 0) printf "%.2f", file_bytes * 8 / seconds / 1000000 }')"
fixture_ffmpeg="$(manifest_value ffmpeg)"

print "# Compare Mode production-resolution profile"
print
print -r -- "- Hardware: ${hardware_model:-Unknown} / ${chip:-Unknown} / ${memory:-Unknown}"
print -r -- "- Model identifier: ${model_identifier:-Unknown}"
print -r -- "- macOS: $(sw_vers -productVersion)"
print -r -- "- Xcode: ${xcode_version:-Unknown}"
print -r -- "- Git: ${git_revision:-Unknown} ($git_state at profile start)"
print -r -- "- Power before measured run: ${pre_profile_power:-Unknown}"
print -r -- "- Low Power Mode values before measured run: ${pre_profile_low_power:-Unknown}"
print -r -- "- Thermal state before measured run: ${pre_profile_thermal:-Unavailable}"
print -r -- "- Thermal state after measured run: ${post_profile_thermal:-Unavailable}"
print -r -- "- Thermal sampling: pmset every 2 seconds during the run (thermal.log retained with raw artifacts)"
print -r -- "- Fixture: $frame_size at $frame_rate fps, HEVC Main 10, BT.2020/PQ"
print -r -- "- Container horizontal reflection (both sources): $reflected"
print -r -- "- Fixture bytes (A/B): ${source_a_bytes:-Unknown}/${source_b_bytes:-Unknown}"
print -r -- "- Approximate fixture bitrate Mbps (A/B): ${source_a_bitrate:-Unknown}/${source_b_bitrate:-Unknown}"
print -r -- "- Fixture encoder: ${fixture_ffmpeg:-Unknown}"
print -r -- "- Render surface: $render_size per decoder"
print -r -- "- Sustained observation: $observation_seconds seconds per backend pairing"
print -r -- "- Resource totals: xcodebuild command accounting; separately hosted app processes may be excluded"
print
print '```text'
if [[ "$attachments_exported" == true ]]; then
  /usr/bin/grep -R -a -h -o 'COMPARE_PROFILE.*' "$attachments_dir" 2>/dev/null || true
else
  /usr/bin/grep -a -h -o 'COMPARE_PROFILE.*' "$profile_log" 2>/dev/null || true
fi
/usr/bin/grep -a -E '\*\* TEST (SUCCEEDED|FAILED) \*\*|real |user |sys |maximum resident set size' "$profile_log" || true
print '```'
print
print 'Distinct thermal observations during the run:'
print '```text'
/usr/bin/awk '!/^timestamp=/ && NF' "$thermal_log" | /usr/bin/sort -u
print '```'
print
print "Decoder drift signposts are available in Instruments under the CompareMode category."
if [[ -n "${COMPARE_PROFILE_FIXTURE_DIR:-}" ]]; then
  print "Fixtures retained at: $fixture_dir"
fi
if [[ -n "$artifact_dir" ]]; then
  print "Raw artifacts retained at: $artifact_dir"
fi

if (( profile_status != 0 )); then
  print -u2 "Compare Mode profiling assertions failed; see the report above."
  exit "$profile_status"
fi
