#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repository_dir="${0:A:h:h}"
output_dir="${1:-$repository_dir/build/Compare Mode Demo}"
output_dir="${output_dir:A}"
ffmpeg_binary="${FFMPEG:-$(command -v ffmpeg || true)}"
ffprobe_binary="${FFPROBE:-$(command -v ffprobe || true)}"
frame_size="${COMPARE_DEMO_SIZE:-1920x1080}"
duration="${COMPARE_DEMO_SECONDS:-18}"
frame_rate=24
source_a="$output_dir/Source A - reference.mov"
source_b="$output_dir/Source B - delivery encode.mov"
manifest="$output_dir/MANIFEST.txt"

if [[ -z "$ffmpeg_binary" || ! -x "$ffmpeg_binary" ]]; then
  print -u2 "A full ffmpeg installation is required. Set FFMPEG=/path/to/ffmpeg."
  exit 1
fi

if [[ -z "$ffprobe_binary" || ! -x "$ffprobe_binary" ]]; then
  print -u2 "ffprobe is required to validate the demo files. Set FFPROBE=/path/to/ffprobe."
  exit 1
fi

if ! [[ "$duration" == <4-120> ]]; then
  print -u2 "COMPARE_DEMO_SECONDS must be an integer from 4 through 120."
  exit 1
fi

size_pattern='^[1-9][0-9]*x[1-9][0-9]*$'
if ! [[ "$frame_size" =~ $size_pattern ]]; then
  print -u2 "COMPARE_DEMO_SIZE must use WIDTHxHEIGHT with positive integers."
  exit 1
fi

encoder_list="$($ffmpeg_binary -hide_banner -encoders 2>/dev/null)"
for encoder in libx264 libx265; do
  if [[ "$encoder_list" != *" $encoder "* ]]; then
    print -u2 "The selected ffmpeg does not include $encoder: $ffmpeg_binary"
    exit 1
  fi
done

if [[ -e "$source_a" || -e "$source_b" || -e "$manifest" ]]; then
  print -u2 "Demo output already exists in $output_dir."
  print -u2 "Choose a new directory or remove the old generated fixtures explicitly."
  exit 1
fi

mkdir -p "$output_dir"

ffmpeg() {
  "$ffmpeg_binary" -hide_banner -loglevel error -nostdin "$@"
}

print -u2 "Generating the high-detail source master…"
ffmpeg \
  -f lavfi \
  -i "testsrc2=size=${frame_size}:rate=${frame_rate}:duration=${duration},noise=alls=8:allf=t+u:all_seed=20260905" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=${duration}" \
  -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -preset slow -crf 10 -pix_fmt yuv420p \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
  -c:a pcm_s24le -timecode "01:00:00:00" -movflags +faststart \
  "$source_a"

print -u2 "Deriving the delivery encode from the source master…"
ffmpeg \
  -ss 1 -i "$source_a" -t "$((duration - 2))" \
  -map 0:v:0 -map 0:a:0 \
  -c:v libx265 -preset medium -crf 34 -pix_fmt yuv420p \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
  -x265-params "log-level=error:repeat-headers=1" -tag:v hvc1 \
  -c:a aac -b:a 160k -timecode "01:00:01:00" -movflags +faststart \
  "$source_b"

probe_codec() {
  "$ffprobe_binary" -v error -select_streams v:0 \
    -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1" \
    | /usr/bin/awk 'NF { print; exit }'
}

probe_timecodes() {
  "$ffprobe_binary" -v error \
    -show_entries format_tags=timecode:stream_tags=timecode \
    -of default=noprint_wrappers=1:nokey=1 "$1"
}

if [[ "$(probe_codec "$source_a")" != h264 ]]; then
  print -u2 "Source A codec validation failed."
  exit 1
fi
if [[ "$(probe_codec "$source_b")" != hevc ]]; then
  print -u2 "Source B codec validation failed."
  exit 1
fi
if [[ "$(probe_timecodes "$source_a")" != *"01:00:00:00"* ]]; then
  print -u2 "Source A timecode validation failed."
  exit 1
fi
if [[ "$(probe_timecodes "$source_b")" != *"01:00:01:00"* ]]; then
  print -u2 "Source B timecode validation failed."
  exit 1
fi

{
  print "Aagedal Media Player Compare Mode demo fixtures"
  print "schema=1"
  print "size=$frame_size"
  print "frame_rate=$frame_rate"
  print "source_a_timecode=01:00:00:00"
  print "source_b_timecode=01:00:01:00"
  print "source_a_sha256=$(shasum -a 256 "$source_a" | /usr/bin/awk '{ print $1 }')"
  print "source_b_sha256=$(shasum -a 256 "$source_b" | /usr/bin/awk '{ print $1 }')"
  print "ffmpeg=$($ffmpeg_binary -hide_banner -version 2>&1 | head -n 1)"
} > "$manifest"

print "Compare Mode demo fixtures are ready:"
print "  A: $source_a"
print "  B: $source_b"
print "  Manifest: $manifest"
