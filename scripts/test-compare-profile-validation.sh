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
COMPARE_PROFILE_LOUPE pair=mpv/avFoundation, freshCaptures=80/80
COMPARE_PROFILE_LOUPE pair=avFoundation/mpv, freshCaptures=80/80
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
print 'Executed 10 tests, with 0 tests skipped and 0 failures' >> "$test_dir/valid.log"
validate "$test_dir/valid.log"
head -n 9 "$test_dir/valid.log" > "$test_dir/invalid.log"
expect_rejected 'missing scenario'
head -n 1 "$test_dir/valid.log" >> "$test_dir/invalid.log"
expect_rejected 'ten lines with duplicate masking missing scenario'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
head -n 1 "$test_dir/valid.log" >> "$test_dir/invalid.log"
expect_rejected 'duplicate alongside complete set'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
print 'COMPARE_PROFILE_SCOPE pair=mpv/mpv, scopeRenders=100' >> "$test_dir/invalid.log"
expect_rejected 'unexpected scenario'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
print 'COMPARE_PROFILE_UNKNOWN pair=mpv/avFoundation, samples=100' >> "$test_dir/invalid.log"
expect_rejected 'unexpected workload prefix'
/usr/bin/awk '!/^COMPARE_PROFILE_LOUPE /' "$test_dir/valid.log" > "$test_dir/invalid.log"
expect_rejected 'legacy run without loupe workloads'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
print 'COMPARE_PROFILE_LOUPE pair=mpv/avFoundation, freshCaptures=80/80' >> "$test_dir/invalid.log"
expect_rejected 'duplicate loupe workload'
cat "$test_dir/valid.log" > "$test_dir/invalid.log"
print 'COMPARE_PROFILE pair=unknown' >> "$test_dir/invalid.log"
expect_rejected 'malformed metric'
for skip in 'Test skipped: fixtures absent' "Test Case '-[Tests testProfile]' skipped (0.1 seconds)." 'Executed 10 tests, with 1 test skipped and 0 failures'; do
  cat "$test_dir/valid.log" > "$test_dir/invalid.log"
  print -r -- "$skip" >> "$test_dir/invalid.log"
  expect_rejected "$skip"
done
: > "$test_dir/invalid.log"
expect_rejected 'empty run'
print 'PASS: profile metric validation (complete, missing, duplicate, unexpected, malformed, skipped, empty)'

# Exercise the real profiler's argument and reused-manifest validation. Stop at
# the first build invocation so these checks never encode media or run Xcode.
mkdir -p "$test_dir/bin" "$test_dir/fixtures/compare"
cat > "$test_dir/bin/xcodebuild" <<'MOCK'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Mock Xcode'
  exit 0
fi
print -r -- "$1" >> "$PROFILE_VALIDATION_CALLS"
exit 73
MOCK
cat > "$test_dir/bin/ffmpeg" <<'MOCK'
#!/bin/zsh
print 'FAIL: reused-fixture validation invoked ffmpeg' >&2
print 'ffmpeg' >> "$PROFILE_VALIDATION_CALLS"
exit 74
MOCK
chmod +x "$test_dir/bin/xcodebuild" "$test_dir/bin/ffmpeg"
print 'stub source A' > "$test_dir/fixtures/compare/source-a.mov"
print 'stub source B' > "$test_dir/fixtures/compare/source-b.mov"

write_manifest() {
  {
    print 'schema=5'
    print 'size=640x360'
    print 'frame_rate=24'
    print 'duration=13'
    if [[ "$1" != legacy ]]; then print -r -- "reflected=$1"; fi
  } > "$test_dir/fixtures/MANIFEST.txt"
}

check_profile_configuration() {
  local requested="$1" expected_status="$2" expected_message="$3"
  local actual_status=0
  local reflection_environment=()
  if [[ "$requested" != default ]]; then
    reflection_environment=("COMPARE_PROFILE_REFLECTED=$requested")
  fi
  : > "$test_dir/calls.log"
  env -i \
    PATH="$test_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$test_dir/" \
    FFMPEG="$test_dir/bin/ffmpeg" \
    PROFILE_VALIDATION_CALLS="$test_dir/calls.log" \
    COMPARE_PROFILE_SIZE=640x360 \
    COMPARE_PROFILE_FRAME_RATE=24 \
    COMPARE_PROFILE_SECONDS=8 \
    COMPARE_PROFILE_REUSE_FIXTURES=1 \
    COMPARE_PROFILE_FIXTURE_DIR="$test_dir/fixtures" \
    "${reflection_environment[@]}" \
    /bin/zsh "$script_dir/profile-compare-mode.sh" \
    > "$test_dir/configuration.log" 2>&1 || actual_status=$?
  if [[ "$actual_status" != "$expected_status" ]] \
      || ! /usr/bin/grep -Fq -- "$expected_message" "$test_dir/configuration.log"; then
    print -u2 "FAIL: reflected=$requested expected status $expected_status and: $expected_message"
    cat "$test_dir/configuration.log" >&2
    exit 1
  fi
  local expected_calls=""
  if [[ "$expected_status" == 73 ]]; then expected_calls=build-for-testing; fi
  if [[ "$(cat "$test_dir/calls.log")" != "$expected_calls" ]]; then
    print -u2 "FAIL: reflected=$requested unexpectedly invoked a build or encoder"
    cat "$test_dir/calls.log" >&2
    exit 1
  fi
}

write_manifest 0
for invalid in 2 -1 true; do
  check_profile_configuration "$invalid" 1 'COMPARE_PROFILE_REFLECTED must be 0 or 1.'
done
check_profile_configuration 0 73 'Reusing validated comparison fixtures'
check_profile_configuration default 73 'Reusing validated comparison fixtures'
check_profile_configuration 1 1 'Reusable fixtures do not match this profile configuration.'
write_manifest 1
check_profile_configuration 1 73 'Reusing validated comparison fixtures'
check_profile_configuration 0 1 'Reusable fixtures do not match this profile configuration.'
write_manifest legacy
check_profile_configuration 0 73 'Reusing validated comparison fixtures'
check_profile_configuration 1 1 'Reusable fixtures do not match this profile configuration.'
write_manifest invalid
check_profile_configuration 0 1 'Reusable fixtures do not match this profile configuration.'
check_profile_configuration 1 1 'Reusable fixtures do not match this profile configuration.'
print 'PASS: reflection option and fixture reuse validation (matching, mismatched, legacy, invalid)'
