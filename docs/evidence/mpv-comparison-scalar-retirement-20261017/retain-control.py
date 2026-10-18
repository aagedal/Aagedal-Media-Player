#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain the same-build relationship control without modifying its outcome."""
import gzip
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

root = Path.cwd()
base = Path(sys.argv[1]).resolve(strict=True)
run = base/'relationship-control'
out = Path(__file__).resolve().parent/'relationship-control'
out.mkdir(exist_ok=False)
spec = importlib.util.spec_from_file_location('runner', root/'scripts/validate-mpv-native-app.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
runner.validate_memory_diagnostics(run/'memory-diagnostics', 3, post_test=True)
for path in (run/'memory-diagnostics').glob('*.json'):
    shutil.copyfile(path, out/path.name)
summary = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                   '--path', str(run/'tests.xcresult')], text=True)
(out/'summary.json').write_text(summary)
for name in ('executed-configuration.plist', 'command.json'):
    shutil.copyfile(run/name, out/name)
for name in ('xcodebuild.log', 'action.log'):
    (out/(name+'.gz')).write_bytes(gzip.compress((run/name).read_bytes(), mtime=0))
shutil.copyfile(base/'relationship-control-runner.log', out/'runner.log')
print(summary)
