#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repository_dir="${0:A:h:h}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp/}aagedal-audio-waveform-profile.XXXXXX")"
profiler="$temporary_dir/audio-waveform-profiler"
decoder="${FFMPEG_DECODER:-$repository_dir/Aagedal Media Player/Binaries/ffmpeg}"
generator="${FFMPEG:-$(command -v ffmpeg || true)}"

trap 'rm -R "$temporary_dir"' EXIT

if [[ -z "$generator" || ! -x "$generator" ]]; then
  print -u2 "A full ffmpeg installation is required to create profiling inputs."
  print -u2 "Install ffmpeg or set FFMPEG=/path/to/ffmpeg."
  exit 1
fi

if [[ ! -x "$decoder" ]]; then
  print -u2 "The selected waveform decoder is not executable: $decoder"
  exit 1
fi

formats="$("$generator" -hide_banner -formats 2>/dev/null)"
if [[ "$formats" != *lavfi* ]]; then
  print -u2 "The selected ffmpeg does not provide the lavfi input used by this profiler."
  exit 1
fi

cd "$repository_dir"
xcrun swiftc \
  -O \
  -parse-as-library \
  -module-cache-path "$temporary_dir/module-cache" \
  "Aagedal Media Player/Logic/StreamingWaveformAccumulator.swift" \
  "scripts/AudioWaveformProfiler.swift" \
  -o "$profiler"

print '| Duration | Channels | Columns | Decode rate | Elapsed | Accumulators | Resident delta |'
print '| ---: | ---: | ---: | ---: | ---: | ---: | ---: |'

for hours in 1 8 24; do
  seconds=$((hours * 3600))
  input="$temporary_dir/${hours}h-7.1.wav"
  "$generator" \
    -hide_banner -loglevel error -nostdin -y \
    -f lavfi -i 'anullsrc=r=100:cl=7.1' \
    -t "$seconds" -c:a pcm_s16le "$input"
  "$profiler" "$decoder" "$input" "$seconds" 8
  rm "$input"
done
