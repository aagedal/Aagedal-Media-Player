#!/bin/zsh
set -uo pipefail
root=/private/tmp/aagedal-gpl-metal-meter-repeat-20260930
/usr/bin/caffeinate -disu -w $$ &
awake_pid=$!
trap 'kill "$awake_pid" 2>/dev/null || true' EXIT
for name in fx6-120s aac-90s dts-30s ac3-30s; do
 /bin/zsh /Users/truls.aagedal/Developer/Aagedal-Media-Player/docs/evidence/live-meter-authentic-sustained-20260930/run-authentic-meter-20260930.sh "$root/$name" > "$root/$name/runner.log" 2>&1
 result=$?
 print "$name exit=$result"
done
