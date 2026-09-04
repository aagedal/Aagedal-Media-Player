#!/bin/bash

# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_dir="$(cd "$script_dir/.." && pwd)"
output_dir="${1:-$repository_dir/Test Fixtures/Generated}"
ffmpeg_binary="${FFMPEG:-$(command -v ffmpeg || true)}"

if [[ -z "$ffmpeg_binary" || ! -x "$ffmpeg_binary" ]]; then
    echo "A full ffmpeg installation is required. Set FFMPEG=/path/to/ffmpeg." >&2
    exit 1
fi

encoder_list="$($ffmpeg_binary -hide_banner -encoders 2>/dev/null)"
for required_encoder in libx264 libx265 alac; do
    if ! grep -q " $required_encoder " <<< "$encoder_list"; then
        echo "The selected ffmpeg does not include $required_encoder: $ffmpeg_binary" >&2
        echo "The app's bundled image-only ffmpeg cannot generate the media fixtures." >&2
        exit 1
    fi
done

mkdir -p "$output_dir/rates"
mkdir -p "$output_dir/drop-frame-boundaries"
mkdir -p "$output_dir/compare"
workspace_dir="$(mktemp -d "${TMPDIR:-/tmp}/aagedal-media-fixtures.XXXXXX")"
trap 'rm -rf "$workspace_dir"' EXIT

ffmpeg() {
    "$ffmpeg_binary" -hide_banner -loglevel error -nostdin -y "$@"
}

generate_rate_fixture() {
    local name="$1"
    local rate="$2"
    ffmpeg \
        -f lavfi -i "testsrc2=size=160x90:rate=$rate:duration=0.5" \
        -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
        -movflags +faststart "$output_dir/rates/$name.mp4"
}

generate_rate_fixture "23.976" "24000/1001"
generate_rate_fixture "24" "24"
generate_rate_fixture "25" "25"
generate_rate_fixture "29.97" "30000/1001"
generate_rate_fixture "30" "30"
generate_rate_fixture "50" "50"
generate_rate_fixture "59.94" "60000/1001"
generate_rate_fixture "60" "60"

generate_drop_frame_fixture() {
    local name="$1"
    local rate="$2"
    local timecode="$3"
    ffmpeg \
        -f lavfi -i "testsrc2=size=160x90:rate=$rate:duration=0.5" \
        -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
        -timecode "$timecode" -movflags +faststart \
        "$output_dir/drop-frame-boundaries/$name.mov"
}

generate_drop_frame_fixture "29.97-minute" "30000/1001" "00:00:59;28"
generate_drop_frame_fixture "29.97-ten-minute" "30000/1001" "00:09:59;28"
generate_drop_frame_fixture "29.97-hour" "30000/1001" "00:59:59;28"
generate_drop_frame_fixture "29.97-day-wrap" "30000/1001" "23:59:59;28"
generate_drop_frame_fixture "59.94-minute" "60000/1001" "00:00:59;56"

# Comparison masters with a one-second source-timecode offset. Twelve seconds
# of overlap leaves enough headroom for the real-decoder tests to observe
# sustained playback without reaching EOF.
# Source A starts at 01:00:00:00 while B starts at 00:59:59:00, so A time
# 00:00:00:00 maps to B time 00:00:01:00. Both files are intentionally
# AVFoundation-compatible even though normal playback selects MPV; the live
# Compare Mode integration tests force each backend to exercise MPV/MPV,
# AVFoundation/AVFoundation, and both mixed directions with the same pair.
ffmpeg \
    -f lavfi -i "testsrc2=size=320x180:rate=24:duration=12" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=12" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -crf 28 \
    -pix_fmt yuv420p -c:a aac -timecode "01:00:00:00" \
    -movflags +faststart "$output_dir/compare/source-a.mov"

ffmpeg \
    -f lavfi -i "testsrc2=size=320x180:rate=24:duration=13" \
    -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=13" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -crf 28 \
    -pix_fmt yuv420p -c:a aac -timecode "00:59:59:00" \
    -movflags +faststart "$output_dir/compare/source-b.mov"

# A pair without embedded timecode verifies the relative-timeline fallback.
# It deliberately differs in codec, coded raster, frame rate, duration, and
# audio codec so the live Compare Mode tests exercise an ordinary source/master
# mismatch instead of another identical pair.
ffmpeg \
    -f lavfi -i "testsrc2=size=320x180:rate=24:duration=5" \
    -f lavfi -i "sine=frequency=550:sample_rate=48000:duration=5" \
    -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -crf 28 \
    -pix_fmt yuv420p -c:a aac -movflags +faststart \
    "$output_dir/compare/relative-a.mov"

ffmpeg \
    -f lavfi -i "testsrc2=size=240x180:rate=25:duration=6" \
    -f lavfi -i "sine=frequency=770:sample_rate=48000:duration=6" \
    -map 0:v:0 -map 1:a:0 -c:v libx265 -preset ultrafast -crf 30 \
    -pix_fmt yuv420p -tag:v hvc1 -c:a alac -movflags +faststart \
    "$output_dir/compare/relative-b.mov"

# This clip starts an hour after source-a.mov ends. Compare Mode should retain
# its source-timecode mapping, report no shared interval, and clamp B to its
# first frame when A is at the beginning of its own timeline.
ffmpeg \
    -f lavfi -i "testsrc2=size=320x180:rate=24:duration=4" \
    -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -timecode "02:00:00:00" -movflags +faststart \
    "$output_dir/compare/disjoint-b.mov"

# Coded 720x576 with 64:45 PAR gives a 16:9 display grid. The display matrix
# then rotates the presentation by 90 degrees without physically rotating the
# encoded frames.
ffmpeg \
    -noautorotate -display_rotation:v 90 \
    -f lavfi -i "testsrc2=size=720x576:rate=25:duration=2" \
    -vf "setsar=64/45" -an -c:v libx264 -preset ultrafast -crf 28 \
    -pix_fmt yuv420p -movflags +faststart "$output_dir/rotation-par.mp4"

# A physically portrait square-pixel source with the same 9:16 display aspect
# as rotation-par.mp4. Comparing the pair verifies that display geometry is
# normalized from metadata rather than from either coded raster.
ffmpeg \
    -f lavfi -i "testsrc2=size=324x576:rate=25:duration=2" \
    -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -movflags +faststart "$output_dir/portrait.mp4"

# A small HDR10 clip carrying BT.2020/PQ, mastering-display, and MaxCLL/MaxFALL
# metadata. repeat-headers keeps the metadata available to prefix-only readers.
ffmpeg \
    -f lavfi -i "testsrc2=size=160x90:rate=24:duration=2" \
    -an -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p10le \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
    -x265-params "log-level=error:hdr10=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,50):max-cll=1000,400" \
    -tag:v hvc1 -movflags +faststart "$output_dir/hdr10.mp4"

# An explicitly tagged SDR partner for hdr10.mp4. Keeping both clips at the
# same rate and duration isolates the color-system mismatch in Compare Mode.
ffmpeg \
    -f lavfi -i "testsrc2=size=160x90:rate=24:duration=2" \
    -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
    -movflags +faststart "$output_dir/sdr-bt709.mp4"

# Six independently identifiable channels in standard 5.1 order.
ffmpeg \
    -f lavfi -i "aevalsrc=sin(2*PI*220*t)|sin(2*PI*330*t)|sin(2*PI*440*t)|sin(2*PI*55*t)|sin(2*PI*550*t)|sin(2*PI*660*t):s=48000:d=1:c=5.1" \
    -c:a alac -sample_fmt s32p -movflags +faststart "$output_dir/multichannel-5.1.m4a"

printf '%s\n' \
    '1' \
    '00:00:00,000 --> 00:00:01,500' \
    'Opening subtitle' \
    '' \
    '2' \
    '00:00:02,000 --> 00:00:04,500' \
    'Closing subtitle' > "$workspace_dir/subtitles.srt"

printf '%s\n' \
    ';FFMETADATA1' \
    '[CHAPTER]' \
    'TIMEBASE=1/1000' \
    'START=0' \
    'END=2500' \
    'title=Opening' \
    '[CHAPTER]' \
    'TIMEBASE=1/1000' \
    'START=2500' \
    'END=5000' \
    'title=Closing' > "$workspace_dir/chapters.ffmetadata"

# Five seconds at 25 fps with only the first frame as a keyframe. The same
# Matroska fixture also covers subtitle and chapter parsing.
ffmpeg \
    -f lavfi -i "testsrc2=size=320x180:rate=25:duration=5" \
    -f srt -i "$workspace_dir/subtitles.srt" \
    -f ffmetadata -i "$workspace_dir/chapters.ffmetadata" \
    -map 0:v:0 -map 1:s:0 -map_metadata 2 \
    -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -g 250 -keyint_min 250 -sc_threshold 0 \
    -c:s srt -metadata:s:s:0 language=eng -metadata:s:s:0 title="English" \
    -disposition:s:0 default "$output_dir/chapters-subtitles-long-gop.mkv"

printf '%s\n' \
    'Aagedal Media Player generated media fixtures' \
    'schema=5' \
    "ffmpeg=$($ffmpeg_binary -hide_banner -version 2>&1 | head -n 1)" \
    > "$output_dir/MANIFEST.txt"

echo "Generated test fixtures in $output_dir"
