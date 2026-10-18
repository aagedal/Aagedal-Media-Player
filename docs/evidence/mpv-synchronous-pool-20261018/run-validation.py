#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run arm64 focused validation and retain scalar synchronous pool observations."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

root = Path.cwd()
evidence = Path(__file__).resolve().parent
base = Path('/private/tmp/aagedal-synchronous-pool-20261018')
products = base / 'derived/Build/Products'
xctestrun, = products.glob('*.xctestrun')
app = products / 'Release/Aagedal Media Player.app'
inputs = [root/'Aagedal Media Player Tests/LiveLoupeSessionTests.swift', xctestrun,
          app/'Contents/MacOS/Aagedal Media Player',
          app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',
          *sorted(evidence.glob('*.py'))]
if sys.argv[1:] not in ([], ['--collect-existing']):
    raise SystemExit('Usage: run-validation.py [--collect-existing]')
if '--collect-existing' not in sys.argv[1:]:
    with (base/'signature-verification.txt').open('w') as log:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    (base/'execution-inputs.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in inputs}, indent=2)+'\n')
    command = [sys.executable, str(evidence/'run-focused.py'), str(xctestrun), str(base/'native-fixtures.json'),
               '/private/tmp/aagedal-continuation-20261016-fixtures',
               '/private/tmp/aagedal-scopes-delta-restored-r3-20261015/delta/validation/signal-fixtures',
               '/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json', str(base/'focused')]
    with (base/'focused-runner.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(result.returncode)
# xcresulttool wraps the action text in JSON and escapes embedded receipts.
# Extract the unescaped line from the retained xcodebuild stdout instead.
focused = json.loads((base/'focused/summary.json').read_text())
assert focused['result'] == 'Passed' and focused['failedTests'] == 0 and focused['skippedTests'] == 0
assert focused['passedTests'] == 77 and not focused['runtimeWarnings']
text = (base/'focused/xcodebuild.log').read_text()
prefix = 'MPV_COMPARISON_SYNCHRONOUS_POOL_OBSERVATIONS: '
receipts = [json.loads(line.split(prefix, 1)[1]) for line in text.splitlines() if prefix in line]
if len(receipts) != 1:
    raise SystemExit('Expected exactly one synchronous pool receipt')
receipt = receipts[0]
assert receipt['independentOuterPools'] and not receipt['pumpsRunLoop'] and not receipt['inspectsRelationships']
observations = receipt['observations']
assert len(observations) == 144
stages = ['after-close', 'after-inner-boundary', 'before-outer-drain', 'after-outer-drain']
summary = []
for content in ['bare', 'appkit', 'swiftui']:
    for arm in ['outer', 'nested']:
        for stage in stages:
            rows = [r for r in observations if (r['content'], r['arm'], r['checkpoint']) == (content, arm, stage)]
            assert len(rows) == 6 and {r['iteration'] for r in rows} == set(range(1, 7))
            for row in rows:
                assert row['armOrder'] == (['nested', 'outer'] if row['iteration'] % 2 == 0 else ['outer', 'nested'])
                objects = row['objects']
                assert len(objects) == (2 if content == 'bare' else 3)
                assert len({o['id'] for o in objects}) == len(objects)
                assert all('window' not in o and 'view' not in o for o in objects)
                assert not any(o['alive'] for o in objects if o['label'] == 'arcSentinel')
            summary.append(dict(content=content, arm=arm, checkpoint=stage, iterations=6,
                survivingWindows=sum(o['alive'] for r in rows for o in r['objects'] if o['label'] == 'window'),
                survivingHosts=sum(o['alive'] for r in rows for o in r['objects'] if o['label'] == 'host')))
(base/'pool-observations.json').write_text(json.dumps(receipt, indent=2)+'\n')
(base/'pool-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print('Verified 144 scalar observations across 36 synchronous window lifecycles; see pool-summary.json')

(base/'collection-inputs.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in [Path(__file__), base/'focused/xcodebuild.log', base/'focused/summary.json']}, indent=2)+'\n')
