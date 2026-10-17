#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain this continuation's accepted local run: retain.py NEW_RUN_ROOT."""
import gzip
import hashlib
import json
import itertools
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path.cwd()
base = Path(sys.argv[1]).resolve(strict=True)
out = Path(__file__).resolve().parent

def sha(path):
    return hashlib.file_digest(Path(path).open('rb'), 'sha256').hexdigest()

def write(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def command(*args):
    return subprocess.check_output(args, text=True).strip()

shutil.copyfile(base/'runner-regressions.log', out/'runner-regressions.log')

for name in ('focused', 'soak'):
    run = base / ('focused-isolated' if name == 'focused' else 'soak-isolated')
    summary = json.loads(command('xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(run/'tests.xcresult')))
    assert summary['result'] == 'Passed' and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
    assert summary['passedTests'] == (68 if name == 'focused' else 1), summary
    write(name+'-summary.json', summary)
    for source, target in [('xcodebuild.log', name+'-tests.log.gz'), ('action.log', name+'-action.log.gz')]:
        (out/target).write_bytes(gzip.compress((run/source).read_bytes(), mtime=0))
    for file in ('executed-configuration.plist', 'command.json'):
        shutil.copyfile(run/file, out/(name+'-'+file))
    shutil.copyfile(base/('focused-isolated-runner.log' if name == 'focused' else 'soak-isolated-runner.log'), out/(name+'-runner.log'))

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

outputs = list(emitted_output(json.loads((base/'soak-isolated/action.log').read_text())))
assert len(outputs) == 1, 'Expected exactly one sustained comparison test output'
text = outputs[0]
required = [
    'MPV_LIVE_LOUPE_COMPARISON_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per mode,',
    'MPV_COMPARISON_ACTIVE_SCOPES_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 3 scope sources, 10 seconds per selection, resolution=1440, targetFPS=30',
    'MPV_COMPARISON_SCOPE_PROVENANCE_SOAK_ACCEPTANCE: 3 cycles, 2 pairs, 3 modes, 10 seconds per selection, resolution=1440, targetFPS=30, exact difference pixels and occupied bins, capture retirement and resume']
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
assert all('resolution=1440, targetFPS=30,' in line for line in scopes)
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
assert len(footprints) == 3 and max(footprints) - footprints[0] <= 268435456
assert min(fps) >= 45 and max(drift) <= .1 and min(valid) >= 29
assert len(pixels) == sum('selection=difference,' in line for line in scopes)
assert len(resumes) == 6
assert all(n == 1166400 for n in numbers(r'pixels=(\d+)', pixels+resumes))
write('stats.json', dict(loupeWindows=len(loupe), scopeWindows=len(scopes),
    sampledDifferencePublications=len(pixels), resumedDifferencePublications=len(resumes),
    pixelsPerSample=1166400, minimumLoupePresentationsPerSecond=min(fps), maximumFollowerDriftSeconds=max(drift),
    usableClockSamples=int(sum(valid)), totalClockSamples=len(valid)*30,
    minimumMeasuredSecondsPerSelection=min(coverage.values()), measuredSelections=len(coverage),
    cycleEndFootprintBytes=[int(n) for n in footprints], maximumCycleEndGrowthBytes=int(max(footprints)-footprints[0]),
    scopeConfiguration=dict(resolution=1440, targetFPS=30, secondsPerSelection=10, cycles=3)))

sources = {}
for folder in ('Aagedal Media Player', 'Aagedal Media Player Tests'):
    for path in sorted((root/folder).rglob('*.swift')):
        relative = str(path.relative_to(root))
        assert sha(path) == sha(base/'app'/relative), relative
        sources[relative] = sha(path)
app = base/'derived/Build/Products/Release/Aagedal Media Player.app'
binaries = {}
for path in [app/'Contents/MacOS/Aagedal Media Player', app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests']:
    architecture = command('lipo', '-archs', str(path))
    assert architecture == 'arm64', architecture
    binaries[str(path.relative_to(app))] = dict(sha256=sha(path), architecture=architecture)
previous = json.loads((root/'docs/evidence/mpv-comparison-scope-provenance-20261016/candidate-receipt.json').read_text())
fixtures = previous['fixturesSHA256']
for path, expected in fixtures.items():
    assert sha(path) == expected, path
libmpv = Path('/private/tmp/aagedal-scopes-delta-restored-r3-20261015/MPVKit/Candidate/Libmpv-GPL/Libmpv.xcframework/macos-arm64/Libmpv.framework/Versions/A/Libmpv')
assert sha(libmpv) == previous['libmpvSHA256']
shutil.copyfile(base/'prepare.py', out/'prepare.py')
for name in ('build.log', 'build-bounded-oracle.log', 'build-isolated-settings.log'):
    (out/(name+'.gz')).write_bytes(gzip.compress((base/name).read_bytes(), mtime=0))
write('candidate-receipt.json', dict(sourceCommit=command('git', 'rev-parse', 'HEAD'), sourceFilesSHA256=sources,
    binaries=binaries, libmpvSHA256=sha(libmpv), fixturesSHA256=fixtures,
    fixtureManifestsSHA256={str(p):sha(p) for p in [base/'native-fixtures.json', Path('/private/tmp/aagedal-loupe-playback-60fps/live-viewer-fixtures.json')]},
    dependencyDescriptorsSHA256={p:sha(root/p) for p in previous['dependencyDescriptorsSHA256']},
    validationScriptsSHA256={p:sha(root/p) for p in ['scripts/validate-mpv-native-app.py', 'scripts/test-mpv-native-app-runner.py',
        'docs/evidence/mpv-comparison-scope-provenance-20261016/run.py', str(out.relative_to(root)/'prepare.py'), str(out.relative_to(root)/'retain.py')]},
    host=dict(sw_vers=command('sw_vers'), architecture=command('uname', '-m'), cpu=command('sysctl','-n','machdep.cpu.brand_string'), memoryBytes=command('sysctl','-n','hw.memsize')),
    buildLogSHA256={name:sha(base/name) for name in ('build.log', 'build-bounded-oracle.log', 'build-isolated-settings.log')}))
patch = subprocess.check_output(['git','diff','HEAD','--','Aagedal Media Player','Aagedal Media Player Tests','scripts/validate-mpv-native-app.py','scripts/test-mpv-native-app-runner.py'])
(out/'source.patch.gz').write_bytes(gzip.compress(patch, mtime=0))
print('Retained accepted focused and sustained runs; source/binary/fixture checks passed')
