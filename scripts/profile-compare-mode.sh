#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repository_dir="${0:A:h:h}"
ffmpeg_binary="${FFMPEG:-$(command -v ffmpeg || true)}"
frame_size="${COMPARE_PROFILE_SIZE:-3840x2160}"
frame_rate="${COMPARE_PROFILE_FRAME_RATE:-24}"
observation_seconds="${COMPARE_PROFILE_SECONDS:-30}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp/}aagedal-compare-profile.XXXXXX")"
fixture_dir="${COMPARE_PROFILE_FIXTURE_DIR:-$temporary_dir/fixtures}"
build_log="$temporary_dir/build.log"
profile_log="$temporary_dir/profile.log"
result_bundle="$temporary_dir/CompareModeProfile.xcresult"
attachments_dir="$temporary_dir/attachments"
profile_config="$repository_dir/Test Fixtures/Generated/COMPARE_PROFILE.conf"
profile_config_created=false

cleanup() {
  if [[ "$profile_config_created" == true ]]; then
    rm -f "$profile_config"
  fi
  rm -R "$temporary_dir"
}
trap cleanup EXIT

if [[ -z "$ffmpeg_binary" || ! -x "$ffmpeg_binary" ]]; then
  print -u2 "A full ffmpeg installation is required to create profiling inputs."
  print -u2 "Install ffmpeg or set FFMPEG=/path/to/ffmpeg."
  exit 1
fi

if ! [[ "$observation_seconds" == <8-3600> ]]; then
  print -u2 "COMPARE_PROFILE_SECONDS must be an integer from 8 through 3600."
  exit 1
fi
fixture_seconds=$((observation_seconds + 5))

encoder_list="$($ffmpeg_binary -hide_banner -encoders 2>/dev/null)"
if [[ "$encoder_list" != *" libx265 "* ]]; then
  print -u2 "The selected ffmpeg does not include libx265: $ffmpeg_binary"
  exit 1
fi

mkdir -p "$fixture_dir/compare"
mkdir -p "${profile_config:h}"
if [[ -e "$profile_config" ]]; then
  print -u2 "A Compare Mode profile is already active: $profile_config"
  exit 1
fi

ffmpeg() {
  "$ffmpeg_binary" -hide_banner -loglevel error -nostdin -y "$@"
}

generate_fixture() {
  local destination="$1"
  local duration="$2"
  local tone="$3"
  local timecode="$4"

  ffmpeg \
    -f lavfi -i "testsrc2=size=${frame_size}:rate=${frame_rate}:duration=${duration}" \
    -f lavfi -i "sine=frequency=${tone}:sample_rate=48000:duration=${duration}" \
    -map 0:v:0 -map 1:a:0 \
    -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p10le \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
    -x265-params "log-level=error:hdr10=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" \
    -tag:v hvc1 -c:a aac -timecode "$timecode" -movflags +faststart \
    "$destination"
}

print -u2 "Generating $frame_size, ${frame_rate} fps, 10-bit HDR comparison fixtures…"
generate_fixture "$fixture_dir/compare/source-a.mov" "$fixture_seconds" 440 "01:00:00:00"
generate_fixture "$fixture_dir/compare/source-b.mov" "$((fixture_seconds + 1))" 660 "00:59:59:00"

{
  print "Aagedal Media Player Compare Mode profiling fixtures"
  print "schema=3"
  print "size=$frame_size"
  print "frame_rate=$frame_rate"
  print "duration=$fixture_seconds"
  print "ffmpeg=$($ffmpeg_binary -hide_banner -version 2>&1 | head -n 1)"
} > "$fixture_dir/MANIFEST.txt"

profile_config_created=true
{
  print "fixture_dir=$fixture_dir"
  print "seconds=$observation_seconds"
  print "report=1"
} > "$profile_config"

cd "$repository_dir"
print -u2 "Building the Compare Mode integration tests…"
if ! xcodebuild build-for-testing \
  -project "Aagedal Media Player.xcodeproj" \
  -scheme "Aagedal Media Player" \
  -destination "platform=macOS" \
  -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests" \
  > "$build_log" 2>&1; then
  tail -n 200 "$build_log" >&2
  exit 1
fi

print -u2 "Profiling all four backend pairings for $observation_seconds seconds each…"
set +e
/usr/bin/time -lp env \
  MEDIA_FIXTURE_DIR="$fixture_dir" \
  COMPARE_SUSTAINED_PLAYBACK_SECONDS="$observation_seconds" \
  COMPARE_PROFILE_REPORT=1 \
  xcodebuild test-without-building \
    -project "Aagedal Media Player.xcodeproj" \
    -scheme "Aagedal Media Player" \
    -destination "platform=macOS" \
    -resultBundlePath "$result_bundle" \
    -only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests" \
    > "$profile_log" 2>&1
profile_status=$?
set -e

xcrun xcresulttool export attachments \
  --path "$result_bundle" --output-path "$attachments_dir" >/dev/null

hardware_model="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ { print $2; exit }')"
chip="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ { print $2; exit }')"
memory="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Memory/ { print $2; exit }')"

print "# Compare Mode production-resolution profile"
print
print -r -- "- Hardware: ${hardware_model:-Unknown} / ${chip:-Unknown} / ${memory:-Unknown}"
print -r -- "- macOS: $(sw_vers -productVersion)"
print -r -- "- Fixture: $frame_size at $frame_rate fps, HEVC Main 10, BT.2020/PQ"
print -r -- "- Sustained observation: $observation_seconds seconds per backend pairing"
print
print '```text'
rg --no-filename -o 'COMPARE_PROFILE.*' "$attachments_dir" || true
rg '\*\* TEST (SUCCEEDED|FAILED) \*\*|real |user |sys |maximum resident set size' "$profile_log" || true
print '```'
print
print "Decoder drift signposts are available in Instruments under the CompareMode category."
if [[ -n "${COMPARE_PROFILE_FIXTURE_DIR:-}" ]]; then
  print "Fixtures retained at: $fixture_dir"
fi

if (( profile_status != 0 )); then
  print -u2 "Compare Mode profiling assertions failed; see the report above."
  exit "$profile_status"
fi
