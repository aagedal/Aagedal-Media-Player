#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the retained arm64 candidate's focused checks and instrumented workload."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

root = Path.cwd()
evidence = Path(__file__).resolve().parent
base = Path('/private/tmp/aagedal-allocation-stacks-20261018')
products = base / 'derived/Build/Products'
xctestrun = next(products.glob('*.xctestrun'))
app = products / 'Release/Aagedal Media Player.app'
live = Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json')

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

inputs = [xctestrun, base/'native-fixtures.json', live,
          app/'Contents/MacOS/Aagedal Media Player',
          app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',
          *sorted(evidence.glob('*.py')),
          *[root/'scripts'/p for p in ('validate-mpv-native-app.py', 'test-mpv-native-app-runner.py',
                                      'collect-mpv-allocation-stacks.py', 'test-mpv-allocation-stacks.py')]]
(base/'execution-inputs.json').write_text(json.dumps({str(p): sha(p) for p in inputs}, indent=2)+'\n')
with (base/'signature-verification.txt').open('w') as log:
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
for name, script in [('runner', 'test-mpv-native-app-runner.py'), ('collector', 'test-mpv-allocation-stacks.py')]:
    with (base/f'{name}-regressions.log').open('w') as log:
        subprocess.run([sys.executable, str(root/'scripts'/script)], stdout=log, stderr=subprocess.STDOUT, check=True)
command = [sys.executable, str(evidence/'run-focused.py'), str(xctestrun), str(base/'native-fixtures.json'),
           '/private/tmp/aagedal-continuation-20261016-fixtures',
           '/private/tmp/aagedal-scopes-delta-restored-r3-20261015/delta/validation/signal-fixtures',
           str(live), str(base/'focused')]
with (base/'focused-runner.log').open('w') as log:
    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
command = [sys.executable, str(root/'scripts/validate-mpv-native-app.py'), str(xctestrun), str(live),
           str(base/'soak'), '--comparison', '--active-scopes', '--scope-provenance', '--memory-diagnostics',
           '--scalar-memory-diagnostics', '--allocation-stacks', '--post-test-retirement',
           '--scope-resolution', '720', '--scope-fps', '15', '--soak-seconds', '10', '--soak-cycles', '3']
(base/'soak-command.json').write_text(json.dumps(command, indent=2)+'\n')
with (base/'soak-runner.log').open('w') as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
# Always extract a summary, including instrumented rejection or collector failure.
summary = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                          '--path', str(base/'soak/tests.xcresult')], capture_output=True, text=True)
(base/'soak-summary.json').write_text(summary.stdout)
(base/'validation-result.json').write_text(json.dumps({'runnerExitCode': result.returncode,
    'summaryExitCode': summary.returncode}, indent=2)+'\n')
raise SystemExit(result.returncode or summary.returncode)
