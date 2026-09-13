#!/usr/bin/env bash
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later

# Run the fast, self-contained tests for release/profile validation helpers.
# External-reference checks, production profilers, fixture generators, and the
# disk-image exhaustion harness remain explicit opt-ins and are not run here.

set -euo pipefail

repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_dir"

echo "==> Script syntax"
for script in scripts/*.py; do
    python3 -c \
        'import ast, pathlib, sys; path = pathlib.Path(sys.argv[1]); ast.parse(path.read_text(), filename=str(path))' \
        "$script"
done
for script in scripts/*.sh; do
    case "$(head -n 1 "$script")" in
        *zsh*) interpreter=/bin/zsh ;;
        *bash*) interpreter=/bin/bash ;;
        *)
            echo "ERROR: unsupported shell interpreter in $script" >&2
            exit 1
            ;;
    esac
    if ! syntax_diagnostics=$("$interpreter" -n "$script" 2>&1); then
        echo "$syntax_diagnostics" >&2
        exit 1
    fi
done

python_tests=(
    scripts/test-audio-loudness-profile-validation.py
    scripts/test-github-release-asset-validation.py
    scripts/test-homebrew-cask-update.py
    scripts/test-itu-programme-lra-reference.py
    scripts/test-itu-programme-true-peak-reference.py
    scripts/test-metadata-candidate-validation.py
    scripts/test-metadata-cli-validation.py
    scripts/test-metadata-jxl-diagnostic.py
    scripts/test-metadata-library-fixture-validation.py
    scripts/test-metadata-memory-profile-validation.py
    scripts/test-production-metadata-memory-profile-validation.py
    scripts/test-programme-loudness-profile-validation.py
    scripts/test-programme-profile-power.py
    scripts/test-release-script-validation.py
    scripts/test-release-xcresult-validation.py
    scripts/test_native_review_disk_full.py
)

for test_script in "${python_tests[@]}"; do
    echo "==> $test_script"
    PYTHONDONTWRITEBYTECODE=1 python3 "$test_script"
done

echo "==> scripts/test-compare-profile-validation.sh"
/bin/zsh scripts/test-compare-profile-validation.sh

echo "==> Script-validator self-tests passed"
