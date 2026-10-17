#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain complete same-build scalar control, preserving its independent outcome."""
import gzip
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import re
import shutil
import subprocess

root = Path.cwd()
base = Path('/private/tmp/aagedal-scope-failure-provenance-20261018')
run = base/'scalar-control'
out = Path(__file__).resolve().parent/'scalar-control'
for path, expected in json.loads((base/'scalar-control-execution-inputs.json').read_text()).items():
    assert hashlib.file_digest(Path(path).open('rb'), 'sha256').hexdigest() == expected, path
spec = importlib.util.spec_from_file_location('runner', root/'scripts/validate-mpv-native-app.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
runner.validate_memory_diagnostics(run/'memory-diagnostics', 3, post_test=True, scalar_only=True)
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                              '--path', str(run/'tests.xcresult')], text=True))
out.mkdir(exist_ok=False)
(out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
for path in (run/'memory-diagnostics').glob('*.json'):
    shutil.copyfile(path, out/path.name)
for name in ('executed-configuration.plist', 'command.json'):
    shutil.copyfile(run/name, out/name)
for name in ('xcodebuild.log', 'action.log'):
    (out/(name+'.gz')).write_bytes(gzip.compress((run/name).read_bytes(), mtime=0))
shutil.copyfile(base/'scalar-control-execution-inputs.json', out/'execution-inputs.json')
shutil.copyfile(base/'scalar-control-runner.log', out/'runner.log')

def outputs(node):
    if isinstance(node, dict):
        if node.get('testName') == 'testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory()' and isinstance(node.get('emittedOutput'), str):
            yield node['emittedOutput']
        for value in node.values():
            yield from outputs(value)
    elif isinstance(node, list):
        for value in node:
            yield from outputs(value)

text = list(outputs(json.loads((run/'action.log').read_text())))
assert len(text) == 1
text = text[0]
rejected = summary['result'] != 'Passed'
required = [
    'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,',
    'MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 3 scope sources, 10 seconds per selection, resolution=720, targetFPS=15',
    'MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per selection, resolution=720, targetFPS=15, exact difference pixels and occupied bins, capture retirement and resume']
assert all(re.search(re.escape(marker) + r'(?=$|[\s])', text) for marker in required)

lines = [line.strip() for line in text.splitlines() if 'MPV_COMPARISON_' in line or 'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE:' in line]
(out/'measurements.txt').write_text('\n'.join(lines)+'\n')
loupe = [line for line in lines if 'MPV_COMPARISON_LOUPE_WINDOW:' in line]
scopes = [line for line in lines if 'MPV_COMPARISON_SCOPE_WINDOW:' in line]
pixels = [line for line in lines if 'MPV_COMPARISON_DIFFERENCE_PUBLICATION:' in line]
resumes = [line for line in lines if 'MPV_COMPARISON_DIFFERENCE_RESUME:' in line]
cycles = [line for line in lines if 'MPV_COMPARISON_LOUPE_SOAK_CYCLE:' in line]
def numbers(pattern, rows):
    return [float(re.search(pattern, line)[1]) for line in rows]

fps = numbers(r'fps=([\d.]+)', loupe)
drift = numbers(r'maxDrift=([\d.eE+-]+)', loupe)
valid = numbers(r'validSamples=(\d+)/30', loupe)
footprints = numbers(r'physicalFootprintBytes=(\d+)', cycles)
coverage = {}
for line in scopes:
    key = tuple(re.search(pattern, line)[1] for pattern in (r'cycle=(\d+)', r'pair=([^,]+)', r'mode=([^,]+)', r'selection=([^,]+)'))
    coverage[key] = max(coverage.get(key, 0), float(re.search(r'measuredSeconds=([\d.]+)', line)[1]))
pairs = ['uhd-h264-hardware/pq-hevc-hardware', 'pq-hevc-hardware/hlg-hevc-hardware']
expected = set(itertools.product(['1', '2', '3'], pairs, ['sideBySide', 'verticalWipe', 'overlay'], ['primary', 'secondary', 'difference']))
assert set(coverage) == expected and min(coverage.values()) >= 10, coverage
assert all('resolution=720, targetFPS=15,' in line for line in scopes)
def identity(line, fields):
    return tuple(re.search(rf'{field}=([^,]+)', line)[1] for field in fields)
def unique_keys(rows, fields):
    keys = [identity(line, fields) for line in rows]
    assert len(keys) == len(set(keys)), 'Duplicate measurement identity'
    return set(keys)
fields = ['cycle', 'pair', 'mode', 'window']
scope_keys = unique_keys(scopes, fields+['selection'])
loupe_keys = unique_keys(loupe, fields+['scopeSelection', 'source'])
assert loupe_keys == {(*key, source) for key in scope_keys for source in ['0', '1']}
difference_keys = unique_keys([line for line in scopes if 'selection=difference,' in line], fields)
assert unique_keys(pixels, fields) == difference_keys
assert unique_keys(resumes, ['cycle', 'pair']) == set(itertools.product(['1', '2', '3'], pairs))
assert [identity(line, ['cycle'])[0] for line in cycles] == ['1', '2', '3']
assert len(footprints) == 3
for cycle, footprint in enumerate(footprints, 1):
    sample = json.loads((out/f'cycle-{cycle}.json').read_text())
    assert sample['gatePhysicalFootprintBytes'] == int(footprint)
    counts = sample['retirement']
    for label in ('host', 'window', 'primaryController', 'secondaryController', 'comparisonController',
                  'loupeState', 'primaryLoupeCapture', 'secondaryLoupeCapture', 'primaryScopeCapture',
                  'secondaryScopeCapture', 'scopeProbe', 'scopeWorker', 'loupeSurface', 'loupeLayer',
                  'loupeSession', 'followerPlayer', 'primaryPlayer', 'secondaryPlayer'):
        assert counts[label]['observed'] >= cycle * 2, (cycle, label, counts)

memory_passed = max(footprints) - footprints[0] <= 268435456
cadence_passed = min(fps) >= 45
clock_passed = max(drift) <= .1 and min(valid) >= 29
if not rejected:
    assert memory_passed and cadence_passed and clock_passed
assert len(pixels) == sum('selection=difference,' in line for line in scopes)
assert len(resumes) == 6
assert all(n == 291600 for n in numbers(r'pixels=(\d+)', pixels+resumes))

windows = [line for line in lines if line.startswith('MPV_COMPARISON_LOUPE_WINDOW:')]
scopes = [line for line in lines if line.startswith('MPV_COMPARISON_SCOPE_WINDOW:')]
def values(pattern, rows):
    return [float(re.search(pattern, row)[1]) for row in rows]
cycles = [json.loads((run/'memory-diagnostics'/f'cycle-{n}.json').read_text()) for n in range(1, 4)]
footprints = [sample['gatePhysicalFootprintBytes'] for sample in cycles]
runner_accepted = 'Native app acceptance passed; logs and xcresult:' in (base/'scalar-control-runner.log').read_text()
stats = dict(
    result=summary['result'],
    accepted=not rejected and memory_passed and cadence_passed and clock_passed and runner_accepted,
    memoryGatePassed=memory_passed, cadenceGatePassed=cadence_passed, clockGatePassed=clock_passed,
    minimumMeasuredSecondsPerSelection=min(coverage.values()), measuredSelections=len(coverage),
    analysisScriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    actionLogSHA256=hashlib.sha256((run/'action.log').read_bytes()).hexdigest(),
    executionInputsSHA256=hashlib.sha256((base/'scalar-control-execution-inputs.json').read_bytes()).hexdigest(),
    loupeWindows=len(windows), scopeWindows=len(scopes),
    sampledDifferencePublications=sum(line.startswith('MPV_COMPARISON_DIFFERENCE_PUBLICATION:') for line in lines),
    resumedDifferencePublications=sum(line.startswith('MPV_COMPARISON_DIFFERENCE_RESUME:') for line in lines),
    minimumLoupePresentationsPerSecond=min(values(r'fps=([\d.]+)', windows)),
    maximumFollowerDriftSeconds=max(values(r'maxDrift=([\d.eE+-]+)', windows)),
    usableClockSamples=int(sum(values(r'validSamples=(\d+)/30', windows))),
    totalClockSamples=len(windows)*30,
    cycleEndFootprintBytes=footprints,
    maximumCycleEndGrowthBytes=max(footprints)-footprints[0],
    aliveByCheckpoint={p.stem:{key:value['alive'] for key,value in json.loads(p.read_text())['retirement'].items() if value['alive']}
                       for p in sorted((run/'memory-diagnostics').glob('*.json'))}
)
(out/'stats.json').write_text(json.dumps(stats, indent=2)+'\n')
print(json.dumps(stats, indent=2))
assert runner_accepted
assert summary['result'] == 'Passed' and summary['passedTests'] == 2 and summary['failedTests'] == 0 and summary['skippedTests'] == 0
assert memory_passed and cadence_passed and clock_passed
