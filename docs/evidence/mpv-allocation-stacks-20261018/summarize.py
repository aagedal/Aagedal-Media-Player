#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarize a complete retained workload, including rejected gates."""
from pathlib import Path
import itertools
import json
import re
base = Path('/private/tmp/aagedal-allocation-stacks-20261018')
out = Path(__file__).resolve().parent
rejected = json.loads((base/'validation-result.json').read_text())['runnerExitCode'] != 0
def write(name, value):
    (out/name).write_text(json.dumps(value, indent=2)+'\n')
def emitted_output(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if (key == 'emittedOutput' and isinstance(value, str)
                    and node.get('testName') == 'testSustainedComparisonCanvasKeepsPairedLoupesAndBoundsMemory()'):
                yield value
            else:
                yield from emitted_output(value)
    elif isinstance(node, list):
        for value in node:
            yield from emitted_output(value)

outputs = list(emitted_output(json.loads((base/'soak/action.log').read_text())))
assert len(outputs) == 1, 'Expected exactly one sustained comparison test output'
text = outputs[0]
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
    sample = json.loads((out/'memory-diagnostics'/f'cycle-{cycle}.json').read_text())
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

assert len(pixels) == sum('selection=difference,' in line for line in scopes)
assert len(resumes) == 6
assert all(n == 291600 for n in numbers(r'pixels=(\d+)', pixels+resumes))
write('stats.json', dict(accepted=not rejected, memoryGatePassed=memory_passed,
    cadenceGatePassed=cadence_passed, clockGatePassed=clock_passed, loupeWindows=len(loupe), scopeWindows=len(scopes),
    sampledDifferencePublications=len(pixels), resumedDifferencePublications=len(resumes),
    pixelsPerSample=291600, minimumLoupePresentationsPerSecond=min(fps), maximumFollowerDriftSeconds=max(drift),
    usableClockSamples=int(sum(valid)), totalClockSamples=len(valid)*30,
    minimumMeasuredSecondsPerSelection=min(coverage.values()), measuredSelections=len(coverage),
    cycleEndFootprintBytes=[int(n) for n in footprints], maximumCycleEndGrowthBytes=int(max(footprints)-footprints[0]),
    scopeConfiguration=dict(resolution=720, targetFPS=15, secondsPerSelection=10, cycles=3)))
