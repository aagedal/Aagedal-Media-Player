#!/bin/zsh
set -euo pipefail
artifact_dir=/private/tmp/aagedal-dts-lossless-native-20260930
/usr/bin/caffeinate -disu -w $$ &
awake_pid=$!
trap 'kill "$awake_pid" 2>/dev/null || true' EXIT
/bin/zsh /Users/truls.aagedal/Developer/Aagedal-Media-Player/docs/evidence/live-meter-authentic-sustained-20260930/run-authentic-meter-20260930.sh "$artifact_dir"
