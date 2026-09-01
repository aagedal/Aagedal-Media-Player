#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repository_dir="${0:A:h:h}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp/}aagedal-scope-profile.XXXXXX")"
profiler="$temporary_dir/scope-profiler"

trap 'rm -R "$temporary_dir"' EXIT

cd "$repository_dir"
xcrun swiftc \
  -O \
  -parse-as-library \
  -module-cache-path "$temporary_dir/module-cache" \
  "Aagedal Media Player/Logic/Scopes/ScopeComputer.swift" \
  "scripts/ScopeProfiler.swift" \
  -framework AppKit \
  -o "$profiler"

"$profiler"
