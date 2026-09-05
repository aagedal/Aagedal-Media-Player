#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
script_dir="${0:A:h}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp/}compare-profile-validation.XXXXXX")"
trap 'rm -Rf -- "$test_dir"' EXIT
cat > "$test_dir/valid.log" <<'METRICS'
COMPARE_PROFILE pair=mpv/mpv, samples=100
COMPARE_PROFILE pair=mpv/avFoundation, samples=100
COMPARE_PROFILE pair=avFoundation/avFoundation, samples=100
COMPARE_PROFILE pair=avFoundation/mpv, samples=100
COMPARE_PROFILE_VISUAL pair=mpv/avFoundation, visualUpdates=100
COMPARE_PROFILE_VISUAL pair=avFoundation/mpv, visualUpdates=100
COMPARE_PROFILE_SCOPE pair=mpv/avFoundation, scopeRenders=100
COMPARE_PROFILE_SCOPE pair=avFoundation/mpv, scopeRenders=100
METRICS
validate() {
  /usr/bin/awk -f "$script_dir/validate-compare-profile.awk" "$1" 2> "$test_dir/errors.log"
}
expect_rejected() {
  if validate "$test_dir/invalid.log"; then
    print -u2 "FAIL: accepted $1"
    exit 1
  fi
}
print 'Executed 8 tests, with 0 tests skipped and 0 failures' >> "$test_dir/valid.log"
validate "$test_dir/valid.log"
head -n 7 "$test_dir/valid.log" > "$test_dir/invalid.log"
expect_rejected 'missing scenario'
head -n 1 "$test_dir/valid.log" >> "$test_dir/invalid.log"
expect_rejected 'eight lines with duplicate masking missing scenario'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
head -n 1 "$test_dir/valid.log" >> "$test_dir/invalid.log"
expect_rejected 'duplicate alongside complete set'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
print 'COMPARE_PROFILE_SCOPE pair=mpv/mpv, scopeRenders=100' >> "$test_dir/invalid.log"
expect_rejected 'unexpected scenario'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
print 'COMPARE_PROFILE pair=unknown' >> "$test_dir/invalid.log"
expect_rejected 'malformed metric'
for skip in 'Test skipped: fixtures absent' "Test Case '-[Tests testProfile]' skipped (0.1 seconds)." 'Executed 8 tests, with 1 test skipped and 0 failures'; do
  cat "$test_dir/valid.log" > "$test_dir/invalid.log"
  print -r -- "$skip" >> "$test_dir/invalid.log"
  expect_rejected "$skip"
done
: > "$test_dir/invalid.log"
expect_rejected 'empty run'
print 'PASS: profile metric validation (complete, missing, duplicate, unexpected, malformed, skipped, empty)'
